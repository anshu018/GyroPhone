import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hid/hid_bridge.dart';
import 'layouts/status_screen.dart';

void main() {
  runApp(const GyroPhoneApp());
}

class GyroPhoneApp extends StatefulWidget {
  const GyroPhoneApp({super.key});

  @override
  State<GyroPhoneApp> createState() => _GyroPhoneAppState();
}

class _GyroPhoneAppState extends State<GyroPhoneApp> with WidgetsBindingObserver {
  late final HidBridge _bridge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const methods = MethodChannel('gyrophone/hid');
    const events = EventChannel('gyrophone/hid_events');
    _bridge = HidBridge(
      invoke: (method, [args]) => methods.invokeMethod(method, args),
      eventStream: () =>
          events.receiveBroadcastStream().map((event) => event as Map<Object?, Object?>),
    );
    unawaited(_bridge.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_bridge.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS unregisters the HID app when we leave the foreground; the bridge
    // re-registers on resume (docs/specs/M1-pair-as-ds4.md R2/R7).
    if (state == AppLifecycleState.resumed) {
      _bridge.appResumed();
    } else if (state == AppLifecycleState.paused) {
      _bridge.appPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GyroPhone',
      theme: ThemeData.dark(),
      home: StatusScreen(bridge: _bridge),
    );
  }
}
