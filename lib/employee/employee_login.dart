import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ats_onework/employee/employee_navigation_shell.dart';
import 'package:ats_onework/management/navigation_shell.dart';  
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/google_auth_service.dart';
import 'package:ats_onework/shared/google_sign_in_button.dart';

class UniversalLoginScreen extends StatefulWidget {
  const UniversalLoginScreen({super.key});

  @override
  State<UniversalLoginScreen> createState() => _UniversalLoginScreenState();
}

class _UniversalLoginScreenState extends State<UniversalLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

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
    final savedEmail = prefs.getString('saved_corporate_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _routeUserBasedOnRole(String email) async {
    try {
      final statusDoc = await FirebaseFirestore.instance.collection('employee_status').doc(email).get();
      if (statusDoc.exists) {
        final bool isActive = statusDoc.data()?['isActive'] ?? true;
        if (isActive == false) {
          await FirebaseAuth.instance.signOut();
          await GoogleAuthService.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Access Denied: Your account has been deactivated by HR.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }

      String role = 'employee';
      String? savedName; 
      
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(email).get();
      if (userDoc.exists) {
        if (userDoc.data()!.containsKey('role')) {
          role = userDoc.data()!['role'].toString().toLowerCase();
        }
        if (userDoc.data()!.containsKey('name')) {
          savedName = userDoc.data()!['name'].toString();
        }
      } else {
        await FirebaseFirestore.instance.collection('users').doc(email).set({
          'email': email,
          'role': 'employee',
          'name': email.split('@')[0],
          'createdAt': FieldValue.serverTimestamp(),
        });
        role = 'employee';
        savedName = email.split('@')[0];
      }

      ExpenseStore.instance.currentUserRole = role;

      if (mounted) {
        if (role == 'manager' || role == 'hr' || role == 'director' || role == 'finance' || role == 'admin') {
          ExpenseStore.instance.setCurrentManager(email: email);
          if (savedName != null && savedName.isNotEmpty) {
            ExpenseStore.instance.setManagerName(savedName);
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ManagementNavigationShell()),
          );
        } else {
          ExpenseStore.instance.setCurrentEmployee(email: email);
          if (savedName != null && savedName.isNotEmpty) {
            ExpenseStore.instance.setEmployeeName(savedName);
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const EmployeeNavigationShell()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Routing error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      final email = await GoogleAuthService.signIn();
      await _routeUserBasedOnRole(email);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // Helper method to keep routing logic clean
  Future<void> _completeLoginFlow(String email) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_corporate_email', email);
    } else {
      await prefs.remove('saved_corporate_email');
    }
    await _routeUserBasedOnRole(email);
  }

  // Helper method for error display
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      try {
        // 1. Attempt standard login first
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _completeLoginFlow(email);

      } on FirebaseAuthException catch (e) {
        // 2. Auto-register if the account doesn't exist
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          
          if (email.toLowerCase().endsWith('@ats.com')) {
            try {
              // Create the Firebase Auth account on the fly
              await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: email,
                password: password,
              );
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Corporate account auto-created!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.green),
                );
              }
              await _completeLoginFlow(email);
              
            } on FirebaseAuthException catch (signUpError) {
              if (signUpError.code == 'email-already-in-use') {
                _showError('Incorrect password.');
              } else {
                _showError('Auto-registration failed: ${signUpError.message}');
              }
            }
          } else {
            _showError('Incorrect email or password.');
          }
        } else {
          _showError('An error occurred: ${e.message}');
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please type your email address first.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.redAccent));
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset link sent! Check your inbox.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error sending link. Verify your email is correct.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: Colors.redAccent));
    }
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
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: obsidianBlack,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.5),
                        ),
                      ),
                      const Positioned(top: 14, child: Icon(Icons.keyboard_arrow_up_rounded, size: 48, color: Color(0xFFE2B93B))),
                      const Positioned(bottom: 18, child: Icon(Icons.star_rounded, size: 12, color: Color(0xFFE2B93B))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('ATS OneWork', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textFrost, letterSpacing: 0.5)),
                  
                  const Text('Secure Corporate Login', style: TextStyle(fontSize: 14, color: champagneGold, fontWeight: FontWeight.w500, letterSpacing: 0.5)),

                  const SizedBox(height: 32),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Corporate Email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textMuted)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    style: const TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Enter your email',
                      hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 14),
                      filled: true,
                      fillColor: obsidianBlack,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: champagneGold, width: 1.5)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter your corporate email';
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
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: champagneGold, width: 1.5)),
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
                            child: Checkbox(value: _rememberMe, activeColor: champagneGold, checkColor: obsidianBlack, onChanged: (value) => setState(() => _rememberMe = value!)),
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
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: obsidianBlack, strokeWidth: 2.5))
                          : const Text('Secure Login'),
                    ),
                  ),
                  const OrDivider(),
                  GoogleSignInButton(isLoading: _isGoogleLoading, onPressed: _handleGoogleLogin),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.2), thickness: 1)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('OR', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.2), thickness: 1)),
        ],
      ),
    );
  }
}