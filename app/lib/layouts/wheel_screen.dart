import 'dart:async';

import 'package:flutter/material.dart';

import '../hid/hid_bridge.dart';
import '../hid/wheel_frame.dart';
import 'connection_sheet.dart';
import 'layout_engine.dart';
import 'schema.dart';
import 'settings_sheet.dart';
import 'wheel_layout.dart';

/// The racing cockpit: renders [wheelLayoutV1] through the layout engine and
/// hosts the connection/settings sheets. Look is deliberately temporary per
/// the UIUX interim rule — function first (M2 spec R7/R8).
class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key, required this.bridge});

  final HidBridge bridge;

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen> with WidgetsBindingObserver {
  /// Local settings state, live-applied; persistence is M3 (Ver-1 Step 7).
  WheelParams _params = WheelParams.defaults;

  /// Currently held pedal targets ('r2'/'l2'); both bytes re-merged on every
  /// change so releasing one pedal never forgets the other (M2 spec R5).
  final Set<String> _heldPedals = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The bridge disarms the native loop on pause (neutral report); the local
    // press state must clear with it, or the next pedal press would re-merge a
    // phantom held pedal (M1 stuck-input lesson, M2 spec R1/R5).
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _heldPedals.clear();
    }
  }

  void _onHold(HidTarget target, bool pressed) {
    switch (target) {
      case AnalogTrigger(:final id):
        pressed ? _heldPedals.add(id) : _heldPedals.remove(id);
        unawaited(widget.bridge.setPedals(
          _heldPedals.contains('r2') ? 255 : 0,
          _heldPedals.contains('l2') ? 255 : 0,
        ));
      case SteeringAxis():
        widget.bridge.log.error('steering axis is sensor-driven; hold ignored');
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SettingsSheet(
        params: _params,
        onChanged: (params) {
          setState(() => _params = params);
          unawaited(widget.bridge.setWheelParams(params));
        },
      ),
    );
  }

  void _openConnection() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ConnectionSheet(bridge: widget.bridge),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // The bridge is listenable: the engine rebuilds only on state/host
        // changes; the 60 Hz angle stream stays localized to the wheel widget
        // inside the engine (Ver-1 Step 4 pitfall).
        child: ListenableBuilder(
          listenable: widget.bridge,
          builder: (context, _) {
            final bridge = widget.bridge;
            return LayoutEngine(
              definition: wheelLayoutV1,
              context: LayoutContext(
                wheel: bridge.wheelFrame,
                connection: ConnectionView(
                  stateLabel: bridge.state.label,
                  hostLabel: bridge.hostName,
                  linked: bridge.state.isLinked,
                ),
                actions: {
                  ActionButtonSpec.actionReZero: () => unawaited(bridge.reZero()),
                  ActionButtonSpec.actionSettings: _openSettings,
                  ActionButtonSpec.actionConnection: _openConnection,
                },
                onHold: _onHold,
              ),
            );
          },
        ),
      ),
    );
  }
}
