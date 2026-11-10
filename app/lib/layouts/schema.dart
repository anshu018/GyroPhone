/// The declarative layout schema — the contract of ADR-011. A layout is data:
/// widget specs with normalized positions and HID bindings, rendered by one
/// engine. The wheel layout (`wheel_layout.dart`) is the first instance;
/// M3's gamepad layout, switcher, and button remapping ride the same schema.
///
/// Positions are fractions of the viewport (0–1), so one definition fits every
/// landscape screen. HID bindings name DS4 targets (the byte map lives in the
/// M1/M2 specs and the native packer) — remapping means binding a different
/// target, never editing the DS4 map (Ver-1 Step 6 pitfall).
library;

import 'package:flutter/foundation.dart'
    show ValueListenable, VoidCallback, immutable;

import '../hid/wheel_frame.dart';

/// What a control writes to the emulated DS4.
sealed class HidTarget {
  const HidTarget();
}

/// The fused steering angle — read-only, drawn by the wheel widget.
class SteeringAxis extends HidTarget {
  const SteeringAxis();
}

/// An analog trigger byte: `r2` (throttle) or `l2` (brake).
class AnalogTrigger extends HidTarget {
  const AnalogTrigger(this.id);

  final String id;
}

/// Where and what a control is. Coordinates are viewport fractions.
sealed class WidgetSpec {
  const WidgetSpec({required this.x, required this.y, required this.w, required this.h});

  final double x;
  final double y;
  final double w;
  final double h;
}

/// The wheel graphic mirroring the fused angle at the UI stream rate.
class WheelWidgetSpec extends WidgetSpec {
  const WheelWidgetSpec({required super.x, required super.y, required super.w, required super.h});
}

/// A press-and-hold control bound to an HID target (pedals in layout v1).
class HoldButtonSpec extends WidgetSpec {
  const HoldButtonSpec({
    required super.x,
    required super.y,
    required super.w,
    required super.h,
    required this.label,
    required this.target,
  });

  final String label;
  final HidTarget target;
}

/// An in-app action (not HID): re-zero, sheets. Wired by the host screen.
class ActionButtonSpec extends WidgetSpec {
  const ActionButtonSpec({
    required super.x,
    required super.y,
    required super.w,
    required super.h,
    required this.label,
    required this.action,
  });

  static const String actionReZero = 'reZero';
  static const String actionSettings = 'settings';
  static const String actionConnection = 'connection';

  final String label;
  final String action;
}

/// Connection state + host, loudest element (UIUX constraint); taps open the
/// connection sheet.
class StatusChipSpec extends WidgetSpec {
  const StatusChipSpec({required super.x, required super.y, required super.w, required super.h});
}

/// Static text, or the live telemetry line when [data] is `telemetry`.
class LabelSpec extends WidgetSpec {
  const LabelSpec({
    required super.x,
    required super.y,
    required super.w,
    required super.h,
    this.text,
    this.data = '',
    this.fontScale = 1.0,
  });

  static const String dataTelemetry = 'telemetry';

  /// Static text shown when [data] is empty.
  final String? text;

  /// Which live value the label shows (see [dataTelemetry]).
  final String data;
  final double fontScale;
}

/// A whole layout: id, display name, and its widgets.
class LayoutDefinition {
  const LayoutDefinition({required this.id, required this.name, required this.widgets});

  final String id;
  final String name;
  final List<WidgetSpec> widgets;
}

/// What the engine's status chip shows: the loudest element on screen
/// (UIUX constraint). Derived from the bridge state + host identity.
@immutable
class ConnectionView {
  const ConnectionView({
    required this.stateLabel,
    this.hostLabel,
    this.linked = false,
  });

  static const ConnectionView disconnected = ConnectionView(stateLabel: 'starting…');

  final String stateLabel;
  final String? hostLabel;
  final bool linked;
}

/// Everything the engine needs beyond the definition itself.
class LayoutContext {
  const LayoutContext({
    required this.wheel,
    required this.connection,
    required this.actions,
    required this.onHold,
  });

  /// Live fused angle (≤60 Hz) — only the wheel widget listens, so pedals and
  /// chrome never rebuild per frame (Ver-1 Step 4 pitfall).
  final ValueListenable<WheelFrame> wheel;

  /// Connection state for the status chip (plain value; the host screen
  /// rebuilds the engine when it changes — a rare event next to the 60 Hz
  /// wheel stream).
  final ConnectionView connection;

  /// Action id → callback; the engine wires [ActionButtonSpec]s from it.
  final Map<String, VoidCallback> actions;

  /// Hold events from [HoldButtonSpec]s: target + pressed.
  final void Function(HidTarget target, bool pressed) onHold;
}
