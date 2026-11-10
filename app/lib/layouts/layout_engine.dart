import 'package:flutter/material.dart';

import 'schema.dart';
import 'widgets/wheel_arc.dart';

/// Renders a [LayoutDefinition] — the one engine every layout rides
/// (ADR-011). Positions are viewport fractions; the switch over the sealed
/// spec types is exhaustive, so a new widget type is a compile error until the
/// engine learns it.
class LayoutEngine extends StatelessWidget {
  const LayoutEngine({super.key, required this.definition, required this.context});

  final LayoutDefinition definition;
  final LayoutContext context;

  @override
  Widget build(BuildContext context_) {
    return LayoutBuilder(
      builder: (builderContext, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            for (final spec in definition.widgets)
              Positioned(
                left: spec.x * w,
                top: spec.y * h,
                width: spec.w * w,
                height: spec.h * h,
                child: _widgetFor(spec),
              ),
          ],
        );
      },
    );
  }

  Widget _widgetFor(WidgetSpec spec) => switch (spec) {
        WheelWidgetSpec() => ValueListenableBuilder(
            valueListenable: context.wheel,
            builder: (context, frame, _) => WheelArc(angleDeg: frame.angleDeg),
          ),
        HoldButtonSpec() => _HoldButton(
            label: spec.label,
            onChanged: (pressed) => context.onHold(spec.target, pressed),
          ),
        ActionButtonSpec() => OutlinedButton(
            onPressed: context.actions[spec.action],
            child: Text(spec.label, textAlign: TextAlign.center),
          ),
        StatusChipSpec() => InkWell(
            onTap: context.actions[ActionButtonSpec.actionConnection],
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.connection.linked
                    ? Colors.green.withValues(alpha: 0.25)
                    : Colors.red.withValues(alpha: 0.25),
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                context.connection.hostLabel == null
                    ? context.connection.stateLabel
                    : '${context.connection.stateLabel} · ${context.connection.hostLabel}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        LabelSpec() => spec.data == LabelSpec.dataTelemetry
            ? ValueListenableBuilder(
                valueListenable: context.wheel,
                builder: (context, frame, _) =>
                    Text(frame.telemetryLabel, textAlign: TextAlign.right),
              )
            : Text(
                spec.text ?? '',
                textAlign: TextAlign.center,
                textScaler: TextScaler.linear(spec.fontScale),
              ),
      };
}

/// Press-and-hold control: pressed while held, released on lift or cancel —
/// a cancelled gesture must never leave a held pedal (M1 lesson).
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.label, required this.onChanged});

  final String label;
  final void Function(bool pressed) onChanged;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.onChanged(pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        decoration: BoxDecoration(
          color: _pressed ? Theme.of(context).colorScheme.primaryContainer : Colors.black26,
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(widget.label, textAlign: TextAlign.center),
      ),
    );
  }
}
