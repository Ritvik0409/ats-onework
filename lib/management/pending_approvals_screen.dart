import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/budget_setup_screen.dart';
import 'package:ats_onework/shared/app_snack.dart';

/// Manager queue for project-access requests (FastAPI /access-requests,
/// migration 0002). Each pending request already carries the project the
/// employee selected, so "approve" confirms that project — no picker —
/// while deny just rejects it.
class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh once when the screen opens. Doing it from the build method
    // restarted the request on every rebuild, and the fetch notifies
    // listeners — so the screen refetched itself in a loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ExpenseStore.instance.fetchProjectRequestsFromBackend();
    });
  }

  void _showApproveDialog(BuildContext context, Map<String, dynamic> requestData, ExpenseStore store) {
    final employeeName = requestData['name']?.toString() ?? 'Unknown';
    final employeeEmail = requestData['email']?.toString() ?? '';
    final projectName = requestData['projectName']?.toString() ?? '';
    final requestId = requestData['access_request_id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: store.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
        title: Text('Grant Project Access', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold, fontSize: 18)),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$employeeName ($employeeEmail) wants to join:', style: TextStyle(color: store.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              Text(projectName.isEmpty ? 'Unknown project' : projectName, style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
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
                  label: Text('Create New Project Instead', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: store.accentGold, foregroundColor: store.isDarkMode ? store.bg : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: requestId.isEmpty ? null : () async {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              final ok = await store.decideProjectAccess(requestId, true);
              if (!context.mounted) return;
              if (ok) {
                AppSnack.success(context, '$employeeName assigned successfully!');
              } else {
                AppSnack.error(context, 'Could not approve the request.');
              }
            },
            child: const Text('Confirm & Grant Access', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleDeny(BuildContext context, Map<String, dynamic> requestData, ExpenseStore store) {
    final employeeName = requestData['name']?.toString() ?? 'Unknown';
    final requestId = requestData['access_request_id']?.toString() ?? '';

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
            onPressed: requestId.isEmpty ? null : () async {
              Navigator.pop(dialogContext);
              final ok = await store.decideProjectAccess(requestId, false);
              if (!context.mounted) return;
              if (ok) {
                AppSnack.error(context, 'Project access request denied.');
              } else {
                AppSnack.error(context, 'Could not deny the request.');
              }
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
              // Data path: GET /api/v1/access-requests?status=pending
              // (store.projectRequests, migration 0002 flow).
              //
              // The list is read straight from the store. It used to be
              // wrapped in a FutureBuilder, which started a new request
              // on every rebuild — and the fetch notifies listeners, so
              // the screen refetched itself forever.
              child: Builder(
                builder: (context) {
                  final requests = store.projectRequests;

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
                            child: Text(store.getInitials(req['name']?.toString() ?? 'U'), style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(req['name']?.toString() ?? 'Unknown', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '${req['email'] ?? ''} • Wants to join: ${req['projectName'] ?? ''}',
                            style: TextStyle(color: store.textMuted, fontSize: 12),
                          ),
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
                                onPressed: () => _showApproveDialog(context, req, store),
                                child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
