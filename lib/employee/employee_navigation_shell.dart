import 'package:flutter/material.dart';

import 'package:ats_onework/employee/employee_dashboard.dart';
import 'package:ats_onework/employee/add_expense_screen.dart';
import 'package:ats_onework/employee/my_requests_screen.dart';
import 'package:ats_onework/employee/employee_profile_screen.dart';
import 'package:ats_onework/employee/employee_projects.dart'; 
import 'package:ats_onework/employee/employee_wait_screen.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeNavigationShell extends StatefulWidget {
  const EmployeeNavigationShell({super.key});

  @override
  State<EmployeeNavigationShell> createState() => _EmployeeNavigationShellState();
}

class _EmployeeNavigationShellState extends State<EmployeeNavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        
        // --- THE GATEKEEPER ---
        // Wait screen ONLY when the project fetch has actually completed
        // and came back empty — a slow/failed fetch used to strand
        // assigned employees on this screen with no way out.
        if (!store.projectsLoaded && store.myProjects.isEmpty) {
          return Scaffold(
            backgroundColor: store.bg,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (store.myProjects.isEmpty) {
          return const EmployeeWaitScreen();
        }

        // Otherwise, load the normal portal
        final List<Widget> screens = [
          EmployeeDashboardScreen(onNavigate: (i) => setState(() => _currentIndex = i)),
          const AddExpenseScreen(),
          const MyRequestsScreen(),
          const EmployeeProjectsScreen(),
          const EmployeeProfileScreen(),
        ];

        return Scaffold(
          backgroundColor: store.bg,
          body: IndexedStack(index: _currentIndex, children: screens),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: store.card,
              border: Border(top: BorderSide(color: store.border, width: 1)),
              boxShadow: [
                if (!store.isDarkMode)
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              backgroundColor: store.card,
              selectedItemColor: store.accentGold,
              unselectedItemColor: store.textMuted,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded, size: 22), label: 'Dashboard'),
                BottomNavigationBarItem(icon: Icon(Icons.upload_file_rounded, size: 22), label: 'Upload'),
                BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded, size: 22), label: 'My Requests'),
                BottomNavigationBarItem(icon: Icon(Icons.business_center_rounded, size: 22), label: 'Projects'),
                BottomNavigationBarItem(icon: Icon(Icons.person_rounded, size: 22), label: 'Profile'),
              ],
            ),
          ),
        );
      },
    );
  }
}