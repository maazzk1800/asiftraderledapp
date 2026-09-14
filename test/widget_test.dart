import 'package:flutter_test/flutter_test.dart';
import 'package:project1ledger/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home screen shows ledger choice', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(LedgerApp(prefs: prefs));

    expect(find.text('Start your ledger'), findsOneWidget);
    expect(find.text('Choose your ledger'), findsOneWidget);
    expect(find.text('Sales ledger'), findsOneWidget);
    expect(find.text('Purchase ledger'), findsOneWidget);

    await tester.tap(find.text('Sales ledger'));
    await tester.pump();

    expect(find.text('Choose company for sales'), findsOneWidget);
  });
}
