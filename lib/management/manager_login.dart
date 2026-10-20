import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ats_onework/management/navigation_shell.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/json_utils.dart';

/// Management-portal login — FastAPI JWT (ADR-001), same flow as
/// employee_login but gated on an admin membership: a non-admin login
/// is refused and the persisted token is discarded.
class ManagerLoginScreen extends StatefulWidget {
  const ManagerLoginScreen({super.key});

  @override
  State<ManagerLoginScreen> createState() => _ManagerLoginScreenState();
}

class _ManagerLoginScreenState extends State<ManagerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_manager_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // POST /api/v1/auth/login — base URL via --dart-define=API_BASE_URL
      // (Android emulator: http://10.0.2.2:8000).
      final response = await ApiClient.post(
        '/auth/login',
        {'email': email, 'password': password},
        auth: false,
      );

      if (!mounted) return;

      if (response.statusCode == 401 || response.statusCode == 404) {
        _showError('Incorrect email or password.');
        return;
      }
      if (response.statusCode == 403) {
        _showError('Your account has been deactivated. Please contact administration.');
        return;
      }
      if (response.statusCode != 200) {
        _showError('Server error (${response.statusCode}). Please try again.');
        return;
      }

      // TokenPair: {access_token, refresh_token, organizations[]}.
      final tokenData = json.decode(response.body) as Map<String, dynamic>;
      final token = tokenData['access_token']?.toString() ?? '';
      final refreshToken = tokenData['refresh_token']?.toString() ?? '';
      final orgs = (tokenData['organizations'] as List?) ?? [];

      final prefs = await SharedPreferences.getInstance();
      int? orgId;
      bool isAdmin = false;
      if (orgs.isNotEmpty) {
        final first = orgs.first as Map<String, dynamic>;
        orgId = (first['organization_id'] as num?)?.toInt();
        isAdmin = (first['is_admin'] as bool?) ?? false;
      }
      if (token.isEmpty) {
        // Never persist a token that cannot use the management portal.
        // The stale organization_id and is_admin flags are cleared too,
        // or the next person to use the device is routed into the
        // management portal on the strength of the previous session.
        await prefs.remove('auth_token');
        await prefs.remove('refresh_token');
        await prefs.remove('organization_id');
        await prefs.remove('is_admin');
        _showError('This portal is restricted to management accounts.');
        return;
      }

      await prefs.setString('auth_token', token);
      await prefs.setString('refresh_token', refreshToken);
      if (orgId != null) {
        await prefs.setInt('organization_id', orgId);
      } else {
        await prefs.remove('organization_id');
      }
      await prefs.setBool('is_admin', isAdmin);
      ApiClient.resetSessionExpiryNotification();

      if (_rememberMe) {
        await prefs.setString('saved_manager_email', email);
      } else {
        await prefs.remove('saved_manager_email');
      }

      // Resolve profile via GET /users/me (TokenPair carries no name/email).
      // The same response carries the roles and capabilities the server
      // grants — the management portal is open to whoever holds a
      // management capability, not to whoever owns the organization.
      String userName = 'Manager';
      List<String> roles = <String>[];
      List<String> permissions = <String>[];
      bool superuser = false;
      try {
        final me = await ApiClient.get('/users/me');
        if (me.statusCode == 200) {
          final profile = json.decode(me.body) as Map<String, dynamic>;
          userName = profile['name']?.toString() ?? userName;
          roles = stringList(profile['roles']);
          permissions = stringList(profile['permissions']);
          superuser = profile['is_superuser'] == true;
        }
      } catch (_) {}

      ExpenseStore.instance.currentOrganizationId = orgId;
      ExpenseStore.instance.setUserAccess(
        roles: roles,
        permissions: permissions,
        superuser: superuser,
      );
      if (!ExpenseStore.instance.hasManagementAccess) {
        await ApiClient.signOut();
        _showError('This portal is restricted to management accounts.');
        return;
      }

      ExpenseStore.instance.currentUserName = userName;
      ExpenseStore.instance.setCurrentManager(email: email);
      ExpenseStore.instance.setManagerName(userName);
      await ExpenseStore.instance.loadCurrentUserRole(email);

      // Prime the manager's working set: projects (like employee login),
      // plus the queues the dashboards render first.
      await _primeManagerData(orgId);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ManagementNavigationShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Network error. Verify the backend is running (API_BASE_URL).');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _primeManagerData(int? orgId) async {
    final store = ExpenseStore.instance;
    try {
      if (orgId != null) {
        final projectsResponse = await ApiClient.get(
          '/organizations/$orgId/projects',
          query: {'limit': '100'},
        );
        if (projectsResponse.statusCode == 200) {
          store.setProjects(ApiClient.pageItems(projectsResponse)
              .map((data) => ProjectRecord.fromJson(data as Map<String, dynamic>))
              .toList());
        }
      }
      await store.fetchUsersFromBackend();
      await store.fetchExpensesFromBackend();
      await store.fetchProjectRequestsFromBackend();
    } catch (e) {
      debugPrint('Manager data priming failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _handleForgotPassword() {
    // No reset endpoint in the backend (§49) — account resets are admin
    // actions (PATCH /users/{id}). Point users at their administrator.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password resets are handled by your administrator.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: obsidianBlack,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: darkCharcoal,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: champagneGold.withValues(alpha: 0.15), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 15)),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: obsidianBlack,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.5),
                        ),
                      ),
                      const Positioned(
                        top: 14,
                        child: Icon(Icons.keyboard_arrow_up_rounded, size: 48, color: Color(0xFFE2B93B)),
                      ),
                      const Positioned(
                        bottom: 18,
                        child: Icon(Icons.star_rounded, size: 12, color: Color(0xFFE2B93B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ATS OneWork',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textFrost, letterSpacing: 0.5),
                  ),
                  const Text(
                    'Management Portal',
                    style: TextStyle(fontSize: 14, color: champagneGold, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Email / Manager ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textMuted)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    style: const TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Enter Email or Manager ID',
                      hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 14),
                      filled: true,
                      fillColor: obsidianBlack,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: champagneGold, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter your email';
                      final email = value.trim().toLowerCase();
                      final looksLikeEmail = RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$').hasMatch(email);
                      if (!looksLikeEmail) return 'Please enter a valid email address';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textMuted)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Enter Password',
                      hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 14),
                      filled: true,
                      fillColor: obsidianBlack,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: champagneGold, width: 1.5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: textMuted, size: 20),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) => (value == null || value.isEmpty) ? 'Please enter your password' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Theme(
                            data: ThemeData(unselectedWidgetColor: textMuted),
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: champagneGold,
                              checkColor: obsidianBlack,
                              onChanged: (value) => setState(() => _rememberMe = value!),
                            ),
                          ),
                          const Text('Remember me', style: TextStyle(color: textMuted, fontSize: 13)),
                        ],
                      ),
                      TextButton(
                        onPressed: _handleForgotPassword,
                        child: const Text('Forgot Password?', style: TextStyle(color: champagneGold, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: obsidianBlack,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        disabledBackgroundColor: champagneGold.withValues(alpha: 0.5),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: obsidianBlack, strokeWidth: 2.5)
                            )
                          : const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Secure access for management only',
                    style: TextStyle(fontSize: 11, color: textMuted.withValues(alpha: 0.6), letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
