import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gyrophone/main.dart';

void main() {
  testWidgets('wheel cockpit renders with status chip and pedals', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Answer the platform channels so start() completes deterministically;
    // no appStatus event arrives in tests, so the state stays "registering".
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gyrophone/hid'),
      (call) async {
        switch (call.method) {
          case 'ensurePermissions':
          case 'register':
          case 'connect':
          case 'setWheelParams':
          case 'reZero':
          case 'setPedals':
          case 'setStreaming':
            return true;
          case 'getHosts':
            return <Map<String, Object?>>[];
        }
        return null;
      },
    );

    await tester.pumpWidget(const GyroPhoneApp());
    await tester.pump();

    expect(find.text('registering…'), findsOneWidget, reason: 'status chip is the loudest element');
    expect(find.text('THROTTLE'), findsOneWidget);
    expect(find.text('BRAKE'), findsOneWidget);
    expect(find.text('RE-ZERO'), findsOneWidget);
  });
}
