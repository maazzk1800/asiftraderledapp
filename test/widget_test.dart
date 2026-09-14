import 'package:flutter_test/flutter_test.dart';
import 'package:project1ledger/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('welcome screen shows ledger choice', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(LedgerApp(prefs: prefs));

    expect(find.text('Ledger Studio'), findsOneWidget);
    expect(find.text('Choose your ledger'), findsOneWidget);
    expect(find.text('Sales Ledger'), findsWidgets);
    expect(find.text('Purchase Ledger'), findsWidgets);
  });
}
