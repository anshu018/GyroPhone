import 'schema.dart';

/// Wheel layout v1 — the first instance of the schema (ADR-011). Defined as
/// data; the engine renders it. A full cockpit: wheel arc, re-zero, pedals,
/// connection chip, telemetry, settings (M2 spec R7).
const LayoutDefinition wheelLayoutV1 = LayoutDefinition(
  id: 'wheel-v1',
  name: 'Racing wheel',
  widgets: [
    StatusChipSpec(x: 0.02, y: 0.03, w: 0.32, h: 0.11),
    LabelSpec(x: 0.60, y: 0.035, w: 0.38, h: 0.09, data: LabelSpec.dataTelemetry),
    WheelWidgetSpec(x: 0.27, y: 0.16, w: 0.46, h: 0.68),
    ActionButtonSpec(x: 0.58, y: 0.84, w: 0.14, h: 0.11, label: 'RE-ZERO', action: ActionButtonSpec.actionReZero),
    ActionButtonSpec(x: 0.90, y: 0.16, w: 0.08, h: 0.10, label: '⚙', action: ActionButtonSpec.actionSettings),
    HoldButtonSpec(x: 0.04, y: 0.78, w: 0.20, h: 0.16, label: 'BRAKE', target: AnalogTrigger('l2')),
    HoldButtonSpec(x: 0.76, y: 0.78, w: 0.20, h: 0.16, label: 'THROTTLE', target: AnalogTrigger('r2')),
  ],
);
