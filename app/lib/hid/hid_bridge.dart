import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException;

import 'hid_log.dart';
import 'wheel_frame.dart';

/// The native wheel event stream (`gyrophone/wheel`): raw event maps.
typedef WheelEventStream = Stream<Map<Object?, Object?>> Function();

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

  /// Human label for the status chip (the loudest element, UIUX constraint).
  String get label => switch (this) {
        uninitialized => 'starting…',
        unregistered => 'not registered',
        registering => 'registering…',
        registered => 'pair from the PC',
        connected => 'connected',
        streaming => 'streaming',
        error => 'error',
      };
}

/// Dart side of the HID platform bridge: owns the connection state machine,
/// pushes wheel-model settings and pedal events to the native hot loop, and
/// republishes the native wheel stream for the UI.
///
/// The input reports themselves are owned by the native hot loop (ADR-012):
/// Dart never packs or sends report bytes. The platform interaction is
/// injected as functions so the state machine is unit-testable without the
/// Flutter test binding. [start] wires the real channels; tests drive
/// [handlePlatformEvent] and inject a fake [invoke].
class HidBridge extends ChangeNotifier {
  HidBridge({
    required this._invoke,
    required this._eventStream,
    this._wheelStream,
    HidLog? log,
    this.connectRetryDelay = const Duration(seconds: 2),
  })  : log = log ?? HidLog();

  final Future<dynamic> Function(String method, [dynamic args]) _invoke;
  final Stream<Map<Object?, Object?>> Function() _eventStream;
  final WheelEventStream? _wheelStream;
  final HidLog log;
  StreamSubscription<Map<Object?, Object?>>? _eventSubscription;
  StreamSubscription<Map<Object?, Object?>>? _wheelSubscription;

  /// Live fused angle + hot-loop telemetry, republished for the UI (≤60 Hz).
  final ValueNotifier<WheelFrame> wheelFrame =
      ValueNotifier<WheelFrame>(WheelFrame.neutral);

  /// Wheel-model parameters; mutations apply live over the channel (M2 spec
  /// R3/R8) — no persistence in M2, the settings screen is Ver-1 Step 7.
  WheelParams wheelParams = WheelParams.defaults;

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

  /// Requests permissions, registers with the DS4 SDP record, and starts
  /// listening for platform events. Safe to call again after a failure —
  /// that is what the connection sheet's retry does.
  Future<void> start() async {
    _eventSubscription ??= _eventStream().listen(handlePlatformEvent, onError: (Object e) {
      log.error('event stream error', e);
      _transition(HidState.error, 'platform event stream failed');
      // A dead subscription must not linger: the next start() re-subscribes,
      // otherwise every later retry runs against a closed channel.
      unawaited(_eventSubscription?.cancel());
      _eventSubscription = null;
    });
    _wheelSubscription ??= _wheelStream?.call().listen(
      (event) => wheelFrame.value = WheelFrame.fromMap(event),
      onError: (Object e) => log.error('wheel stream error', e),
    );
    await _ensurePermissionsAndRegister();
  }

  @override
  Future<void> dispose() async {
    _hostConnectTimer?.cancel();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _wheelSubscription?.cancel();
    _wheelSubscription = null;
    super.dispose();
  }

  /// Called by the app lifecycle observer (main.dart).
  void appResumed() {
    appInForeground = true;
    if (_state == HidState.unregistered || _state == HidState.error) {
      log.state('app resumed — re-registering');
      _ensurePermissionsAndRegister();
    }
    if (_state.isLinked) {
      unawaited(setStreaming(true));
    }
  }

  /// Called by the app lifecycle observer (main.dart).
  void appPaused() {
    appInForeground = false;
    // Disarm the native loop: it sends a neutral report while linked, so the
    // host never holds a held wheel or pedal from a backgrounded app
    // (M2 spec R1, extends the M1 focus-loss rule).
    unawaited(setStreaming(false));
  }

  /// Applies wheel parameters live — no re-registration, no reconnect
  /// (M2 spec R1/R8).
  Future<void> setWheelParams(WheelParams params) async {
    wheelParams = params;
    try {
      await _invoke('setWheelParams', params.toChannelArgs());
    } on PlatformException catch (e) {
      log.error('setWheelParams failed', e);
    } on MissingPluginException {
      log.state('setWheelParams skipped — platform channel unavailable');
    }
  }

  /// Re-zero: the current grip becomes "straight" (M2 spec R3).
  Future<void> reZero() async {
    try {
      await _invoke('reZero');
      log.state('wheel re-zeroed');
    } on PlatformException catch (e) {
      log.error('reZero failed', e);
    } on MissingPluginException {
      log.state('reZero skipped — platform channel unavailable');
    }
  }

  /// Pedal hold state (0 released → 255 full); merged into the owned report
  /// by the native packer (M2 spec R5).
  Future<void> setPedals(int throttle, int brake) async {
    try {
      await _invoke('setPedals', {'throttle': throttle, 'brake': brake});
    } on PlatformException catch (e) {
      log.error('setPedals failed', e);
    } on MissingPluginException {
      log.state('setPedals skipped — platform channel unavailable');
    }
  }

  /// Arms/disarms the native sender. Arming on connect; disarming sends a
  /// neutral report while linked (focus-loss rule, M2 spec R1).
  Future<void> setStreaming(bool enabled) async {
    try {
      await _invoke('setStreaming', {'enabled': enabled});
    } on PlatformException catch (e) {
      log.error('setStreaming failed', e);
    } on MissingPluginException {
      log.state('setStreaming skipped — platform channel unavailable');
    }
  }

  /// Bonded hosts for the connection sheet (M1 task 11 fold-in).
  Future<List<BondedHost>> bondedHosts() async {
    try {
      final hosts = await _invoke('getHosts') as List<Object?>? ?? const [];
      return hosts
          .map((host) => BondedHost.fromMap(host as Map<Object?, Object?>))
          .toList();
    } on PlatformException catch (e) {
      log.error('getHosts failed', e);
      return const [];
    } on MissingPluginException {
      log.state('getHosts skipped — platform channel unavailable');
      return const [];
    }
  }

  /// Device-initiated connect to a bonded host ("paired before, profile added
  /// after" — M1 spec task 11).
  Future<void> connectTo(String address) async {
    try {
      await _invoke('connect', {'address': address});
      log.state('connect requested: $address');
    } on PlatformException catch (e) {
      log.error('connect($address) failed', e);
    } on MissingPluginException {
      log.state('connect skipped — platform channel unavailable');
    }
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
      case 'streaming':
        if (_state == HidState.connected) {
          _transition(HidState.streaming, 'native hot loop is streaming');
        }
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
        // Arm the native loop: it gates on linked+armed and dedupes, so
        // arming here is idempotent and safe before any host reads.
        unawaited(setStreaming(true));
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

  void _transition(HidState next, String reason) {
    if (_state == next) return;
    _state = next;
    log.state('$_state — $reason');
    // The UI (wheel screen chrome) rebuilds on transitions only — never per
    // sensor frame.
    notifyListeners();
  }
}

/// A bonded host from `getHosts`, for the connection sheet.
class BondedHost {
  const BondedHost({required this.address, required this.name, required this.state});

  factory BondedHost.fromMap(Map<Object?, Object?> map) => BondedHost(
        address: map['address'] as String? ?? '',
        name: map['name'] as String?,
        state: map['state'] as String? ?? 'unknown',
      );

  final String address;
  final String? name;
  final String state;
}
