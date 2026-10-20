// The single portal shell — the app has one navigation scaffold whose
// tabs are built from what the server says the signed-in user may do.
//
// There is no "management portal" and "employee portal" any more; the
// person who can approve expenses gets the review queue, the person
// who can move reimbursements gets the payout screens, and a plain
// employee gets exactly the tabs they need. The one thing the role
// name still decides is which dashboard the first tab renders — a
// convenience, not an authority.
import 'package:flutter/material.dart';

import 'package:ats_onework/employee/add_expense_screen.dart';
import 'package:ats_onework/employee/employee_dashboard.dart';
import 'package:ats_onework/employee/employee_profile_screen.dart';
import 'package:ats_onework/employee/employee_projects.dart';
import 'package:ats_onework/employee/employee_wait_screen.dart';
import 'package:ats_onework/employee/my_requests_screen.dart';
import 'package:ats_onework/management/access_management_screen.dart';
import 'package:ats_onework/management/budget_allocation_screen.dart';
import 'package:ats_onework/management/director_dashboard.dart';
import 'package:ats_onework/management/employee_management_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/finance_dashboard.dart';
import 'package:ats_onework/management/finance_hub_screens.dart';
import 'package:ats_onework/management/management_projects_screen.dart';
import 'package:ats_onework/management/manager_dashboard.dart';
import 'package:ats_onework/management/manager_profile.dart';
import 'package:ats_onework/management/manager_requests_screen.dart';
import 'package:ats_onework/shared/ats_logo.dart';

/// The tabs the shell can show. The visible set is capability-gated per
/// user, so navigation happens by tab identity, never by index — a
/// capability grant that appears or disappears cannot strand a screen
/// against a stale number.
enum PortalTab {
  dashboard,
  requests,
  myRequests,
  upload,
  projects,
  toPay,
  paid,
  access,
  profile,
}

/// A user whose management duties are the payout lifecycle: they hold
/// `reimbursement.transition` but neither access administration nor any
/// project/budget building capability — the finance shape, whether or
/// not their role is named "finance". Without the negations the
/// organization admin (who holds the transition capability *and* everything
/// else) would be read as finance and lose the manager dashboard.
bool payoutPurePersona(ExpenseStore store) =>
    store.canPayReimbursements &&
    !store.canManageAccess &&
    !store.can('project.create') &&
    !store.can('project.manage') &&
    !store.can('budget.manage');

class PortalShell extends StatefulWidget {
  const PortalShell({super.key});

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  PortalTab _selectedTab = PortalTab.dashboard;

  /// The employee dashboard was written against the old shell's fixed
  /// tab order: 1 = Upload, 2 = My Requests. Translated by tab identity
  /// now, so a custom tab set cannot land a person on the wrong page.
  PortalTab _employeeNavTarget(int legacyIndex) {
    switch (legacyIndex) {
      case 1:
        return PortalTab.upload;
      case 2:
        return PortalTab.myRequests;
      default:
        return PortalTab.dashboard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final bool managementUser = store.hasManagementAccess || store.isSuperUser;

        // --- The plain-employee gatekeeper (unchanged behavior) -------
        // Wait screen only while the project fetch has not completed;
        // the project-access request flow takes over after an empty
        // result — an unassigned employee is never stranded here.
        if (!managementUser) {
          if (!store.projectsLoaded && store.myProjects.isEmpty) {
            return Scaffold(
              backgroundColor: store.bg,
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (store.myProjects.isEmpty) {
            return const EmployeeWaitScreen();
          }
        }

        final canBuildProjects = store.can('project.create') ||
            store.can('project.manage') ||
            store.can('project.member.manage');

        // --- Dashboard persona ----------------------------------------
        Widget dashboard;
        if (!managementUser) {
          dashboard = EmployeeDashboardScreen(
            onNavigate: (legacyIndex) => setState(
              () => _selectedTab = _employeeNavTarget(legacyIndex),
            ),
          );
        } else if (payoutPurePersona(store)) {
          dashboard = const FinanceDashboard();
        } else if (store.reviewerOnlyPersona) {
          dashboard = const DirectorDashboard();
        } else {
          dashboard = const ManagerDashboardScreen();
        }

        // --- The tab list: dashboard first, profile last ---------------
        final entries = <PortalTab, Widget>{};
        final items = <BottomNavigationBarItem>[];

        void addTab(PortalTab tab, Widget screen, BottomNavigationBarItem item) {
          entries[tab] = screen;
          items.add(item);
        }

        addTab(
          PortalTab.dashboard,
          dashboard,
          const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded, size: 22), label: 'Home'),
        );
        if (store.canApproveExpenses) {
          addTab(
            PortalTab.requests,
            const ManagerRequestsScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.list_alt_rounded, size: 22), label: 'Review'),
          );
        }
        // Every submitter gets their own requests — previously the
        // management portal had no such tab and a manager could not see
        // their own submissions anywhere.
        if (store.can('expense.read_own')) {
          addTab(
            PortalTab.myRequests,
            const MyRequestsScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.assignment_rounded, size: 22), label: 'Mine'),
          );
        }
        if (store.can('expense.create')) {
          addTab(
            PortalTab.upload,
            const AddExpenseScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.upload_file_rounded, size: 22), label: 'Add'),
          );
        }
        if (store.can('project.read')) {
          addTab(
            PortalTab.projects,
            canBuildProjects
                ? const ManagementProjectsScreen()
                : const EmployeeProjectsScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.business_center_rounded, size: 22),
                label: 'Projects'),
          );
        }
        if (payoutPurePersona(store)) {
          addTab(
            PortalTab.toPay,
            const FinanceToPayScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_rounded, size: 22),
                label: 'To Pay'),
          );
        }
        if (store.can('reimbursement.read_all') || store.can('reimbursement.read_own')) {
          addTab(
            PortalTab.paid,
            const PaidReimbursementsScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.payments_rounded, size: 22), label: 'Paid'),
          );
        }
        if (store.canManageAccess) {
          addTab(
            PortalTab.access,
            const AccessManagementScreen(),
            const BottomNavigationBarItem(
                icon: Icon(Icons.admin_panel_settings_rounded, size: 22),
                label: 'Access'),
          );
        }
        addTab(
          PortalTab.profile,
          managementUser
              ? const ManagerProfileScreen()
              : const EmployeeProfileScreen(),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded, size: 22), label: 'Profile'),
        );

        // A capability can disappear mid-session (role changed on the
        // server, org switched); never sit on a tab that is gone.
        if (!entries.containsKey(_selectedTab)) {
          _selectedTab = PortalTab.dashboard;
        }
        final int selected = entries.keys.toList().indexOf(_selectedTab);

        // --- Drawer: cross-cutting tools by capability -----------------
        // Was visible to the HR role name only; budget administration
        // belongs to whoever holds budget.manage (an HR account without
        // the capability used to open a screen the API refuses).
        final drawerChildren = <Widget>[
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D11),
              border: Border(bottom: BorderSide(color: Color(0xFFD4AF37), width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const ATSLogo(size: 48, showText: true),
                const SizedBox(height: 12),
                Text(
                  'Access Level: ${store.currentUserRole.toUpperCase()}',
                  style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_rounded, color: Color(0xFF9CA3AF)),
            title: const Text('Home', style: TextStyle(color: Color(0xFFF3F4F6))),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedTab = PortalTab.dashboard);
            },
          ),
        ];
        if (store.can('budget.manage') || store.canManagePeople) {
          drawerChildren.add(const SizedBox(height: 8));
          drawerChildren.add(const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              'ADMIN TOOLS',
              style: TextStyle(
                  color: Color(0xCCD4AF37),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5),
            ),
          ));
        }
        if (store.can('budget.manage')) {
          drawerChildren.add(ListTile(
            leading:
                const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFD4AF37)),
            title: const Text('Budget Allocation',
                style: TextStyle(color: Color(0xFFF3F4F6), fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const BudgetAllocationScreen()),
              );
            },
          ));
        }
        if (store.canManagePeople) {
          drawerChildren.add(ListTile(
            leading: const Icon(Icons.manage_accounts_rounded, color: Color(0xFFD4AF37)),
            title: const Text('Employee Management',
                style: TextStyle(color: Color(0xFFF3F4F6), fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const EmployeeManagementScreen()),
              );
            },
          ));
        }

        return Scaffold(
          backgroundColor: store.bg,
          body: IndexedStack(
            index: selected,
            children: entries.keys.map((t) => entries[t]!).toList(),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: store.card,
              border: Border(top: BorderSide(color: store.border, width: 1)),
              boxShadow: [
                if (!store.isDarkMode)
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4))
              ],
            ),
            child: BottomNavigationBar(
              backgroundColor: store.card,
              selectedItemColor: store.accentGold,
              unselectedItemColor: store.textMuted,
              currentIndex: selected,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              onTap: (index) =>
                  setState(() => _selectedTab = entries.keys.toList()[index]),
              items: items,
            ),
          ),
          drawer: Drawer(
            backgroundColor: store.card,
            child: ListView(
              padding: EdgeInsets.zero,
              children: drawerChildren,
            ),
          ),
        );
      },
    );
  }
}
