import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/ats_logo.dart';

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
      // NOTE: 10.0.2.2 is the address Android Emulators use to connect to your computer's localhost.
      // If you are using iOS simulator or Web, change this to 127.0.0.1
      final url = Uri.parse('http://10.0.2.2:8000/auth/login');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': input, 
          'password': enteredPassword,
        }),
      );

      if (response.statusCode == 200) {
        // Successfully authenticated with the Python backend
        final userData = json.decode(response.body);

        final userRole = userData['role']?.toString() ?? 'employee';
        final empId = userData['employeeId']?.toString() ?? input;
        final userName = userData['name']?.toString() ?? 'User';
        final userEmail = userData['email']?.toString() ?? '';
        final token = userData['access_token']?.toString() ?? '';

        // Store the Auth Token securely using SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);

        ExpenseStore.instance.currentUserRole = userRole.toLowerCase();
        ExpenseStore.instance.currentUserName = userName;
        ExpenseStore.instance.currentUserEmail = userEmail;
        ExpenseStore.instance.currentUserId = empId;
        
        ExpenseStore.instance.currentEmployeeName = userName;
        ExpenseStore.instance.currentEmployeeEmail = userEmail;
        ExpenseStore.instance.currentEmployeeId = empId;
        ExpenseStore.instance.currentManagerName = userName;
        ExpenseStore.instance.currentManagerEmail = userEmail;

        // Fetch Projects from Python FastAPI Backend
        try {
          final projectsUrl = Uri.parse('http://10.0.2.2:8000/projects');
          final projectsResponse = await http.get(
            projectsUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token', 
            },
          );

          if (projectsResponse.statusCode == 200) {
            final List<dynamic> projectsJson = json.decode(projectsResponse.body);
            ExpenseStore.instance.projects = projectsJson
                .map((data) => ProjectRecord.fromJson(data))
                .toList();
          } else {
            print('Failed to load projects: ${projectsResponse.statusCode}');
          }
        } catch (e) {
          print('Network error fetching projects: $e');
        }

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
        _errorMessage = 'Network error: Cannot connect to the local Python server.';
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