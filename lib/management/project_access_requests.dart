import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

/// Manager queue for project-access requests.
///
/// Requests come from `GET /api/v1/access-requests?status=pending`
/// (migration 0002 flow): each request already carries the project the
/// employee wants, so approving just decides it — the project picker
/// from the Firebase era is gone.
class ProjectAccessRequestsScreen extends StatefulWidget {
  const ProjectAccessRequestsScreen({super.key});

  @override
  State<ProjectAccessRequestsScreen> createState() => _ProjectAccessRequestsScreenState();
}

class _ProjectAccessRequestsScreenState extends State<ProjectAccessRequestsScreen> {
  Future<void> _handleRequest(BuildContext context, Map<String, dynamic> request, bool isApproved) async {
    final store = ExpenseStore.instance;
    final requestId = request['access_request_id']?.toString() ?? '';
    if (requestId.isEmpty) return;

    final name = request['name']?.toString() ?? 'Unknown';
    final projectName = request['projectName']?.toString() ?? 'unknown project';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: store.card,
        title: Text(
          isApproved ? 'Approve Access' : 'Deny Access',
          style: TextStyle(color: store.accentGold),
        ),
        content: Text(
          isApproved
              ? 'Grant $name membership on "$projectName"?'
              : 'Reject $name\'s request for "$projectName"?',
          style: TextStyle(color: store.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: store.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isApproved ? store.accentGold : Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isApproved ? 'Approve' : 'Deny'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await store.decideProjectAccess(requestId, isApproved);
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final requests = store.projectRequests;

        return Scaffold(
          backgroundColor: store.bg,
          appBar: AppBar(
            backgroundColor: store.card,
            title: Text('Project Access Requests', style: TextStyle(color: store.accentGold)),
            iconTheme: IconThemeData(color: store.accentGold),
          ),
          body: RefreshIndicator(
            color: store.accentGold,
            onRefresh: store.fetchProjectRequestsFromBackend,
            child: requests.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 160),
                      Center(
                        child: Text(
                          'No pending requests.',
                          style: TextStyle(color: store.textMuted),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final req = requests[index];
                      final email = req['email']?.toString() ?? '';
                      final name = req['name']?.toString() ?? 'Unknown';
                      final projectName = req['projectName']?.toString() ?? '';

                      return Card(
                        color: store.card,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(
                            name,
                            style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            projectName.isEmpty ? email : '$email\nWants to join: $projectName',
                            style: TextStyle(color: store.textMuted),
                          ),
                          isThreeLine: projectName.isNotEmpty,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                                onPressed: () async {
                                  await _handleRequest(context, req, false);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                                onPressed: () async {
                                  await _handleRequest(context, req, true);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}
