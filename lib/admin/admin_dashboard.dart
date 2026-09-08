import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ats_onework/employee/employee_login.dart';

import 'package:ats_onework/management/budget_allocation_screen.dart';
import 'package:ats_onework/management/pending_approvals_screen.dart';
import 'package:ats_onework/management/manager_requests_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/expense_details.dart';

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

  Future<void> _updateUserRole(BuildContext context, String email, String newRole) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(email).set({
        'role': newRole,
      }, SetOptions(merge: true));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully updated $email to $newRole', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating role: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
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
            Icon(Icons.admin_panel_settings, color: champagneGold),
            SizedBox(width: 10),
            Text('Admin Portal', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: champagneGold),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
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
                    const Text('User Role Management', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      height: 280, // Constrained height to allow scrolling without hiding the feed
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: champagneGold));
                          }
                          
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text('No users found in the database.', style: TextStyle(color: textMuted)),
                            );
                          }

                          final users = snapshot.data!.docs;

                          return ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final userData = users[index].data() as Map<String, dynamic>;
                              final userEmail = users[index].id;
                              final currentRole = userData['role'] ?? 'employee';

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
                                    userEmail,
                                    style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Current Role: ${currentRole.toString().toUpperCase()}',
                                    style: const TextStyle(color: textMuted, fontSize: 12),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: darkCharcoal,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: champagneGold.withValues(alpha: 0.3)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        dropdownColor: darkCharcoal,
                                        value: ['employee', 'manager', 'hr', 'finance', 'admin', 'director'].contains(currentRole) ? currentRole : 'employee',
                                        icon: const Icon(Icons.arrow_drop_down, color: champagneGold),
                                        style: const TextStyle(color: textFrost, fontWeight: FontWeight.w600),
                                        onChanged: (String? newValue) {
                                          if (newValue != null && newValue != currentRole) {
                                            _updateUserRole(context, userEmail, newValue);
                                          }
                                        },
                                        items: const [
                                          DropdownMenuItem(value: 'employee', child: Text('Employee')),
                                          DropdownMenuItem(value: 'manager', child: Text('Manager')),
                                          DropdownMenuItem(value: 'hr', child: Text('HR')),
                                          DropdownMenuItem(value: 'finance', child: Text('Finance')),
                                          DropdownMenuItem(value: 'director', child: Text('Director')),
                                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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
                    
                    filteredFeedExpenses.isEmpty
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
                                      child: Text(expense.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
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
          );
        },
      ),
    );
  }
}