import 'package:ats_onework/employee/my_requests_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/ui/app_theme.dart';
import 'package:ats_onework/ui/expense_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExpenseRecord _expense({
  String status = 'Approved',
  double amount = 1250,
  String name = 'Aarav Mehta',
  String project = 'Q4 Launch',
}) {
  return ExpenseRecord(
    id: 'EXP-42',
    name: name,
    email: 'aarav@example.com',
    employeeId: '42',
    type: 'Travel',
    amount: amount,
    date: '20 Oct 2026',
    description: 'Client visit',
    status: status,
    projectName: project,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
  });

  Widget host(Widget child, {Brightness brightness = Brightness.dark}) {
    return MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: child),
    );
  }

  testWidgets('the expense row shows the claim, its owner and its status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(SingleChildScrollView(child: ExpenseRow(expense: _expense()))),
    );

    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('Aarav Mehta · 20 Oct 2026'), findsOneWidget);
    expect(find.text('Q4 Launch'), findsOneWidget);
    expect(find.text('₹1,250'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    // An approved claim is not paid yet.
    expect(find.text('Payment pending'), findsOneWidget);
  });

  testWidgets('the row reads the same in the light theme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ExpenseRow(expense: _expense(status: 'Pending Verification')),
        ),
        brightness: Brightness.light,
      ),
    );

    expect(find.text('Travel'), findsOneWidget);
    expect(find.text('Pending Verification'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected claim can carry a reason', (
    WidgetTester tester,
  ) async {
    final ExpenseRecord rejected = _expense(status: 'Rejected');
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ExpenseRow(
            expense: rejected,
            note: const Text('Reason: missing receipt'),
          ),
        ),
      ),
    );

    expect(find.text('Reason: missing receipt'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('the claims screen shows an empty state and its filters', (
    WidgetTester tester,
  ) async {
    final ExpenseStore store = ExpenseStore.instance;
    store.expensesLoaded = true;
    store.expenses = <ExpenseRecord>[];

    await tester.pumpWidget(host(const MyRequestsScreen()));
    await tester.pump();

    expect(find.text('No claims yet'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
  });
}
