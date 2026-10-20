import 'dart:convert';

import 'package:flutter/material.dart';

import 'shared/login_screen.dart';
import 'management/expense_store.dart';
import 'shared/portal_shell.dart';
import 'shared/api_client.dart';
import 'shared/json_utils.dart';
import 'ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Session resume: with valid tokens stored, users land directly in the
  // app shell instead of the login screen (validates via /users/me and
  // auto-refreshes an expired access token through ApiClient).
  final initialRoute = await _resolveInitialRoute();
  runApp(MyApp(initialRoute: initialRoute));
}

Future<String> _resolveInitialRoute() async {
  try {
    if (!await ApiClient.ensureSession()) return '/';

    final me = await ApiClient.get('/users/me');
    if (me.statusCode != 200) return '/'; // dead/revoked session
    final profile = json.decode(me.body) as Map<String, dynamic>;

    final email = profile['email']?.toString() ?? '';
    final name = profile['name']?.toString() ?? 'User';
    final empId = (profile['employee_id'] ?? '').toString();

    final store = ExpenseStore.instance;
    // The roles and capabilities come from the server. The portal is
    // chosen by what the user may actually do, not by a local flag.
    store.currentOrganizationId = await ApiClient.getOrganizationId();
    store.setUserAccess(
      roles: stringList(profile['roles']),
      permissions: stringList(profile['permissions']),
      superuser: profile['is_superuser'] == true,
    );
    store.currentUserName = name;
    store.currentUserEmail = email;
    store.currentUserId = empId;
    store.currentEmployeeName = name;
    store.currentEmployeeEmail = email;
    store.currentEmployeeId = empId;
    store.currentManagerName = name;
    store.currentManagerEmail = email;
    store.reloadThemePreference();
    await store.primeSessionData();

    // The shell is the same for everyone; the login screen primes the
    // working set either way. The route choice only matters as an alias
    // now, but returning the canonical one keeps it tidy.
    return '/portal_shell';
  } catch (_) {
    // Backend unreachable or corrupt state — fall back to the login
    // screen (the interceptor will offer refresh + retry in-session).
    return '/';
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.initialRoute});

  final String initialRoute;

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ExpenseStore get _store => ExpenseStore.instance;
  late bool _dark = _store.isDarkMode;

  @override
  void initState() {
    super.initState();
    // Rebuild only when the theme actually changes. Listening to every
    // store notification would rebuild the whole MaterialApp on each
    // page fetch.
    _store.addListener(_syncTheme);
    // Any 401 that survives a refresh attempt (dead refresh token) pushes
    // the login screen and wipes the stack — no more silent session death.
    ApiClient.onSessionExpired = () {
      MyApp.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/',
        (Route<dynamic> route) => false,
      );
    };
  }

  void _syncTheme() {
    if (_store.isDarkMode != _dark && mounted) {
      setState(() => _dark = _store.isDarkMode);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_syncTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ATS OneWork',
      debugShowCheckedModeBanner: false,
      navigatorKey: MyApp.navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: widget.initialRoute,
      routes: {
        '/': (context) => const UniversalLoginScreen(),
        // One portal for everyone — tabs are built from capabilities.
        // The old route names kept working as aliases; anything that
        // still pushes them gets the same shell.
        '/portal_shell': (context) => const PortalShell(),
        '/employee_shell': (context) => const PortalShell(),
        '/management_shell': (context) => const PortalShell(),
      },
    );
  }
}
