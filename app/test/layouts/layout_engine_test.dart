import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gyrophone/hid/wheel_frame.dart';
import 'package:gyrophone/layouts/layout_engine.dart';
import 'package:gyrophone/layouts/schema.dart';
import 'package:gyrophone/layouts/wheel_layout.dart';

void main() {
  testWidgets('wheel layout v1 renders every widget spec as data', (tester) async {
    final wheel = ValueNotifier<WheelFrame>(WheelFrame.neutral);
    var reZeroPressed = false;
    final held = <(String, bool)>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LayoutEngine(
            definition: wheelLayoutV1,
            context: LayoutContext(
              wheel: wheel,
              connection: const ConnectionView(stateLabel: 'streaming', hostLabel: 'PC'),
              actions: {
                ActionButtonSpec.actionReZero: () => reZeroPressed = true,
              },
              onHold: (target, pressed) =>
                  held.add((target is AnalogTrigger ? target.id : 'steering', pressed)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Data-driven: every spec in the definition has a live widget.
    expect(find.text('THROTTLE'), findsOneWidget);
    expect(find.text('BRAKE'), findsOneWidget);
    expect(find.text('RE-ZERO'), findsOneWidget);
    expect(find.text('streaming · PC'), findsOneWidget, reason: 'loudest element shows state + host');

    // Actions wired from the context map.
    await tester.tap(find.text('RE-ZERO'));
    expect(reZeroPressed, isTrue);

    // Hold buttons report press and release on the right target.
    final throttleCenter = tester.getCenter(find.text('THROTTLE'));
    final gesture = await tester.startGesture(throttleCenter);
    await tester.pump();
    expect(held.last, ('r2', true));
    await gesture.up();
    await tester.pump();
    expect(held.last, ('r2', false));
  });

  testWidgets('the wheel widget mirrors the fused angle with no animation', (tester) async {
    final wheel = ValueNotifier<WheelFrame>(const WheelFrame(angleDeg: 0));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LayoutEngine(
            definition: const LayoutDefinition(
              id: 't',
              name: 't',
              widgets: [WheelWidgetSpec(x: 0, y: 0, w: 1, h: 1)],
            ),
            context: LayoutContext(
              wheel: wheel,
              connection: ConnectionView.disconnected,
              actions: const {},
              onHold: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    wheel.value = const WheelFrame(angleDeg: 90);
    await tester.pump(); // one frame — no animation curves to settle through
    expect(tester.hasRunningAnimations, isFalse, reason: 'angle mirrors directly (Step 4 pitfall)');
  });
}
