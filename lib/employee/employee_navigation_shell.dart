import 'package:flutter/material.dart';
import 'package:ats_onework/employee/employee_dashboard.dart';
import 'package:ats_onework/employee/add_expense_screen.dart';
import 'package:ats_onework/employee/my_requests_screen.dart';
import 'package:ats_onework/employee/employee_notifications_screen.dart';
import 'package:ats_onework/employee/employee_profile_screen.dart';

class EmployeeNavigationShell extends StatefulWidget {
  const EmployeeNavigationShell({super.key});

  @override
  State<EmployeeNavigationShell> createState() => _EmployeeNavigationShellState();
}

class _EmployeeNavigationShellState extends State<EmployeeNavigationShell> {
  int _currentIndex = 0;

  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      EmployeeDashboardScreen(onNavigate: (i) => setState(() => _currentIndex = i)),
      const AddExpenseScreen(),
      const MyRequestsScreen(),
      const EmployeeNotificationsScreen(),
      const EmployeeProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D11),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: darkCharcoal,
          border: Border(top: BorderSide(color: Color(0xFF262633), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: darkCharcoal,
          selectedItemColor: champagneGold,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded, size: 22), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.upload_file_rounded, size: 22), label: 'Upload'),
            BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded, size: 22), label: 'My Requests'),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_rounded, size: 22), label: 'Notifications'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded, size: 22), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}