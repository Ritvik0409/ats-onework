import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class UniversalLoginScreen extends StatefulWidget {
  const UniversalLoginScreen({super.key});

  @override
  State<UniversalLoginScreen> createState() => _UniversalLoginScreenState();
}

// Alias to maintain compatibility across existing imports
typedef EmployeeLoginScreen = UniversalLoginScreen;

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

  String _getRouteForRole(String role) {
    switch (role.toLowerCase()) {
      case 'employee':
        return '/employee_shell'; 
      case 'hr':
      case 'hr manager':
      case 'finance':
      case 'finance officer':
      case 'admin':
      case 'administrator':
      case 'manager':
      case 'director':
        return '/management_shell'; 
      default:
        return '/employee_shell';
    }
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
      final firestore = FirebaseFirestore.instance;
      Map<String, dynamic>? userData;

      try {
        final doc = await firestore.collection('users').doc(input).get();
        if (doc.exists && doc.data() != null) {
          userData = doc.data();
        }
      } catch (_) {}

      if (userData == null) {
        try {
          final query = await firestore
              .collection('users')
              .where('employeeId', isEqualTo: input)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            userData = query.docs.first.data();
          }
        } catch (_) {}
      }

      if (userData == null) {
        try {
          final query = await firestore
              .collection('users')
              .where('email', isEqualTo: input)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            userData = query.docs.first.data();
          }
        } catch (_) {}
      }

      if (userData == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid ID or Email. Access restricted to authorized database users only.';
          _isLoading = false;
        });
        return;
      }

      final dbPassword = userData['password']?.toString();
      final userRole = userData['role']?.toString() ?? 'employee';
      final empId = userData['employeeId']?.toString() ?? input;
      final userName = userData['name']?.toString() ?? 'User';
      final userEmail = userData['email']?.toString() ?? '';

      if (dbPassword == enteredPassword) {
        ExpenseStore.instance.currentUserRole = userRole.toLowerCase();
        ExpenseStore.instance.currentUserName = userName;
        ExpenseStore.instance.currentUserEmail = userEmail;
        ExpenseStore.instance.currentUserId = empId;
        
        ExpenseStore.instance.currentEmployeeName = userName;
        ExpenseStore.instance.currentEmployeeEmail = userEmail;
        ExpenseStore.instance.currentEmployeeId = empId;
        ExpenseStore.instance.currentManagerName = userName;
        ExpenseStore.instance.currentManagerEmail = userEmail;

        try {
          final snapshot = await FirebaseFirestore.instance.collection('projects').get();
          ExpenseStore.instance.projects = snapshot.docs.map((doc) => ProjectRecord.fromFirestore(doc)).toList();
        } catch (_) {}

        if (!mounted) return;

        if (userRole.toLowerCase() == 'employee') {
          final isAssigned = ExpenseStore.instance.isEmployeeAssignedToAnyProject(empId) || 
                             ExpenseStore.instance.isEmployeeAssignedToAnyProject(userEmail);
          
          if (isAssigned) {
            Navigator.pushReplacementNamed(context, '/employee_shell');
            return;
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logged in as $userRole ($empId)',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: _goldColor,
          ),
        );

        final targetRoute = _getRouteForRole(userRole);
        Navigator.pushReplacementNamed(context, targetRoute);
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid password entered. Please check your credentials.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Database permission denied or network error. Please verify Firebase Security Rules.';
        _isLoading = false;
      });
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
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: _goldColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(color: _goldColor, width: 1.5),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'A',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: _goldColor,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
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
                            labelText: 'User ID or Email',
                            labelStyle: const TextStyle(color: _goldColor),
                            hintText: 'e.g. EMP101 or emp101@company.com',
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
                              return 'Please enter your User ID or Email';
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