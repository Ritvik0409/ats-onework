import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final store = ExpenseStore.instance;
  String _searchQuery = '';

  Future<void> _confirmToggle(String email, String name, bool currentlyActive) async {
    final action = currentlyActive ? 'Deactivate' : 'Reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: store.accentGold.withValues(alpha: 0.2)),
            ),
            title: Text('$action $name?', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Text(
              currentlyActive
                  ? '$name will no longer be able to log in or submit expenses through the employee portal.'
                  : '$name will regain access to the employee portal.',
              style: TextStyle(color: store.textMuted, fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action, style: TextStyle(color: currentlyActive ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );

    if (confirmed == true) {
      await store.setEmployeeActive(email, !currentlyActive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name ${currentlyActive ? 'deactivated' : 'reactivated'}'),
            backgroundColor: currentlyActive ? Colors.redAccent : Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ];

        final employees = store.allEmployees.where((e) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return e['name']!.toLowerCase().contains(q) || e['email']!.toLowerCase().contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: obsidianBlack,
            elevation: 0,
            iconTheme: IconThemeData(color: textFrost),
            title: Text('Manage Employees', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: TextStyle(color: textFrost, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by employee name or email...',
                    hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.7)),
                    prefixIcon: Icon(Icons.search_rounded, color: champagneGold),
                    filled: true,
                    fillColor: darkCharcoal,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
              Expanded(
                child: employees.isEmpty
                    ? Center(child: Text('No employees found.', style: TextStyle(color: textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: employees.length,
                        itemBuilder: (context, index) {
                          final e = employees[index];
                          final email = e['email']!;
                          final name = e['name']!;
                          final isActive = store.isEmployeeActive(email);
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: darkCharcoal,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                              boxShadow: cardShadows,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: champagneGold.withValues(alpha: 0.1),
                                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text(email, style: TextStyle(color: textMuted, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isActive ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isActive ? 'ACTIVE' : 'DEACTIVATED',
                                          style: TextStyle(
                                              color: isActive ? Colors.greenAccent : Colors.redAccent,
                                              fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeThumbColor: champagneGold,
                                  onChanged: (_) => _confirmToggle(email, name, isActive),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}