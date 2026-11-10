import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:gyrophone/hid/hid_bridge.dart';
import 'package:gyrophone/hid/hid_log.dart';
import 'package:gyrophone/hid/wheel_frame.dart';

/// Records every platform-channel call and answers like the real plugin.
class FakePlugin {
  final List<(String, dynamic)> calls = [];

  bool permissionGranted = true;
  bool registerFails = false;
  List<Map<String, Object?>> hosts = const [];

  Future<dynamic> call(String method, [dynamic args]) async {
    calls.add((method, args));
    switch (method) {
      case 'ensurePermissions':
        // The real plugin returns false for a denied permission; it only
        // throws for unexpected conditions (no activity, busy).
        return permissionGranted;
      case 'register':
        if (registerFails) {
          throw PlatformException(code: 'bt-off', message: 'adapter off');
        }
        return 'sent';
      case 'connect':
        return true;
      case 'getHosts':
        return hosts;
      case 'setWheelParams':
      case 'reZero':
      case 'setPedals':
      case 'setStreaming':
        return true;
      default:
        throw StateError('unexpected method $method');
    }
  }

  int count(String method) => calls.where((c) => c.$1 == method).length;
}

void main() {
  FakePlugin plugin = FakePlugin();
  HidBridge bridge = _makeBridge(plugin);

  setUp(() {
    plugin = FakePlugin();
    bridge = _makeBridge(plugin);
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  /// Starts the bridge and delivers the appStatus(registered: true) event the
  /// OS sends after a successful registerApp — the documented truth source.
  Future<void> startAndRegister() async {
    await bridge.start();
    await pump();
    bridge.handlePlatformEvent({'event': 'appStatus', 'registered': true});
    await pump();
  }

  void connectHost() {
    bridge.handlePlatformEvent({
      'event': 'connectionState',
      'address': 'AA:BB:CC:DD:EE:FF',
      'name': 'PC',
      'state': 'connected',
    });
  }

  group('HidBridge state machine', () {
    test('permission denied → unregistered, no register call', () async {
      plugin.permissionGranted = false;
      await bridge.start();
      await pump();
      expect(bridge.state, HidState.unregistered);
      expect(plugin.count('register'), 0);
    });

    test('Bluetooth off at register → unregistered (not error)', () async {
      plugin.registerFails = true;
      await bridge.start();
      await pump();
      expect(bridge.state, HidState.unregistered);
    });

    test('registration flow reaches registered, then host connection arms the hot loop', () async {
      await startAndRegister();
      expect(bridge.state, HidState.registered);
      expect(plugin.count('register'), 1);

      connectHost();
      expect(bridge.state, HidState.connected);
      expect(bridge.hostName, 'PC');
      await pump();
      expect(plugin.count('setStreaming'), 1, reason: 'connect arms the native sender');
      expect((plugin.calls.last.$2 as Map)['enabled'], isTrue);
    });

    test('native streaming event promotes connected → streaming', () async {
      await startAndRegister();
      connectHost();
      bridge.handlePlatformEvent({'event': 'streaming'});
      expect(bridge.state, HidState.streaming);
    });

    test('streaming event while merely registered is ignored', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({'event': 'streaming'});
      expect(bridge.state, HidState.registered);
    });

    test('registered without a host discovers bonded hosts and connects', () async {
      plugin.hosts = [
        {'address': '11:22:33:44:55:66', 'name': 'PC', 'state': 'disconnected'},
      ];
      await startAndRegister();
      expect(bridge.state, HidState.registered);
      expect(plugin.count('connect'), 1);
      expect(bridge.hostAddress, '11:22:33:44:55:66');
    });

    test('disconnect returns to registered and reconnects without restart', () async {
      await startAndRegister();
      connectHost();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'disconnected',
      });
      await pump();
      expect(bridge.state, HidState.registered);
      expect(plugin.count('connect'), 1, reason: 'one reconnect attempt for the known host');
    });

    test('Bluetooth off unregisters; Bluetooth on re-registers', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({'event': 'btState', 'state': 'off'});
      expect(bridge.state, HidState.unregistered);

      bridge.handlePlatformEvent({'event': 'btState', 'state': 'on'});
      await pump();
      expect(plugin.count('register'), 2, reason: 're-registered after BT came back');

      bridge.handlePlatformEvent({'event': 'appStatus', 'registered': true});
      expect(bridge.state, HidState.registered);
    });

    test('app backgrounded unregister waits for resume, then re-registers', () async {
      await startAndRegister();
      bridge.appPaused();
      await pump();
      expect(plugin.count('setStreaming'), greaterThanOrEqualTo(1), reason: 'pause disarms the hot loop');
      bridge.handlePlatformEvent({'event': 'appStatus', 'registered': false});
      expect(bridge.state, HidState.unregistered);
      expect(plugin.count('register'), 1, reason: 'backgrounded: re-register waits for resume');

      bridge.appResumed();
      await pump();
      expect(plugin.count('register'), 2);

      bridge.handlePlatformEvent({'event': 'appStatus', 'registered': true});
      expect(bridge.state, HidState.registered);
    });

    test('appResumed while linked re-arms the hot loop', () async {
      await startAndRegister();
      connectHost();
      bridge.handlePlatformEvent({'event': 'streaming'});
      final before = plugin.count('setStreaming');
      bridge.appPaused();
      await pump();
      bridge.appResumed();
      await pump();
      expect(plugin.count('setStreaming'), greaterThan(before));
      expect((plugin.calls.last.$2 as Map)['enabled'], isTrue, reason: 'resume re-arms while linked');
      expect(bridge.state, HidState.streaming);
    });

    test('repeated foreground unregistration stops auto-retrying', () async {
      await startAndRegister();
      for (var i = 0; i < 5; i++) {
        bridge.handlePlatformEvent({'event': 'appStatus', 'registered': false});
        await pump();
      }
      expect(
        plugin.count('register'),
        4,
        reason: 'bounded retries: 1 initial + 3 re-registers, then give up',
      );
      expect(bridge.state, HidState.unregistered);
    });

    test('appStatus(registered) while streaming does not regress the state', () async {
      await startAndRegister();
      connectHost();
      bridge.handlePlatformEvent({'event': 'streaming'});
      expect(bridge.state, HidState.streaming);

      bridge.handlePlatformEvent({'event': 'appStatus', 'registered': true});
      expect(bridge.state, HidState.streaming, reason: 're-registration while linked must not lie');
    });

    test('failed host connect triggers bounded device-initiated retries', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'disconnected',
      });
      await pump();
      expect(plugin.count('connect'), 0, reason: 'retry is delayed, not immediate');
      await Future<void>.delayed(bridge.connectRetryDelay);
      expect(plugin.count('connect'), 1, reason: 'one device-initiated attempt after the delay');

      // Bounded: further failed host attempts must not retry forever.
      for (var i = 0; i < 3; i++) {
        bridge.handlePlatformEvent({
          'event': 'connectionState',
          'address': 'AA:BB:CC:DD:EE:FF',
          'name': 'PC',
          'state': 'disconnected',
        });
        await Future<void>.delayed(bridge.connectRetryDelay);
      }
      expect(plugin.count('connect'), 3, reason: '3 bounded attempts, then give up');
    });

    test('host requests are logged, not lost', () async {
      bridge.handlePlatformEvent({
        'event': 'hostRequest',
        'kind': 'interruptData',
        'id': 0x11,
        'length': 77,
      });
      final messages = bridge.log.entries.map((e) => e.message);
      expect(messages.join('\n'), contains('interruptData'));
      expect(messages.join('\n'), contains('length=77'));
    });

    test('state transitions are logged', () async {
      await startAndRegister();
      final messages = bridge.log.entries.map((e) => e.message).join('\n');
      expect(messages, contains('registering'));
      expect(messages, contains('registered'));
    });
  });

  group('HidBridge M2 commands', () {
    test('setWheelParams forwards the parameter map', () async {
      const params = WheelParams(
        rangeDeg: 450,
        deadzoneDeg: 2,
        sensitivity: 1.5,
        curve: 'soft',
        axisMode: 'cradle',
      );
      await bridge.setWheelParams(params);
      expect(plugin.count('setWheelParams'), 1);
      final args = plugin.calls.last.$2 as Map;
      expect(args['range'], 450);
      expect(args['deadzone'], 2);
      expect(args['sensitivity'], 1.5);
      expect(args['curve'], 'soft');
      expect(args['axisMode'], 'cradle');
      expect(bridge.wheelParams, same(params));
    });

    test('reZero and setPedals reach the channel', () async {
      await bridge.reZero();
      await bridge.setPedals(255, 0);
      expect(plugin.count('reZero'), 1);
      expect(plugin.count('setPedals'), 1);
      expect((plugin.calls.last.$2 as Map)['throttle'], 255);
      expect((plugin.calls.last.$2 as Map)['brake'], 0);
    });

    test('bondedHosts parses getHosts', () async {
      plugin.hosts = [
        {'address': 'AA:BB', 'name': 'PC', 'state': 'disconnected'},
      ];
      final hosts = await bridge.bondedHosts();
      expect(hosts, hasLength(1));
      expect(hosts.single.address, 'AA:BB');
      expect(hosts.single.name, 'PC');
      expect(hosts.single.state, 'disconnected');
    });

    test('wheel stream updates the frame notifier', () async {
      final controller = StreamController<Map<Object?, Object?>>.broadcast();
      final bridgeWithWheel = HidBridge(
        invoke: plugin.call,
        eventStream: () => const Stream<Map<Object?, Object?>>.empty(),
        wheelStream: () => controller.stream,
        log: HidLog(),
      );
      await bridgeWithWheel.start();
      controller.add({'angle': 123.5, 'avg': 2.0, 'p95': 4.0, 'n': 128, 'sensorHz': 248.0});
      await pump();
      final frame = bridgeWithWheel.wheelFrame.value;
      expect(frame.angleDeg, 123.5);
      expect(frame.avgMs, 2.0);
      expect(frame.p95Ms, 4.0);
      expect(frame.samples, 128);
      expect(frame.sensorHz, 248.0);
      await controller.close();
      await bridgeWithWheel.dispose();
    });

    test('telemetry label formats when reports exist', () async {
      const frame = WheelFrame(angleDeg: 1, avgMs: 1.234, p95Ms: 5.678, samples: 128, sensorHz: 249.1);
      expect(frame.telemetryLabel, contains('n=128'));
      expect(frame.telemetryLabel, contains('avg=1.23ms'));
      expect(frame.telemetryLabel, contains('p95=5.68ms'));
      expect(const WheelFrame(angleDeg: 0).telemetryLabel, contains('no reports'));
    });
  });
}

HidBridge _makeBridge(FakePlugin plugin) => HidBridge(
      invoke: plugin.call,
      eventStream: () => const Stream<Map<Object?, Object?>>.empty(),
      log: HidLog(),
      connectRetryDelay: const Duration(milliseconds: 50),
    );
