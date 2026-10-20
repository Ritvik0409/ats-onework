import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/session_store.dart';
import 'package:ats_onework/shared/ats_logo.dart';
import 'package:ats_onework/shared/json_utils.dart';

/// The app's single sign-in page — the `/` route.
///
/// There is no second "management" login page: management accounts sign
/// in here too and land in the management portal, because the routing
/// decision below reads the capabilities the server reports, not which
/// screen was used. (A management_portal variant did exist, but nothing
/// ever routed to it and it began to drift — it is gone.)
class UniversalLoginScreen extends StatefulWidget {
  const UniversalLoginScreen({super.key});

  @override
  State<UniversalLoginScreen> createState() => _UniversalLoginScreenState();
}

class _UniversalLoginScreenState extends State<UniversalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _errorMessage;
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // Exact High-Contrast Palette matching your reference image
  static const Color _goldColor = Color(0xFFD4AF37);
  static const Color _darkBackground = Color(0xFF0D0D11); // True deep dark background
  static const Color _cardBackground = Color(0xFF16161F); // Distinct contrasting card box

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) return;

    final input = _idController.text.trim();
    final enteredPassword = _passwordController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      // Backend JWT login (ADR-001). Base URL via --dart-define=API_BASE_URL
      // (Android emulator: http://10.0.2.2:8000).
      final response = await ApiClient.post(
        '/auth/login',
        {'email': input, 'password': enteredPassword},
        auth: false,
      );

      if (response.statusCode == 200) {
        // TokenPair: {access_token, refresh_token, organizations[]}
        final tokenData = json.decode(response.body) as Map<String, dynamic>;
        final token = tokenData['access_token']?.toString() ?? '';
        final refreshToken = tokenData['refresh_token']?.toString() ?? '';
        final orgs = (tokenData['organizations'] as List?) ?? [];

        // The tokens go into the platform's secure storage; the
        // organization and the admin flag are not secrets, so they stay
        // in the preferences.
        await SessionStore.writeToken(token);
        await SessionStore.writeRefreshToken(refreshToken);

        int? orgId;
        bool isAdmin = false;
        if (orgs.isNotEmpty) {
          final first = orgs.first as Map<String, dynamic>;
          orgId = (first['organization_id'] as num?)?.toInt();
          isAdmin = (first['is_admin'] as bool?) ?? false;
        }
        // Always written, never left over from a previous session: a
        // stale organization_id or is_admin sent the next user to the
        // wrong organization, or into the management portal.
        if (orgId != null) {
          await SessionStore.writeOrganizationId(orgId);
        } else {
          await SessionStore.deleteOrganizationId();
        }
        await SessionStore.writeIsAdmin(isAdmin);
        ApiClient.resetSessionExpiryNotification();

        // Resolve profile via GET /users/me (TokenPair carries no name/email).
        // The same response carries the roles and capabilities the server
        // grants, so the interface can show the right portal without
        // guessing from a boolean.
        String userName = 'User';
        String userEmail = input.contains('@') ? input : '';
        String empId = '';
        List<String> roles = <String>[];
        List<String> permissions = <String>[];
        bool superuser = false;
        try {
          final me = await ApiClient.get('/users/me');
          if (me.statusCode == 200) {
            final profile = json.decode(me.body) as Map<String, dynamic>;
            userName = profile['name']?.toString() ?? userName;
            userEmail = profile['email']?.toString() ?? userEmail;
            empId = profile['employee_id']?.toString() ?? empId;
            roles = stringList(profile['roles']);
            permissions = stringList(profile['permissions']);
            superuser = profile['is_superuser'] == true;
          }
        } catch (_) {}

        ExpenseStore.instance.currentUserName = userName;
        ExpenseStore.instance.currentUserEmail = userEmail;
        ExpenseStore.instance.currentUserId = empId;
        ExpenseStore.instance.currentOrganizationId = orgId;
        ExpenseStore.instance.setUserAccess(
          roles: roles,
          permissions: permissions,
          superuser: superuser,
        );

        ExpenseStore.instance.currentEmployeeName = userName;
        ExpenseStore.instance.currentEmployeeEmail = userEmail;
        ExpenseStore.instance.currentEmployeeId = empId;
        ExpenseStore.instance.currentManagerName = userName;
        ExpenseStore.instance.currentManagerEmail = userEmail;

        // Prime the signed-in user's working set through the store —
        // expenses, projects, request queues, directory, expense types
        // and notifications. The screen used to inline-fetch just the
        // project list and hand it to setProjects, which bypassed the
        // store's fetch helpers — so expensesLoaded and projectsLoaded
        // stayed false at fresh sign-in and the My Requests / Projects
        // screens spun forever (and "my expenses" read as empty until
        // the next session resume).
        await ExpenseStore.instance.primeSessionData();

        if (!mounted) return;

        // One portal, tab set built from the capabilities this profile
        // carried. The grantedPermissions fallback lands in the same
        // shell (its tabs just stay empty until the server answers).
        Navigator.pushReplacementNamed(context, '/portal_shell');

      } else if (response.statusCode == 401 || response.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid ID or Password. Access denied by backend API.';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Server error. Please try again later.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Network error: Cannot reach the backend server (check API_BASE_URL).';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                color: _cardBackground,
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: _goldColor.withValues(alpha: 0.35), width: 1.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- CUSTOM 'A' LOGO ICON ---
                        const Center(child: ATSLogo(size: 60, showText: false)),
                        const SizedBox(height: 16),
                        const Text(
                          'ATS OneWork',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _goldColor,
                            letterSpacing: 1.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in using your authorized User ID or Email',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade900.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade400),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _idController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: const TextStyle(color: _goldColor),
                            hintText: 'your.name@company.com',
                            hintStyle: TextStyle(color: Colors.grey.shade600),
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              color: _goldColor,
                            ),
                            filled: true,
                            fillColor: _darkBackground,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade800),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: _goldColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.trim().contains('@')) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: _goldColor),
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: _goldColor,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: _goldColor,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: _darkBackground,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade800),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: _goldColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _goldColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'Log In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}