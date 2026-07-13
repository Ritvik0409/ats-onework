import 'package:flutter/material.dart';
import 'package:ats_onework/management/navigation_shell.dart';
import 'package:ats_onework/management/expense_store.dart';

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

  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      ExpenseStore.instance.setCurrentManager(email: _emailController.text.trim());
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const ManagementNavigationShell(),
        ),
      );
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
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                )
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
                          color: const Color(0xFF0D0D11),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2B93B).withValues(alpha: 0.3), width: 1.5),
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
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your corporate email';
                      }
                      final email = value.trim().toLowerCase();
                      final looksLikeEmail = RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$').hasMatch(email);
                      if (!looksLikeEmail) {
                        return 'Please enter a valid email address';
                      }
                      if (!email.endsWith('@company.com')) {
                        return 'Only @company.com corporate emails are allowed';
                      }
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
                        onPressed: () {},
                        child: const Text('Forgot Password?', style: TextStyle(color: champagneGold, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: obsidianBlack,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('Login'),
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