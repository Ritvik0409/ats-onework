import 'package:flutter/material.dart';
import 'package:ats_onework/employee/employee_login.dart';

import 'package:ats_onework/management/budget_allocation_screen.dart';
import 'package:ats_onework/management/pending_approvals_screen.dart';
import 'package:ats_onework/management/manager_requests_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/expense_details.dart';
import 'package:ats_onework/shared/ats_logo.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/app_snack.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  // NEW: State variables for the integrated feed
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final ExpenseStore _store = ExpenseStore.instance;

  /// Admin action — actives/deactivates an account (PATCH /users/{id}
  /// account_status, the real backend counterpart of the old Firestore
  /// role write). Deactivated accounts are refused at login (403).
  Future<void> _updateAccountStatus(BuildContext context, Map<String, String> user, bool active) async {
    final ok = await _store.updateUserAccountStatus(user['id'] ?? '', active);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${user['name']} is now ${active ? 'active' : 'inactive'}'
              : 'Could not update account status.',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: ok ? Colors.green : Colors.redAccent,
      ),
    );
  }

  void _showAssignEmployeeDialog(BuildContext context) {
    final store = ExpenseStore.instance; 
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'employee';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: store.card,
          title: Text('Assign Credentials', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idController,
                  style: TextStyle(color: store.textFrost),
                  decoration: InputDecoration(
                    labelText: 'Employee ID (e.g., EMP101)',
                    labelStyle: TextStyle(color: store.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: store.textFrost),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(color: store.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  style: TextStyle(color: store.textFrost),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: store.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: TextStyle(color: store.textFrost),
                  decoration: InputDecoration(
                    labelText: 'Assign Password',
                    labelStyle: TextStyle(color: store.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                  ),
                ),
                const SizedBox(height: 16),
                
                // --- UNIVERSAL ROLE DROPDOWN ---
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: store.card,
                  decoration: InputDecoration(
                    labelText: 'Assign System Role',
                    labelStyle: TextStyle(color: store.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                  ),
                  style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold),
                  icon: Icon(Icons.arrow_drop_down, color: store.accentGold),
                  items: const [
                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'hr', child: Text('HR')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'finance', child: Text('Finance')),
                    DropdownMenuItem(value: 'director', child: Text('Director')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        selectedRole = newValue;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: store.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: store.accentGold),
              onPressed: () async {
                if (idController.text.trim().isEmpty || passwordController.text.trim().isEmpty || emailController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields')),
                  );
                  return;
                }
                try {
                  // POST /auth/register — the role dropdown is informational
                  // only (no role endpoint in §49).
                  final ok = await store.assignEmployeeCredentials(
                    employeeId: idController.text.trim(),
                    email: emailController.text.trim(),
                    password: passwordController.text.trim(),
                    name: nameController.text.trim(),
                    role: selectedRole, 
                  );
                  if (!context.mounted) return;
                  if (ok) {
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    AppSnack.success(context, 'Account created! (Role is informational — no role endpoint yet)');
                  } else {
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    AppSnack.error(context, 'Could not create the account (the email may already be registered).');
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppSnack.error(context, 'Error: $e');
                  }
                }
              },
              child: Text('Save to Records', style: TextStyle(color: store.bg, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: darkCharcoal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: champagneGold.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: champagneGold, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: obsidianBlack,
      appBar: AppBar(
        backgroundColor: darkCharcoal,
        elevation: 0,
  title: const Row(
  children: [
    ATSLogo(size: 32, showText: false),
    SizedBox(width: 12),
    Text('Admin Portal', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
  ],
),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded, color: champagneGold),
            tooltip: 'Assign Credentials',
            onPressed: () => _showAssignEmployeeDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: champagneGold),
            tooltip: 'Logout',
            onPressed: () async {
              // Revokes the refresh token and clears the local JWT store.
              await ApiClient.signOut();

              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const UniversalLoginScreen()),
                  (Route<dynamic> route) => false,
                );
              }
            },
          )
        ],
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          
          final List<BoxShadow> cardShadows = _store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

          // STRICT IDENTITY LOCK: Hides the Admin's own uploads
          final filteredFeedExpenses = _store.expenses.where((expense) {
            final uploaderEmail = expense.email.trim().toLowerCase();
            final myEmployeeEmail = _store.currentEmployeeEmail.trim().toLowerCase();
            final myManagerEmail = _store.currentManagerEmail.trim().toLowerCase();
            
            if (uploaderEmail == myEmployeeEmail || uploaderEmail == myManagerEmail) {
              return false;
            }

            final matchesSearch = expense.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                expense.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                expense.type.toLowerCase().contains(_searchQuery.toLowerCase());

            if (_selectedFilter == 'All') return matchesSearch;
            if (_selectedFilter == 'Pending') return matchesSearch && expense.status == 'Pending Verification';
            if (_selectedFilter == 'Approved') return matchesSearch && expense.status == 'Approved';
            if (_selectedFilter == 'Paid') return matchesSearch && expense.status == 'Paid';
            if (_selectedFilter == 'Rejected') return matchesSearch && expense.status == 'Rejected';
            return matchesSearch;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                _store.fetchUsersFromBackend(),
                _store.fetchExpensesFromBackend(),
                _store.fetchProjectRequestsFromBackend(),
              ]);
            },
            child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Dashboard',
                      style: TextStyle(color: textFrost, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage employee roles and access organization tools.',
                      style: TextStyle(color: textMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // --- MANAGEMENT TOOLS SECTION ---
                    const Text('Management Tools', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _toolCard(context, 'Assign Credentials', Icons.person_add_rounded, 
                            () => _showAssignEmployeeDialog(context)),
                          const SizedBox(width: 12),
                          _toolCard(context, 'Full Request Logs', Icons.receipt_long_rounded, 
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagerRequestsScreen()))),
                          const SizedBox(width: 12),
                          _toolCard(context, 'Pending Approvals', Icons.person_add_rounded, 
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingApprovalsScreen()))),
                          const SizedBox(width: 12),
                          _toolCard(context, 'Budget Allocation', Icons.account_balance_wallet_rounded, 
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetAllocationScreen()))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // --- USER ROLE MANAGEMENT ---
                    // Backed by GET /users (admin-gated); account_status
                    // opens/closes the door at login.
                    const Text('User Role Management', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      height: 280, // Constrained height to allow scrolling without hiding the feed
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                      ),
                      child: !_store.usersLoaded
                          ? const Center(child: CircularProgressIndicator())
                          : _store.usersList.isEmpty
                          ? const Center(child: Text('No users found in the database.', style: TextStyle(color: textMuted)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _store.usersList.length,
                              itemBuilder: (context, index) {
                                final user = _store.usersList[index];
                                final userName = user['name'] ?? 'Unknown';
                                final userEmail = user['email'] ?? '';
                                final isActive = (user['account_status'] ?? 'active') == 'active';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: obsidianBlack,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: champagneGold.withValues(alpha: 0.05)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                    leading: CircleAvatar(
                                      backgroundColor: champagneGold.withValues(alpha: 0.2),
                                      child: const Icon(Icons.person, color: champagneGold),
                                    ),
                                    title: Text(
                                      '$userName  •  $userEmail',
                                      style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'Account Status: ${isActive ? 'active'.toUpperCase() : (user['account_status'] ?? '').toUpperCase()}',
                                      style: TextStyle(
                                        color: isActive ? textMuted : Colors.redAccent.shade200,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: darkCharcoal,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: champagneGold.withValues(alpha: 0.3)),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<bool>(
                                          dropdownColor: darkCharcoal,
                                          value: isActive,
                                          icon: const Icon(Icons.arrow_drop_down, color: champagneGold),
                                          style: const TextStyle(color: textFrost, fontWeight: FontWeight.w600),
                                          onChanged: (bool? newValue) {
                                            if (newValue != null && newValue != isActive) {
                                              _updateAccountStatus(context, user, newValue);
                                            }
                                          },
                                          items: const [
                                            DropdownMenuItem(value: true, child: Text('Active')),
                                            DropdownMenuItem(value: false, child: Text('Inactive')),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 40),
                    Divider(color: champagneGold.withValues(alpha: 0.2), thickness: 1),
                    const SizedBox(height: 32),

                    // --- INTEGRATED REQUEST FEED ---
                    const Text('Live Approval Feed', style: TextStyle(color: textFrost, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => setState(() => _searchQuery = value),
                      style: const TextStyle(color: textFrost),
                      decoration: InputDecoration(
                        hintText: 'Search by employee name, ID or type...',
                        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
                        prefixIcon: const Icon(Icons.search_rounded, color: champagneGold, size: 22),
                        filled: true,
                        fillColor: darkCharcoal,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: champagneGold, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Pending', 'Approved', 'Paid', 'Rejected'].map((category) {
                          final isSelected = _selectedFilter == category;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) setState(() => _selectedFilter = category);
                              },
                              labelStyle: TextStyle(
                                color: isSelected ? (_store.isDarkMode ? obsidianBlack : Colors.white) : textFrost,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              selectedColor: champagneGold,
                              backgroundColor: darkCharcoal,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: isSelected ? champagneGold : champagneGold.withValues(alpha: 0.15)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    !_store.expensesLoaded
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ))
                      : filteredFeedExpenses.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                          ),
                          child: const Center(child: Text('No matching expense logs found.', style: TextStyle(color: textMuted))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredFeedExpenses.length,
                          itemBuilder: (context, index) {
                            final expense = filteredFeedExpenses[index];

                            Color statusColor = champagneGold;
                            if (expense.status == 'Approved') statusColor = Colors.orangeAccent;
                            if (expense.status == 'Paid') statusColor = Colors.greenAccent.shade400;
                            if (expense.status == 'Rejected') statusColor = Colors.redAccent.shade400;

                            final isHighValue = expense.amount > 30000;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: darkCharcoal,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isHighValue ? Colors.redAccent.shade700.withValues(alpha: 0.6) : champagneGold.withValues(alpha: 0.1), 
                                  width: isHighValue ? 1.5 : 1
                                ),
                                boxShadow: isHighValue 
                                  ? [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.05), blurRadius: 10, spreadRadius: 1), ...cardShadows]
                                  : cardShadows,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: isHighValue ? Colors.redAccent.withValues(alpha: 0.1) : champagneGold.withValues(alpha: 0.1),
                                  child: Text(
                                    expense.name.substring(0, 1),
                                    style: TextStyle(
                                      color: isHighValue ? Colors.redAccent : champagneGold, 
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 18
                                    ),
                                  ),
                                ),
                                title: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(expense.name, style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Text('(${expense.id})', style: const TextStyle(color: textMuted)),
                                    
                                    if (expense.projectName != null && expense.projectName!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: champagneGold.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: champagneGold.withValues(alpha: 0.5)),
                                        ),
                                        child: Text(
                                          expense.projectName!,
                                          style: const TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ]
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text('${expense.type} Expense • ${expense.date}', style: const TextStyle(color: textMuted, fontSize: 13)),
                                ),
                                trailing: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isHighValue) 
                                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                                        if (isHighValue) 
                                          const SizedBox(width: 4),
                                        Text(
                                          expense.amountFormatted, 
                                          style: TextStyle(
                                            color: isHighValue ? Colors.redAccent.shade100 : textFrost, 
                                            fontWeight: FontWeight.w900, 
                                            fontSize: 15
                                          )
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
                                      ),
                                      child: Text(expense.status == 'Approved' ? 'Approved • Payment Pending' : expense.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
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
                  ],
                ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}