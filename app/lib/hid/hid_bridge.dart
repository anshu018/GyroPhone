import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException, PlatformException;

import 'ds4_report.dart';
import 'hid_log.dart';

/// Connection lifecycle of the emulated DS4 (docs/specs/M1-pair-as-ds4.md R7).
enum HidState {
  uninitialized,
  unregistered,
  registering,
  registered,
  connected,
  streaming,
  error;

  bool get isLinked => this == connected || this == streaming;
}

/// Rolling latency statistics for the input path (spec R9).
class LatencyStats {
  const LatencyStats({required this.samples, required this.avgMs, required this.p95Ms});

  final int samples;
  final double avgMs;
  final double p95Ms;

  @override
  String toString() => 'n=$samples avg=${avgMs.toStringAsFixed(2)}ms p95=${p95Ms.toStringAsFixed(2)}ms';
}

/// Dart side of the HID platform bridge: owns the connection state machine,
/// dedupes and sends input reports, and records input-path latency.
///
/// The platform interaction is injected as functions so the state machine is
/// unit-testable without the Flutter test binding. [start] wires the real
/// channels; tests drive [handlePlatformEvent] and inject a fake [invoke].
class HidBridge {
  HidBridge({
    required this._invoke,
    required this._eventStream,
    HidLog? log,
    this.connectRetryDelay = const Duration(seconds: 2),
  }) : log = log ?? HidLog();

  static const int _latencySampleCapacity = 128;

  final Future<dynamic> Function(String method, [dynamic args]) _invoke;
  final Stream<Map<Object?, Object?>> Function() _eventStream;
  final HidLog log;
  final Ds4ReportPacker _packer = Ds4ReportPacker();
  final List<double> _latencySamples = [];
  StreamSubscription<Map<Object?, Object?>>? _eventSubscription;

  /// Delay between device-initiated connect attempts (injectable for tests).
  final Duration connectRetryDelay;
  static const int _maxHostConnectAttempts = 3;

  HidState _state = HidState.uninitialized;

  /// Last known host, kept across disconnects so reconnection can target it.
  String? hostAddress;
  String? hostName;

  /// Set by the app lifecycle (main.dart); the OS auto-unregisters a
  /// backgrounded app, so re-registration only makes sense in foreground.
  bool appInForeground = true;
  bool _registerInFlight = false;
  bool _pendingReRegister = false;
  int _foregroundUnregisterStreak = 0;

  HidState get state => _state;

  /// Input-path latency of the most recent sends, oldest first (ms).
  List<double> get latencySamples => List.unmodifiable(_latencySamples);

  LatencyStats get latencyStats {
    if (_latencySamples.isEmpty) {
      return const LatencyStats(samples: 0, avgMs: 0, p95Ms: 0);
    }
    final sorted = [..._latencySamples]..sort();
    final avg = _latencySamples.reduce((a, b) => a + b) / _latencySamples.length;
    final p95Index = (sorted.length * 0.95).ceil() - 1;
    return LatencyStats(samples: sorted.length, avgMs: avg, p95Ms: sorted[p95Index]);
  }

  /// Requests permissions, registers with the DS4 SDP record, and starts
  /// listening for platform events. Safe to call again after a failure —
  /// that is what the status screen's retry button does.
  Future<void> start() async {
    _eventSubscription ??= _eventStream().listen(handlePlatformEvent, onError: (Object e) {
      log.error('event stream error', e);
      _transition(HidState.error, 'platform event stream failed');
      // A dead subscription must not linger: the next start() re-subscribes,
      // otherwise every later retry runs against a closed channel.
      unawaited(_eventSubscription?.cancel());
      _eventSubscription = null;
    });
    await _ensurePermissionsAndRegister();
  }

  Future<void> dispose() async {
    _hostConnectTimer?.cancel();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Called by the app lifecycle observer (main.dart).
  void appResumed() {
    appInForeground = true;
    if (_state == HidState.unregistered || _state == HidState.error) {
      log.state('app resumed — re-registering');
      _ensurePermissionsAndRegister();
    }
  }

  /// Called by the app lifecycle observer (main.dart).
  void appPaused() {
    appInForeground = false;
  }

  /// Asks the OS to make the phone discoverable (system consent dialog over
  /// our activity). Pairing must happen while the app is foreground — see the
  /// Pitfalls section of docs/specs/M1-pair-as-ds4.md.
  Future<bool> makeDiscoverable() async {
    try {
      final allowed = await _invoke('requestDiscoverable') as bool? ?? false;
      log.state(allowed ? 'discoverable for 5 minutes — pair from the PC now' : 'discoverable request denied');
      return allowed;
    } on PlatformException catch (e) {
      log.error('discoverable request failed', e);
      return false;
    }
  }

  /// Packs and sends [state] if it differs from the last sent input.
  /// Returns true when a report went out. Measured end-to-end over the
  /// platform channel (touch → report handed to the BT stack), which is the
  /// phone-attributable portion of the <10 ms budget (spec R9).
  Future<bool> sendState(Ds4ReportState state) async {
    if (!_state.isLinked) return false;
    if (hostAddress == null) return false;

    // Fresh buffer per send: the packer reuses its scratch, but a second
    // sendState while this invoke is in flight must not mutate bytes the codec
    // may still be encoding. Touch-rate traffic makes the copy irrelevant;
    // the no-allocation invariant binds the M2 sensor hot path.
    if (!_packer.packIfChanged(state, _sendBuffer)) return false;
    final payload = Uint8List.fromList(_sendBuffer);

    final watch = Stopwatch()..start();
    try {
      final sent = await _invoke('sendReport', {
        'address': hostAddress,
        'id': Ds4ReportPacker.reportIdSmall,
        'data': payload,
      }) as bool? ?? false;
      if (!sent) {
        // The stack refused the report (Bluetooth dropped mid-send, stale
        // proxy). The dedupe must not believe this input was delivered.
        _packer.invalidateLastSent();
        log.bluetooth('sendReport rejected by the stack');
        return false;
      }
      watch.stop();
      _recordLatency(watch.elapsedMicroseconds / 1000.0);
      if (_state == HidState.connected) {
        _transition(HidState.streaming, 'first report sent — streaming');
      }
      return true;
    } on PlatformException catch (e) {
      _packer.invalidateLastSent();
      _transition(HidState.error, 'sendReport failed: ${e.code}');
      return false;
    } on MissingPluginException {
      _packer.invalidateLastSent();
      _transition(HidState.unregistered, 'platform channel unavailable during send');
      return false;
    }
  }

  final Uint8List _sendBuffer = Uint8List(Ds4ReportPacker.payloadSize);

  /// Entry point for platform events; public for tests.
  void handlePlatformEvent(Map<Object?, Object?> event) {
    switch (event['event'] as String?) {
      case 'appStatus':
        _onAppStatus(event['registered'] as bool? ?? false);
      case 'connectionState':
        _onConnectionState(event);
      case 'hostRequest':
        _onHostRequest(event);
      case 'btState':
        _onBtState(event['state'] as String?);
      default:
        log.error('unknown platform event: $event');
    }
  }

  Future<void> _ensurePermissionsAndRegister() async {
    if (_registerInFlight) {
      _pendingReRegister = true;
      return;
    }
    _registerInFlight = true;
    try {
      final granted = await _invoke('ensurePermissions') as bool? ?? false;
      if (!granted) {
        _transition(HidState.unregistered, 'BLUETOOTH_CONNECT denied');
        return;
      }
      // Every attempt shows "registering"; the OS always answers with an
      // appStatus event (the documented truth source), which moves the state.
      _transition(HidState.registering, 'registering as DS4');
      await _invoke('register');
    } on PlatformException catch (e) {
      if (e.code == 'bt-off') {
        _transition(HidState.unregistered, 'Bluetooth is off — enable it and return');
      } else {
        _transition(HidState.error, 'register failed: ${e.code}');
      }
    } on MissingPluginException {
      // Engine teardown raced the call; nothing to register against.
      _transition(HidState.unregistered, 'platform channel unavailable');
    } finally {
      _registerInFlight = false;
      if (_pendingReRegister) {
        _pendingReRegister = false;
        _ensurePermissionsAndRegister();
      }
    }
  }

  void _onAppStatus(bool registered) {
    if (registered) {
      _foregroundUnregisterStreak = 0;
      if (_state.isLinked) {
        // The OS can re-emit registration success while a host is linked;
        // regressing to "registered" would lie about the connection.
        log.state('redundant appStatus(registered) while linked — ignored');
        return;
      }
      _transition(HidState.registered, 'registered as DS4 — pair from the PC now');
      _connectKnownHost();
      return;
    }
    if (!appInForeground) {
      _transition(HidState.unregistered, 'unregistered by the OS (app backgrounded)');
      return;
    }
    // The OS unregistered us while we are visibly using the controller. Retry
    // a bounded number of times; a stack that refuses registration forever
    // (OEM quirk) must not turn into a re-register loop.
    _foregroundUnregisterStreak += 1;
    if (_foregroundUnregisterStreak > 3) {
      _transition(HidState.unregistered, 'registration keeps failing — stopped auto-retrying');
      return;
    }
    log.state('unregistered by the OS while foregrounded — re-registering');
    _ensurePermissionsAndRegister();
  }

  void _onConnectionState(Map<Object?, Object?> event) {
    final address = event['address'] as String?;
    final name = event['name'] as String?;
    final platformState = event['state'] as String?;
    if (address != null) {
      hostAddress = address;
    }
    if (name != null) {
      hostName = name;
    }
    switch (platformState) {
      case 'connected':
        // Force a fresh report on (re)connect — the host's cached state is
        // whatever it last saw; a real DS4 sends a full report here.
        _packer.invalidateLastSent();
        _hostConnectAttempts = 0;
        _hostConnectTimer?.cancel();
        _transition(HidState.connected, 'host connected: ${name ?? address}');
      case 'connecting':
        log.state('host connecting: ${name ?? address}');
      case 'disconnected':
      case 'disconnecting':
        if (_state.isLinked) {
          _transition(HidState.registered, 'host disconnected — waiting for reconnect');
          _connectKnownHost();
        } else if (hostAddress != null && platformState == 'disconnected') {
          // The host's connect attempt failed before we were ever linked
          // (Windows pairs, shows connected, then drops). A device-initiated
          // connect goes through the stack's own path and recovers the common
          // first-attempt failure — bounded so a dead host cannot loop us.
          _scheduleHostConnect();
        }
      default:
        log.state('connection state: $platformState');
    }
  }

  int _hostConnectAttempts = 0;
  Timer? _hostConnectTimer;

  /// Bounded device-initiated connect attempts after a failed host attempt.
  void _scheduleHostConnect() {
    if (_hostConnectAttempts >= _maxHostConnectAttempts) {
      log.state('host connect keeps failing — stopped auto-retrying');
      return;
    }
    _hostConnectAttempts += 1;
    _hostConnectTimer?.cancel();
    _hostConnectTimer = Timer(connectRetryDelay, () {
      log.state('device-initiated connect attempt $_hostConnectAttempts/$_maxHostConnectAttempts');
      _connectKnownHost();
    });
  }

  void _onHostRequest(Map<Object?, Object?> event) {
    final kind = event['kind'];
    final id = event['id'];
    final length = event['length'];
    final details = [
      if (id != null) 'id=$id',
      if (length != null) 'length=$length',
    ].join(' ');
    log.host('host request: $kind${details.isEmpty ? '' : ' ($details)'}');
  }

  void _onBtState(String? state) {
    switch (state) {
      case 'off':
        hostAddress = null;
        hostName = null;
        _transition(HidState.unregistered, 'Bluetooth turned off');
      case 'on':
        log.bluetooth('Bluetooth turned on');
        if (appInForeground) {
          _ensurePermissionsAndRegister();
        }
      case 'turningOn':
      case 'turningOff':
        break;
      default:
        log.bluetooth('Bluetooth state: $state');
    }
  }

  /// Reconnects to a host we have seen before, covering both "already paired,
  /// app relaunched" and "connection dropped" without an app restart.
  Future<void> _connectKnownHost() async {
    if (_state != HidState.registered) return;
    try {
      final address = hostAddress;
      if (address != null) {
        await _invoke('connect', {'address': address});
        return;
      }
      // Never connected in this app run: look for a bonded host.
      final hosts = await _invoke('getHosts') as List<Object?>? ?? const [];
      for (final host in hosts) {
        final map = host as Map<Object?, Object?>;
        if (map['state'] == 'disconnected') {
          hostAddress = map['address'] as String?;
          hostName = map['name'] as String?;
          log.state('attempting connect to bonded host: ${hostName ?? hostAddress}');
          await _invoke('connect', {'address': hostAddress});
          return;
        }
      }
    } on PlatformException catch (e) {
      log.error('reconnect failed', e);
    } on MissingPluginException {
      log.state('reconnect skipped — platform channel unavailable');
    }
  }

  void _recordLatency(double ms) {
    if (_latencySamples.length == HidBridge._latencySampleCapacity) {
      _latencySamples.removeAt(0);
    }
    _latencySamples.add(ms);
  }

  void _transition(HidState next, String reason) {
    if (_state == next) return;
    _state = next;
    log.state('$_state — $reason');
  }
}
