import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:gyrophone/hid/ds4_report.dart';
import 'package:gyrophone/hid/hid_bridge.dart';
import 'package:gyrophone/hid/hid_log.dart';

/// Records every platform-channel call and answers like the real plugin.
class FakePlugin {
  final List<(String, dynamic)> calls = [];

  bool permissionGranted = true;
  bool registerFails = false;
  bool sendSucceeds = true;
  bool sendThrows = false;
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
      case 'sendReport':
        if (sendThrows) {
          throw PlatformException(code: 'send', message: 'not connected');
        }
        return sendSucceeds;
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

    test('registration flow reaches registered, then host connection', () async {
      await startAndRegister();
      expect(bridge.state, HidState.registered);
      expect(plugin.count('register'), 1);

      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'Gaming PC',
        'state': 'connected',
      });
      expect(bridge.state, HidState.connected);
      expect(bridge.hostName, 'Gaming PC');
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

    test('first send moves connected → streaming; identical input dedupes', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'connected',
      });

      final first = await bridge.sendState(Ds4ReportState.neutral);
      expect(first, isTrue);
      expect(bridge.state, HidState.streaming);

      final duplicate = await bridge.sendState(Ds4ReportState.neutral);
      expect(duplicate, isFalse);
      expect(plugin.count('sendReport'), 1);

      final changed = await bridge.sendState(Ds4ReportState.neutral.copyWith(cross: true));
      expect(changed, isTrue);
      expect(plugin.count('sendReport'), 2);
      expect(bridge.latencyStats.samples, 2);
    });

    test('sendState before a connection sends nothing', () async {
      await startAndRegister();
      expect(await bridge.sendState(Ds4ReportState.neutral), isFalse);
      expect(plugin.count('sendReport'), 0);
    });

    test('disconnect returns to registered and reconnects without restart', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'connected',
      });
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
      bridge.handlePlatformEvent({'event': 'appStatus', 'registered': false});
      expect(bridge.state, HidState.unregistered);
      expect(plugin.count('register'), 1, reason: 'backgrounded: re-register waits for resume');

      bridge.appResumed();
      await pump();
      expect(plugin.count('register'), 2);

      bridge.handlePlatformEvent({'event': 'appStatus', 'registered': true});
      expect(bridge.state, HidState.registered);
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

    test('a rejected send is not recorded as success and is re-sent later', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'connected',
      });

      plugin.sendSucceeds = false;
      final rejected = await bridge.sendState(Ds4ReportState.neutral);
      expect(rejected, isFalse, reason: 'the stack refused the report');
      expect(bridge.state, HidState.connected, reason: 'connection truth comes from events, not sends');
      expect(bridge.latencyStats.samples, 0, reason: 'a rejected send has no meaningful latency');

      plugin.sendSucceeds = true;
      final retried = await bridge.sendState(Ds4ReportState.neutral);
      expect(retried, isTrue, reason: 'the failed send must not poison the dedupe');
      expect(bridge.latencyStats.samples, 1);
    });

    test('a thrown send marks the bridge errored and invalidates the dedupe', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'connected',
      });
      await bridge.sendState(Ds4ReportState.neutral);

      plugin.sendThrows = true;
      expect(await bridge.sendState(Ds4ReportState.neutral.copyWith(cross: true)), isFalse);
      expect(bridge.state, HidState.error);
    });

    test('appStatus(registered) while streaming does not regress the state', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'connected',
      });
      await bridge.sendState(Ds4ReportState.neutral);
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

    test('sendState while merely registered sends nothing', () async {
      await startAndRegister();
      bridge.handlePlatformEvent({
        'event': 'connectionState',
        'address': 'AA:BB:CC:DD:EE:FF',
        'name': 'PC',
        'state': 'disconnected',
      });
      await pump();
      expect(await bridge.sendState(Ds4ReportState.neutral), isFalse);
      expect(plugin.count('sendReport'), 0, reason: 'no reports before the profile is linked');
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
}

HidBridge _makeBridge(FakePlugin plugin) => HidBridge(
      invoke: plugin.call,
      eventStream: () => const Stream<Map<Object?, Object?>>.empty(),
      log: HidLog(),
      connectRetryDelay: const Duration(milliseconds: 50),
    );
