import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The on-screen wheel: mirrors the fused angle at the UI stream rate with no
/// animation curves (Ver-1 Step 4 pitfall — UI jank reads as input lag).
///
/// The physical range (up to 900°) cannot map linearly onto a circle, so the
/// graphic rotates over a fixed ±120° visual sweep for the full configured
/// range and the true degrees are printed under the hub. The mapping is
/// monotonic and stateless — a rendering compression, never a smoothing.
class WheelArc extends StatelessWidget {
  const WheelArc({super.key, required this.angleDeg, this.rangeDeg = 900});

  final double angleDeg;
  final double rangeDeg;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WheelPainter(angleDeg: angleDeg, rangeDeg: rangeDeg),
      child: const SizedBox.expand(),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.angleDeg, required this.rangeDeg});

  final double angleDeg;
  final double rangeDeg;

  static const double _visualSweep = 120; // ± degrees of visual rotation at full lock

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.92;
    final clamped = angleDeg.clamp(-rangeDeg / 2, rangeDeg / 2);
    final visual = clamped / (rangeDeg / 2) * _visualSweep;

    // Dim full-lock track.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.08
      ..color = Colors.white12;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi / 2 - _visualSweep * math.pi / 180,
      2 * _visualSweep * math.pi / 180,
      false,
      track,
    );

    // Wheel: rim + three spokes rotating with the angle.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(visual * math.pi / 180);
    final wheel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.10
      ..color = Colors.white70;
    canvas.drawCircle(Offset.zero, radius * 0.82, wheel);
    for (var i = 0; i < 3; i++) {
      final a = i * 2 * math.pi / 3;
      canvas.drawLine(
        Offset.zero,
        Offset(math.cos(a) * radius * 0.82, math.sin(a) * radius * 0.82),
        wheel,
      );
    }
    canvas.drawCircle(Offset.zero, radius * 0.12, wheel..style = PaintingStyle.fill);
    canvas.restore();

    // True angle, printed — the graphic is compressed, the number is not.
    final text = TextPainter(
      text: TextSpan(
        text: '${clamped.toStringAsFixed(0)}°',
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, -radius * 0.35));
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.angleDeg != angleDeg || oldDelegate.rangeDeg != rangeDeg;
}
