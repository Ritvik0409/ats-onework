import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/portal_shell.dart';
import 'package:ats_onework/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shell has to work on a phone, on a tablet and on a wide desktop
/// window. These tests pin the two navigation shapes down: a bottom bar
/// with a More sheet below 900 logical pixels, a rail at 900 and above.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'organization_id': 1,
    });
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      <String, String>{},
    );
  });

  /// A user with enough capabilities to overflow a phone's bottom bar but
  /// not so many that the wide rail breaks.
  void signIn({List<String> permissions = const <String>[]}) {
    ExpenseStore.instance.setUserAccess(
      roles: const <String>['admin'],
      permissions: permissions.isEmpty
          ? const <String>[
              'expense.read_all',
              'expense.approve',
              'expense.read_own',
              'expense.create',
              'project.read',
              'project.manage',
              'reimbursement.read_all',
              'role.manage',
              'user.manage',
              'budget.manage',
            ]
          : permissions,
    );
  }

  /// A plain employee only reaches the navigation once the server has told
  /// the store which projects they belong to.
  void signInEmployee() {
    final ExpenseStore store = ExpenseStore.instance;
    store.setUserAccess(
      roles: const <String>['employee'],
      permissions: const <String>['expense.read_own', 'expense.create'],
    );
    store.currentUserId = '42';
    store.projectsLoaded = true;
    store.projects = <ProjectRecord>[
      ProjectRecord(
        id: 'p1',
        name: 'Q4 Launch',
        budget: 1000,
        assignedEmails: const <String>['42'],
        isActive: true,
      ),
    ];
    store.notifyListeners();
  }

  void setWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const PortalShell()),
    );
    // The shell listens to the store, so the first frame needs a settle.
    await tester.pump();
  }

  List<String> bottomBarLabels(WidgetTester tester) => tester
      .widgetList<NavigationDestination>(find.byType(NavigationDestination))
      .map((NavigationDestination d) => d.label)
      .toList(growable: false);

  testWidgets('a phone gets a bottom bar with a More destination', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(390, 844));
    signIn();
    await pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    // Four primary destinations plus the always-present More.
    expect(bar.destinations, hasLength(5));
    expect(
      bottomBarLabels(tester),
      containsAll(<String>['Home', 'Review', 'My claims', 'Add', 'More']),
    );
  });

  testWidgets('the More sheet lists the destinations the bar cannot show', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(390, 844));
    signIn();
    await pumpShell(tester);

    await tester.tap(find.text('More'));
    // A skeleton or a spinner keeps animating, so the sheet is opened with
    // a plain pump instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Overflow destinations: Projects, Paid, Access, Profile.
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Access'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // The account section is always there.
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Dark theme'), findsOneWidget);
  });

  testWidgets('a wide window gets a rail instead of a bottom bar', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1000, 800));
    signIn();
    await pumpShell(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    final NavigationRail rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    // At most five destinations fit the rail; the rest live in More.
    expect(rail.destinations.length, lessThanOrEqualTo(5));
    expect(rail.extended, isFalse);
  });

  testWidgets('a very wide window extends the rail', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1400, 900));
    signIn();
    await pumpShell(tester);

    final NavigationRail rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(rail.extended, isTrue);
  });

  testWidgets('an employee with few capabilities still gets a usable bar', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(360, 780));
    signInEmployee();
    await pumpShell(tester);

    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    // Home, My claims, Add, Profile + More.
    expect(bar.destinations, hasLength(5));
    expect(
      bottomBarLabels(tester),
      containsAll(<String>['Home', 'My claims', 'Add', 'Profile', 'More']),
    );
  });
}
