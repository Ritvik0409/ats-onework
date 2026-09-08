import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/manager_dashboard.dart';
import 'package:ats_onework/management/director_dashboard.dart';
import 'package:ats_onework/management/finance_dashboard.dart';
import 'package:ats_onework/management/manager_requests_screen.dart';
import 'package:ats_onework/management/manager_profile.dart';
import 'package:ats_onework/management/budget_allocation_screen.dart';
import 'package:ats_onework/management/employee_management_screen.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/download_web.dart'; 
import 'package:ats_onework/management/management_projects_screen.dart';
import 'package:ats_onework/employee/add_expense_screen.dart';

class ManagementNavigationShell extends StatefulWidget {
  const ManagementNavigationShell({super.key});

  @override
  State<ManagementNavigationShell> createState() => _ManagementNavigationShellState();
}

class _ManagementNavigationShellState extends State<ManagementNavigationShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final String currentRole = store.currentUserRole;
        final bool isHR = (currentRole == 'hr' || currentRole == 'admin' || currentRole == 'director');
        final bool isDirector = (currentRole == 'director');
        final bool isFinance = (currentRole == 'finance'); 

        final List<Widget> screens = [
          if (isDirector) const DirectorDashboard()
          else if (isFinance) const FinanceDashboard()
          else const ManagerDashboardScreen(),

          if (isFinance) const FinanceToPayScreen() 
          else const ManagerRequestsScreen(),

          if (!isFinance) const AddExpenseScreen(),

          if (!isFinance) const ManagementProjectsScreen(),

          if (isDirector || isFinance) const PaidReimbursementsScreen(),
          
          const ManagerProfileScreen(),
        ];

        final List<BottomNavigationBarItem> navItems = [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          
          if (isFinance)
            const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'To Pay')
          else
            const BottomNavigationBarItem(icon: Icon(Icons.list_alt_rounded), label: 'Requests'),
          
          if (!isFinance)
            const BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline_rounded), label: 'Upload'),
          
          if (!isFinance)
            const BottomNavigationBarItem(icon: Icon(Icons.business_center_rounded), label: 'Projects'),
            
          if (isDirector || isFinance) 
            const BottomNavigationBarItem(icon: Icon(Icons.payments_rounded), label: 'Paid'),
            
          const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ];

        if (_selectedIndex >= screens.length) {
          _selectedIndex = 0;
        }

        return Scaffold(
          backgroundColor: obsidianBlack,
          body: screens[_selectedIndex],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: darkCharcoal,
              border: Border(top: BorderSide(color: store.border, width: 1)),
              boxShadow: [
                if (!store.isDarkMode)
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))
              ],
            ),
            child: BottomNavigationBar(
              backgroundColor: darkCharcoal,
              selectedItemColor: champagneGold,
              unselectedItemColor: textMuted,
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              onTap: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              items: navItems,
            ),
          ),
          drawer: Drawer(
            backgroundColor: darkCharcoal,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: obsidianBlack,
                    border: Border(bottom: BorderSide(color: champagneGold, width: 2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('ATS OneWork', style: TextStyle(color: textFrost, fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Access Level: ${currentRole.toUpperCase()}', style: TextStyle(color: champagneGold, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ],
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.home_rounded, color: textMuted),
                  title: Text('Home', style: TextStyle(color: textFrost)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedIndex = 0);
                  },
                ),
                Visibility(
                  visible: isHR,
                  child: const Divider(color: Colors.white24, thickness: 1, height: 32),
                ),
                Visibility(
                  visible: isHR,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Text('MANAGEMENT & HR TOOLS', style: TextStyle(color: champagneGold.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ),
                ),
                Visibility(
                  visible: isHR,
                  child: ListTile(
                    leading: Icon(Icons.account_balance_wallet_rounded, color: champagneGold),
                    title: Text('Budget Allocation', style: TextStyle(color: textFrost, fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const BudgetAllocationScreen()));
                    },
                  ),
                ),
                Visibility(
                  visible: isHR,
                  child: ListTile(
                    leading: Icon(Icons.manage_accounts_rounded, color: champagneGold),
                    title: Text('Employee Management', style: TextStyle(color: textFrost, fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const EmployeeManagementScreen()));
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FinanceToPayScreen extends StatefulWidget {
  const FinanceToPayScreen({super.key});

  @override
  State<FinanceToPayScreen> createState() => _FinanceToPayScreenState();
}

class _FinanceToPayScreenState extends State<FinanceToPayScreen> {
  String _searchQuery = '';
  final ExpenseStore _store = ExpenseStore.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;

        final approvedExpenses = _store.expenses.where((expense) {
          if (expense.status != 'Approved') return false;
          return expense.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              expense.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              expense.type.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: Text('Pending Payouts', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) => setState(() => _searchQuery = value),
                          style: TextStyle(color: textFrost),
                          // CHANGE THIS:
// decoration: const InputDecoration(

// TO THIS (remove const):
decoration: InputDecoration(
  hintText: 'Search approved requests by name, ID or type...',
  hintStyle: TextStyle(color: textMuted, fontSize: 14),
  prefixIcon: Icon(Icons.search_rounded, color: champagneGold, size: 22),
  filled: true,
  fillColor: darkCharcoal,
  contentPadding: const EdgeInsets.symmetric(vertical: 16),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: champagneGold, width: 1.5),
  ),
),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 52, 
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.download_rounded, size: 16),
                          label: Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: champagneGold,
                            side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const FinanceReportsScreen()));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: approvedExpenses.isEmpty
                        ? Center(child: Text('Inbox Zero! No pending payouts.', style: TextStyle(color: textMuted)))
                        : ListView.builder(
                            itemCount: approvedExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = approvedExpenses[index];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.fromBorderSide(BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 1)),
                                  boxShadow: [
                                    if (!_store.isDarkMode)
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.orangeAccent.withValues(alpha: 0.1),
                                    child: Text(
                                      expense.name.isNotEmpty ? expense.name.substring(0, 1) : 'E',
                                      style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                  ),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Text('(${expense.id})', style: TextStyle(color: textMuted)),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Text('${expense.type} Expense • ${expense.date}', style: TextStyle(color: textMuted, fontSize: 13)),
                                  ),
                                  trailing: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(expense.amountFormatted, style: TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orangeAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.fromBorderSide(BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.3), width: 1)),
                                        ),
                                        child: Text('Approved', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => ExpenseDetailsScreen(expenseId: expense.id)),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PaidReimbursementsScreen extends StatefulWidget {
  const PaidReimbursementsScreen({super.key});
  @override
  State<PaidReimbursementsScreen> createState() => _PaidReimbursementsScreenState();
}

class _PaidReimbursementsScreenState extends State<PaidReimbursementsScreen> {
  String _searchQuery = '';
  final ExpenseStore _store = ExpenseStore.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;

        final paidExpenses = _store.expenses.where((expense) {
          if (expense.status != 'Paid') return false;
          return expense.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              expense.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              expense.type.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        final double totalPaidAmount = paidExpenses.fold(0.0, (sum, item) => sum + item.amount);

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            title: Text('Paid Reimbursements', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 20)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.fromBorderSide(BorderSide(color: Colors.greenAccent.withValues(alpha: 0.2), width: 1)),
                      boxShadow: [
                        if (!_store.isDarkMode)
                          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Settled & Disbursed', style: TextStyle(color: textMuted, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text('₹${totalPaidAmount.toStringAsFixed(2)}', style: TextStyle(color: textFrost, fontSize: 26, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.fromBorderSide(BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3), width: 1)),
                          ),
                          child: Text(
                            '${paidExpenses.length} Paid Records',
                            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) => setState(() => _searchQuery = value),
                          style: TextStyle(color: textFrost),
                          decoration: InputDecoration(
                            hintText: 'Search paid records by employee, ID or type...',
                            hintStyle: TextStyle(color: textMuted, fontSize: 14),
                            prefixIcon: Icon(Icons.search_rounded, color: champagneGold, size: 22),
                            filled: true,
                            fillColor: darkCharcoal,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: champagneGold, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 52, 
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.download_rounded, size: 16),
                          label: Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: champagneGold,
                            side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const PaidReportsScreen()));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: paidExpenses.isEmpty
                        ? Center(child: Text('No paid reimbursement records found.', style: TextStyle(color: textMuted)))
                        : ListView.builder(
                            itemCount: paidExpenses.length,
                            itemBuilder: (context, index) {
                              final expense = paidExpenses[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.fromBorderSide(BorderSide(color: Colors.greenAccent.withValues(alpha: 0.2), width: 1)),
                                  boxShadow: [
                                    if (!_store.isDarkMode)
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.1),
                                    child: Text(
                                      expense.name.isNotEmpty ? expense.name.substring(0, 1) : 'E',
                                      style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                  ),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Text('(${expense.id})', style: TextStyle(color: textMuted)),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Text('${expense.type} Expense • Settled: ${expense.date}', style: TextStyle(color: textMuted, fontSize: 13)),
                                  ),
                                  trailing: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(expense.amountFormatted, style: TextStyle(color: textFrost, fontWeight: FontWeight.w900, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.fromBorderSide(BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3), width: 1)),
                                        ),
                                        child: Text('Paid', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => ExpenseDetailsScreen(expenseId: expense.id)));
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PaidReportsScreen extends StatefulWidget {
  const PaidReportsScreen({super.key});
  @override
  State<PaidReportsScreen> createState() => _PaidReportsScreenState();
}

class _PaidReportsScreenState extends State<PaidReportsScreen> {
  String _searchQuery = '';
  String _selectedTimeframe = 'All Time';

  bool _matchesTimeframe(String dateStr) {
    if (_selectedTimeframe == 'All Time') return true;
    try {
      DateTime? d;
      if (dateStr.contains(RegExp(r'[a-zA-Z]'))) {
        final parts = dateStr.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          int day = int.parse(parts[0]);
          String mStr = parts[1].toLowerCase().substring(0, 3);
          int y = int.parse(parts[2]);
          const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
          int m = months.indexOf(mStr) + 1;
          if (m > 0) d = DateTime(y, m, day);
        }
      }
      if (d != null) {
        final now = DateTime.now();
        if (_selectedTimeframe == 'This Month') {
          return d.year == now.year && d.month == now.month;
        } else if (_selectedTimeframe == 'Last 3 Months') {
          final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
          return d.isAfter(threeMonthsAgo) || d.isAtSameMomentAs(threeMonthsAgo);
        }
      }
    } catch (_) {}
    return false; 
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final paidExpenses = store.expenses.where((e) {
          if (e.status != 'Paid') return false;
          if (!_matchesTimeframe(e.date)) return false;

          final q = _searchQuery.toLowerCase();
          return e.name.toLowerCase().contains(q) || 
                 e.id.toLowerCase().contains(q) || 
                 e.type.toLowerCase().contains(q);
        }).toList();

        final totalAmount = paidExpenses.fold(0.0, (sum, item) => sum + item.amount);

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text('Paid Reimbursements Report', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
            iconTheme: IconThemeData(color: textFrost),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'Search by employee name, ID or type...',
                      hintStyle: TextStyle(color: textMuted, fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: champagneGold, size: 22),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: champagneGold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: obsidianBlack,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.fromBorderSide(BorderSide(color: champagneGold.withValues(alpha: 0.3), width: 1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            dropdownColor: darkCharcoal,
                            value: _selectedTimeframe,
                            icon: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(Icons.arrow_drop_down, color: champagneGold),
                            ),
                            items: <String>['All Time', 'This Month', 'Last 3 Months'].map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_month_rounded, color: champagneGold, size: 16),
                                    const SizedBox(width: 8),
                                    Text(value, style: TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) setState(() => _selectedTimeframe = newValue);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.fromBorderSide(BorderSide(color: store.border, width: 1)),
                      boxShadow: [
                        if (!store.isDarkMode)
                          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total reimbursed', style: TextStyle(color: textMuted, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('₹${totalAmount.toStringAsFixed(2)}', style: TextStyle(color: textFrost, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Records', style: TextStyle(color: textMuted, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${paidExpenses.length}', style: TextStyle(color: champagneGold, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: paidExpenses.isEmpty 
                      ? Center(child: Text('No matching paid records found.', style: TextStyle(color: textMuted)))
                      : ListView.builder(
                          itemCount: paidExpenses.length,
                          itemBuilder: (context, index) {
                            final expense = paidExpenses[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: darkCharcoal,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.fromBorderSide(BorderSide(color: store.border, width: 1)),
                                boxShadow: [
                                  if (!store.isDarkMode)
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text('${expense.type} • ${expense.date}', style: TextStyle(color: textMuted, fontSize: 12)),
                                    ],
                                  ),
                                  Text(expense.amountFormatted, style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            );
                          }
                      ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: store.isDarkMode ? obsidianBlack : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        if (paidExpenses.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No records to download.'), backgroundColor: Colors.redAccent),
                          );
                          return;
                        }

                        String csvContent = "Employee Name,Expense ID,Type,Amount,Date Settled,Status\n";
                        for (var exp in paidExpenses) {
                          final cleanName = exp.name.replaceAll(',', ''); 
                          csvContent += "$cleanName,${exp.id},${exp.type},${exp.amount},${exp.date},Paid\n";
                        }
                        final bytes = utf8.encode(csvContent);

                        try {
                          final timestamp = DateTime.now().millisecondsSinceEpoch;
                          downloadFile(bytes, 'Paid_Reimbursements_$timestamp.csv');
                          
                         ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text('Download started!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    backgroundColor: champagneGold,
    behavior: SnackBarBehavior.floating,
  ),
);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error downloading file: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                      icon: Icon(Icons.download_rounded, size: 20),
                      label: Text('Download CSV Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}

class FinanceReportsScreen extends StatefulWidget {
  const FinanceReportsScreen({super.key});
  @override
  State<FinanceReportsScreen> createState() => _FinanceReportsScreenState();
}

class _FinanceReportsScreenState extends State<FinanceReportsScreen> {
  String _searchQuery = '';
  String _selectedTimeframe = 'All Time';

  bool _matchesTimeframe(String dateStr) {
    if (_selectedTimeframe == 'All Time') return true;
    try {
      DateTime? d;
      if (dateStr.contains(RegExp(r'[a-zA-Z]'))) {
        final parts = dateStr.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          int day = int.parse(parts[0]);
          String mStr = parts[1].toLowerCase().substring(0, 3);
          int y = int.parse(parts[2]);
          const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
          int m = months.indexOf(mStr) + 1;
          if (m > 0) d = DateTime(y, m, day);
        }
      }
      if (d != null) {
        final now = DateTime.now();
        if (_selectedTimeframe == 'This Month') {
          return d.year == now.year && d.month == now.month;
        } else if (_selectedTimeframe == 'Last 3 Months') {
          final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
          return d.isAfter(threeMonthsAgo) || d.isAtSameMomentAs(threeMonthsAgo);
        }
      }
    } catch (_) {}
    return false; 
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final pendingPayouts = store.expenses.where((e) {
          if (e.status != 'Approved') return false;
          if (!_matchesTimeframe(e.date)) return false;

          final q = _searchQuery.toLowerCase();
          return e.name.toLowerCase().contains(q) || 
                 e.id.toLowerCase().contains(q) || 
                 e.type.toLowerCase().contains(q);
        }).toList();

        final totalAmount = pendingPayouts.fold(0.0, (sum, item) => sum + item.amount);

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text('Pending Payouts Report', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
            iconTheme: IconThemeData(color: textFrost),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: textFrost),
                   // CHANGE THIS:
// decoration: const InputDecoration(

// TO THIS (remove const):
decoration: InputDecoration(
  hintText: 'Search by employee name, ID or type...',
  hintStyle: TextStyle(color: textMuted, fontSize: 14),
  prefixIcon: Icon(Icons.search_rounded, color: champagneGold, size: 22),
  filled: true,
  fillColor: darkCharcoal,
  contentPadding: const EdgeInsets.symmetric(vertical: 16),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: champagneGold, width: 1.5),
  ),
),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: obsidianBlack,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.fromBorderSide(BorderSide(color: champagneGold.withValues(alpha: 0.3), width: 1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            dropdownColor: darkCharcoal,
                            value: _selectedTimeframe,
                            icon: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(Icons.arrow_drop_down, color: champagneGold),
                            ),
                            items: <String>['All Time', 'This Month', 'Last 3 Months'].map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_month_rounded, color: champagneGold, size: 16),
                                    const SizedBox(width: 8),
                                    Text(value, style: TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              if (newValue != null) setState(() => _selectedTimeframe = newValue);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.fromBorderSide(BorderSide(color: store.border, width: 1)),
                      boxShadow: [
                        if (!store.isDarkMode)
                          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Pending Payout', style: TextStyle(color: textMuted, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('₹${totalAmount.toStringAsFixed(2)}', style: TextStyle(color: textFrost, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Records', style: TextStyle(color: textMuted, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${pendingPayouts.length}', style: TextStyle(color: Colors.orangeAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: pendingPayouts.isEmpty 
                      ? Center(child: Text('No matching pending records found.', style: TextStyle(color: textMuted)))
                      : ListView.builder(
                          itemCount: pendingPayouts.length,
                          itemBuilder: (context, index) {
                            final expense = pendingPayouts[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: darkCharcoal,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.fromBorderSide(BorderSide(color: store.border, width: 1)),
                                boxShadow: [
                                  if (!store.isDarkMode)
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(expense.name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text('${expense.type} • ${expense.date}', style: TextStyle(color: textMuted, fontSize: 12)),
                                    ],
                                  ),
                                  Text(expense.amountFormatted, style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            );
                          }
                      ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: store.isDarkMode ? obsidianBlack : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        if (pendingPayouts.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No records to download.'), backgroundColor: Colors.redAccent),
                          );
                          return;
                        }

                        String csvContent = "Employee Name,Expense ID,Type,Amount,Date Approved,Status\n";
                        for (var exp in pendingPayouts) {
                          final cleanName = exp.name.replaceAll(',', ''); 
                          csvContent += "$cleanName,${exp.id},${exp.type},${exp.amount},${exp.date},Approved\n";
                        }
                        final bytes = utf8.encode(csvContent);

                        try {
                          final timestamp = DateTime.now().millisecondsSinceEpoch;
                          downloadFile(bytes, 'Pending_Payouts_$timestamp.csv');
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Download started!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              backgroundColor: champagneGold,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error downloading file: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                      icon: Icon(Icons.download_rounded, size: 20),
                      label: Text('Download CSV Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}