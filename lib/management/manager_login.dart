import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // NEW: Required to check activation status
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ats_onework/management/navigation_shell.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/google_auth_service.dart';
import 'package:ats_onework/shared/google_sign_in_button.dart';


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
    final savedEmail = prefs.getString('saved_manager_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

 Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      try {
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Security Checkpoint
        final statusDoc = await FirebaseFirestore.instance.collection('employee_status').doc(email).get();
        if (statusDoc.exists && statusDoc.data()?['isActive'] == false) {
          await FirebaseAuth.instance.signOut(); 
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Your account has been deactivated. Please contact administration.'), backgroundColor: Colors.redAccent),
            );
            // Force the spinner off right here just to be absolutely safe
            setState(() => _isLoading = false);
          }
          return; 
        }

        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('saved_manager_email', email);
        } else {
          await prefs.remove('saved_manager_email');
        }

        ExpenseStore.instance.setCurrentManager(email: email);
        await ExpenseStore.instance.loadCurrentUserRole(email);

        if (mounted) {
          Navigator.pushReplacement(
            context,
           MaterialPageRoute(builder: (context) => const ManagementNavigationShell()),
          );
        }
      } catch (e) {
        // FIX: Broadened the catch block to intercept EVERY type of error, preventing silent crashes
        String errorMessage = 'An error occurred. Please try again.';
        if (e is FirebaseAuthException) {
          if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
            errorMessage = 'Incorrect email or password.';
          } else if (e.code == 'user-disabled') {
            errorMessage = 'Your account has been disabled by an administrator.';
          } else {
            errorMessage = e.message ?? errorMessage;
          }
        } else {
          errorMessage = e.toString(); // Catches database permission errors
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final email = await GoogleAuthService.signIn();

      // FIX: Apply the same security checkpoint to Google Logins
      final statusDoc = await FirebaseFirestore.instance.collection('employee_status').doc(email).get();
      if (statusDoc.exists && statusDoc.data()?['isActive'] == false) {
        await FirebaseAuth.instance.signOut(); 
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your account has been deactivated. Please contact administration.'), backgroundColor: Colors.redAccent),
          );
        }
        return; 
      }

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('saved_manager_email', email);
      }

      ExpenseStore.instance.setCurrentManager(email: email);
      await ExpenseStore.instance.loadCurrentUserRole(email);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ManagementNavigationShell()),
        );
      }
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

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please type your email address first.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset link sent! Check your inbox.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error sending link. Verify your email is correct.'), backgroundColor: Colors.redAccent),
        );
      }
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
                  const OrDivider(),
                  GoogleSignInButton(isLoading: _isGoogleLoading, onPressed: _handleGoogleSignIn),
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

// Ensure you have your OrDivider component defined either here or imported
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.2))),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('OR', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.2))),
        ],
      ),
    );
  }
}