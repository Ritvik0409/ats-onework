import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/budget_setup_screen.dart'; 

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  void _showAssignProjectDialog(BuildContext context, Map<String, String> employee, ExpenseStore store) {
    final projects = store.projects;
    String? selectedProjectName;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Assign Project to ${employee['name']}', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select an existing project to grant this employee access.', style: TextStyle(color: store.textMuted, fontSize: 13)),
                  const SizedBox(height: 16),
                  projects.isEmpty
                      ? const Text('No active projects available.', style: TextStyle(color: Colors.redAccent, fontSize: 13))
                      : DropdownButtonFormField<String>(
                          initialValue: selectedProjectName,
                          dropdownColor: store.card,
                          style: TextStyle(color: store.textFrost),
                          decoration: InputDecoration(
                            labelText: 'Select Project',
                            labelStyle: TextStyle(color: store.textMuted),
                            filled: true,
                            fillColor: store.isDarkMode ? store.bg : Colors.grey.shade100,
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: store.accentGold.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: store.accentGold, width: 1.5), borderRadius: BorderRadius.circular(8)),
                          ),
                          items: projects.map((p) => DropdownMenuItem(value: p.name, child: Text(p.name))).toList(),
                          onChanged: (val) => setDialogState(() => selectedProjectName = val),
                        ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: store.accentGold.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogContext); 
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BudgetSetupScreen(initialEmployeeEmail: employee['email']),
                          ),
                        );
                      },
                      icon: Icon(Icons.add_rounded, color: store.accentGold, size: 18),
                      label: Text('Create New Project for Employee', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: store.accentGold, foregroundColor: store.isDarkMode ? store.bg : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: selectedProjectName == null ? null : () async {
                  final targetProject = projects.firstWhere((p) => p.name == selectedProjectName);
                  final email = employee['email']!;

                  // --- FIX: OPTIMISTIC UI UPDATE ---
                  // Instantly inject the email into local memory so the Unassigned list automatically filters them out[cite: 8]
                  if (!targetProject.assignedEmails.contains(email)) {
                    targetProject.assignedEmails.add(email);
                  }
                  
                  if (dialogContext.mounted) Navigator.pop(dialogContext); // Close dialog instantly
                  setState(() {}); // Force the screen to redraw instantly[cite: 8]
                  
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${employee['name']} assigned successfully!'), backgroundColor: store.accentGold));

                  // Let Firebase do the heavy lifting in the background without freezing the screen[cite: 8]
                  try {
                    await store.addMembersToProject(targetProject.id, [email]);
                  } catch (e) {
                    // Safety net: If Firebase fails, revert the change so the card comes back
                    targetProject.assignedEmails.remove(email);
                    if (mounted) setState(() {});
                  }
                },
                child: const Text('Confirm & Grant Access', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: store.bg,
          appBar: AppBar(
            backgroundColor: store.card,
            elevation: 0,
            leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: store.textFrost), onPressed: () => Navigator.pop(context)),
            title: Text('Unassigned Employees', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
            bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(color: store.accentGold.withValues(alpha: 0.15), height: 1)),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'employee').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: store.accentGold));
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading employees', style: TextStyle(color: Colors.redAccent)));
                  }

                  final liveEmployees = snapshot.data?.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return {
                      'email': data['email']?.toString() ?? '',
                      'name': data['name']?.toString() ?? 'Unknown',
                    };
                  }).toList() ?? [];

                  final unassignedEmployees = liveEmployees.where((emp) {
                    final email = emp['email']!;
                    return email.isNotEmpty && !store.projects.any((p) => p.assignedEmails.contains(email));
                  }).toList();

                  if (unassignedEmployees.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.greenAccent.withValues(alpha: 0.6)),
                          const SizedBox(height: 16),
                          Text('All Caught Up!', style: TextStyle(color: store.textFrost, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('There are no new employees waiting for project assignment.', style: TextStyle(color: store.textMuted)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: unassignedEmployees.length,
                    itemBuilder: (context, index) {
                      final emp = unassignedEmployees[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: store.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: store.accentGold.withValues(alpha: 0.2)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          leading: CircleAvatar(
                            backgroundColor: store.accentGold.withValues(alpha: 0.1),
                            child: Text(store.getInitials(emp['name'] ?? 'U'), style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(emp['name'] ?? 'Unknown', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                          subtitle: Text('${emp['email']} • Waiting for access', style: TextStyle(color: store.textMuted, fontSize: 12)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: store.accentGold,
                              foregroundColor: store.isDarkMode ? Colors.black : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _showAssignProjectDialog(context, emp, store),
                            child: const Text('Assign Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}