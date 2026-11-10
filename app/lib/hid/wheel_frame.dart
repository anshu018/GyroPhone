import 'package:flutter/foundation.dart';

/// One frame of the native wheel stream (`gyrophone/wheel`, ≤60 Hz):
/// the fused angle plus the hot loop's live telemetry (M2 spec R6/R9).
@immutable
class WheelFrame {
  const WheelFrame({
    required this.angleDeg,
    this.avgMs,
    this.p95Ms,
    this.samples = 0,
    this.sensorHz = 0,
  });

  static const neutral = WheelFrame(angleDeg: 0);

  final double angleDeg;
  final double? avgMs;
  final double? p95Ms;
  final int samples;
  final double sensorHz;

  factory WheelFrame.fromMap(Map<Object?, Object?> map) => WheelFrame(
        angleDeg: (map['angle'] as num?)?.toDouble() ?? 0,
        avgMs: (map['avg'] as num?)?.toDouble(),
        p95Ms: (map['p95'] as num?)?.toDouble(),
        samples: (map['n'] as num?)?.toInt() ?? 0,
        sensorHz: (map['sensorHz'] as num?)?.toDouble() ?? 0,
      );

  /// One-line telemetry for the on-screen readout (M2 spec R9).
  String get telemetryLabel {
    if (avgMs == null || p95Ms == null) return 'no reports yet';
    final hz = sensorHz.toStringAsFixed(0);
    return 'n=$samples avg=${avgMs!.toStringAsFixed(2)}ms '
        'p95=${p95Ms!.toStringAsFixed(2)}ms sensors=${hz}Hz';
  }
}

/// Wheel-model parameters, live-applied over the channel (M2 spec R3/R8).
/// No persistence in M2 — the settings screen lands in M3 (Ver-1 Step 7).
@immutable
class WheelParams {
  const WheelParams({
    required this.rangeDeg,
    required this.deadzoneDeg,
    required this.sensitivity,
    required this.curve,
    required this.axisMode,
  });

  static const WheelParams defaults = WheelParams(
    rangeDeg: 900,
    deadzoneDeg: 1.5,
    sensitivity: 1.0,
    curve: 'linear',
    axisMode: 'auto',
  );

  static const double minRangeDeg = 90;
  static const double maxRangeDeg = 900;

  final double rangeDeg;
  final double deadzoneDeg;
  final double sensitivity;
  final String curve; // linear | soft | sharp
  final String axisMode; // auto | flat | cradle

  Map<String, Object?> toChannelArgs() => {
        'range': rangeDeg,
        'deadzone': deadzoneDeg,
        'sensitivity': sensitivity,
        'curve': curve,
        'axisMode': axisMode,
      };
}
