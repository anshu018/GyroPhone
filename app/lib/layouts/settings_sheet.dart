import 'package:flutter/material.dart';

import '../hid/wheel_frame.dart';

/// Minimal live wheel settings (M2 spec R8): range, deadzone, sensitivity,
/// response-curve preset, steering-axis mode. Every change applies instantly
/// over the channel; persistence is M3 (Ver-1 Step 7). Look is temporary per
/// the UIUX interim rule.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.params, required this.onChanged});

  final WheelParams params;
  final void Function(WheelParams params) onChanged;

  WheelParams _with({double? rangeDeg, double? deadzoneDeg, double? sensitivity, String? curve, String? axisMode}) =>
      WheelParams(
        rangeDeg: rangeDeg ?? params.rangeDeg,
        deadzoneDeg: deadzoneDeg ?? params.deadzoneDeg,
        sensitivity: sensitivity ?? params.sensitivity,
        curve: curve ?? params.curve,
        axisMode: axisMode ?? params.axisMode,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Wheel settings', style: Theme.of(context).textTheme.titleMedium),
            _slider(
              label: 'Range — ${params.rangeDeg.toStringAsFixed(0)}°',
              value: params.rangeDeg,
              min: WheelParams.minRangeDeg,
              max: WheelParams.maxRangeDeg,
              divisions: 27, // 30° steps: 90…900
              onChanged: (v) => onChanged(_with(rangeDeg: v)),
            ),
            _slider(
              label: 'Deadzone — ${params.deadzoneDeg.toStringAsFixed(1)}°',
              value: params.deadzoneDeg,
              min: 0,
              max: 10,
              divisions: 20,
              onChanged: (v) => onChanged(_with(deadzoneDeg: v)),
            ),
            _slider(
              label: 'Sensitivity — ×${params.sensitivity.toStringAsFixed(2)}',
              value: params.sensitivity,
              min: 0.4,
              max: 2.5,
              divisions: 42,
              onChanged: (v) => onChanged(_with(sensitivity: v)),
            ),
            const SizedBox(height: 8),
            _segmented(
              label: 'Response curve',
              labels: const {'linear': 'Linear', 'soft': 'Soft', 'sharp': 'Sharp'},
              selected: params.curve,
              onChanged: (v) => onChanged(_with(curve: v)),
            ),
            const SizedBox(height: 8),
            _segmented(
              label: 'Steering axis',
              labels: const {'auto': 'Auto', 'flat': 'Flat', 'cradle': 'Cradle'},
              selected: params.axisMode,
              onChanged: (v) => onChanged(_with(axisMode: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _segmented({
    required String label,
    required Map<String, String> labels,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: [
            for (final entry in labels.entries)
              ButtonSegment(value: entry.key, label: Text(entry.value)),
          ],
          selected: {selected},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}
