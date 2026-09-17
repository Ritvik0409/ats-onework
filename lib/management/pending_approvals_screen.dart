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
  void _showAssignProjectDialog(BuildContext context, Map<String, dynamic> requestData, ExpenseStore store) {
    final projects = store.projects;
    String? selectedProjectName;
    final employeeName = requestData['name'] ?? 'Unknown';
    final employeeEmail = requestData['email'] ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Assign Project to $employeeName', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
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
                          isExpanded: true,
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
                          items: projects.map((p) {
                            final bool isDeactivated = !p.isActive; 
                            
                            return DropdownMenuItem<String>(
                              value: p.name,
                              enabled: !isDeactivated,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(color: isDeactivated ? store.textMuted : store.textFrost),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isDeactivated)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Deactivated', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
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
                            builder: (_) => BudgetSetupScreen(initialEmployeeEmail: employeeEmail),
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
                  
                  if (dialogContext.mounted) Navigator.pop(dialogContext); 
                  
                  try {
                    await store.approveProjectAccess(employeeEmail, targetProject.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$employeeName assigned successfully!'), backgroundColor: store.accentGold));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error assigning project: $e'), backgroundColor: Colors.redAccent));
                    }
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

  void _handleDeny(BuildContext context, Map<String, dynamic> requestData, ExpenseStore store) {
    final employeeName = requestData['name'] ?? 'Unknown';
    final employeeEmail = requestData['email'] ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: store.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
        title: Text('Deny Access for $employeeName?', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text('This will dismiss the request.', style: TextStyle(color: store.textMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await FirebaseFirestore.instance.collection('project_requests').doc(employeeEmail).delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Project access request denied.'), backgroundColor: Colors.redAccent),
                  );
                }
              } catch (_) {}
            },
            child: const Text('Yes, Deny', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
            title: Text('Project Access Requests', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
            bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(color: store.accentGold.withValues(alpha: 0.15), height: 1)),
          ),
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24.0),
              // NOW STREAMING EXCLUSIVELY FROM 'project_requests'
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('project_requests').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: store.accentGold));
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading requests', style: TextStyle(color: Colors.redAccent)));
                  }

                  final requests = snapshot.data?.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return {
                      'email': data['email']?.toString() ?? '',
                      'name': data['name']?.toString() ?? 'Unknown',
                    };
                  }).toList() ?? [];

                  if (requests.isEmpty) {
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
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final req = requests[index];
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
                            child: Text(store.getInitials(req['name'] ?? 'U'), style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(req['name'] ?? 'Unknown', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                          subtitle: Text('${req['email']} • Waiting for access', style: TextStyle(color: store.textMuted, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: store.accentGold,
                                  foregroundColor: store.isDarkMode ? Colors.black : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _showAssignProjectDialog(context, req, store),
                                child: const Text('Assign Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade900.withValues(alpha: 0.25),
                                  foregroundColor: Colors.redAccent,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _handleDeny(context, req, store),
                                child: const Text('Deny', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ],
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