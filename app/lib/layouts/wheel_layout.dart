import 'schema.dart';

/// Wheel layout v1.1 — the first instance of the schema (ADR-011). Defined as
/// data; the engine renders it. A full cockpit: wheel arc, re-zero, pedals,
/// action buttons (gears + handbrake — LFS's default wheel bindings map
/// cross/l1/r1 to handbrake/shift-down/shift-up), connection chip, telemetry,
/// settings (M2 spec R7; buttons added after the first LFS session showed the
/// sequential-gear gap).
const LayoutDefinition wheelLayoutV1 = LayoutDefinition(
  id: 'wheel-v1',
  name: 'Racing wheel',
  widgets: [
    StatusChipSpec(x: 0.02, y: 0.03, w: 0.32, h: 0.11),
    LabelSpec(x: 0.60, y: 0.035, w: 0.38, h: 0.09, data: LabelSpec.dataTelemetry),
    WheelWidgetSpec(x: 0.30, y: 0.14, w: 0.40, h: 0.60),
    ActionButtonSpec(x: 0.58, y: 0.80, w: 0.13, h: 0.15, label: 'RE-ZERO', action: ActionButtonSpec.actionReZero),
    ActionButtonSpec(x: 0.90, y: 0.16, w: 0.08, h: 0.10, label: '⚙', action: ActionButtonSpec.actionSettings),
    HoldButtonSpec(x: 0.02, y: 0.78, w: 0.15, h: 0.17, label: 'BRAKE', target: AnalogTrigger('l2')),
    HoldButtonSpec(x: 0.18, y: 0.78, w: 0.13, h: 0.17, label: 'GEAR−', target: Ds4Button('l1')),
    HoldButtonSpec(x: 0.32, y: 0.78, w: 0.15, h: 0.17, label: 'H-BRAKE', target: Ds4Button('cross')),
    HoldButtonSpec(x: 0.72, y: 0.78, w: 0.13, h: 0.17, label: 'GEAR+', target: Ds4Button('r1')),
    HoldButtonSpec(x: 0.86, y: 0.78, w: 0.13, h: 0.17, label: 'THROTTLE', target: AnalogTrigger('r2')),
  ],
);
