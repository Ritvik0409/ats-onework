import 'package:flutter/material.dart';
import 'package:ats_onework/employee/employee_login.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/api_client.dart';

class EmployeeWaitScreen extends StatelessWidget {
  const EmployeeWaitScreen({super.key});

  /// Requests are per-project (migration 0002): pick a project first,
  /// then POST /projects/{id}/access-requests.
  Future<void> _pickAndRequestProject(BuildContext context, ExpenseStore store) async {
    // Keep the project list fresh before choosing.
    await store.fetchProjectsFromBackend();
    final activeProjects = store.projects.where((p) => p.isActive).toList();
    if (!context.mounted) return;

    String? selectedProjectId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: store.card,
          title: Text('Request Project Access', style: TextStyle(color: store.accentGold)),
          content: activeProjects.isEmpty
              ? Text(
                  'No projects are currently synced. Ask your manager to create one.',
                  style: TextStyle(color: store.textMuted),
                )
              : DropdownButtonFormField<String>(
                  value: selectedProjectId,
                  dropdownColor: store.card,
                  style: TextStyle(color: store.textFrost),
                  decoration: InputDecoration(
                    labelText: 'Select Project',
                    labelStyle: TextStyle(color: store.textMuted),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                  ),
                  items: activeProjects
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedProjectId = val),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel', style: TextStyle(color: store.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: store.accentGold, foregroundColor: Colors.black),
              onPressed: selectedProjectId == null ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('Send Request'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedProjectId == null || !context.mounted) return;
    await store.submitProjectAccessRequest(selectedProjectId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Access request sent successfully!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: store.accentGold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return Scaffold(
      backgroundColor: store.bg,
      appBar: AppBar(
        backgroundColor: store.card,
        elevation: 0,
        title: Text('Account Setup', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: store.border, height: 1),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              color: store.card,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: store.accentGold.withValues(alpha: 0.3), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: store.accentGold.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: store.accentGold, width: 1.5),
                      ),
                      child: Icon(Icons.hourglass_top_rounded, color: store.accentGold, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Awaiting Assignment',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: store.textFrost),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your account is successfully verified, but you have not been assigned to a project yet.',
                      style: TextStyle(color: store.textMuted, fontSize: 13, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // --- Green note successfully removed from here ---
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: store.accentGold.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await _pickAndRequestProject(context, store);
                        },
                        icon: Icon(Icons.mail_outline_rounded, color: store.accentGold, size: 18),
                        label: Text('Request Project Access', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          // Revokes the refresh token and clears the
                          // local JWT store (api_client.dart).
                          await ApiClient.signOut();
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const UniversalLoginScreen()),
                            (Route<dynamic> route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                        label: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}