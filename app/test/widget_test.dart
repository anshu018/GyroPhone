import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gyrophone/main.dart';

void main() {
  testWidgets('status screen renders with the pairing guide', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Answer the platform channel so start() completes deterministically;
    // no appStatus event arrives in tests, so the state stays "registering".
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('gyrophone/hid'),
      (call) async {
        switch (call.method) {
          case 'ensurePermissions':
          case 'register':
          case 'connect':
          case 'sendReport':
            return true;
          case 'getHosts':
            return <Map<String, Object?>>[];
        }
        return null;
      },
    );

    await tester.pumpWidget(const GyroPhoneApp());
    await tester.pumpAndSettle();

    expect(find.text('Pair from the PC:'), findsOneWidget);
    expect(find.text('Enable controller mode'), findsOneWidget);
    expect(find.text('not connected to a PC'), findsOneWidget);
  });
}
