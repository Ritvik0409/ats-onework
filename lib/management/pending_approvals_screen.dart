import 'package:flutter/material.dart';

import '../management/budget_setup_screen.dart';
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

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

  void _showApproveDialog(
    BuildContext context,
    Map<String, dynamic> requestData,
    ExpenseStore store,
  ) {
    final String employeeName = requestData['name']?.toString() ?? 'Unknown';
    final String employeeEmail = requestData['email']?.toString() ?? '';
    final String projectName = requestData['projectName']?.toString() ?? '';
    final String requestId = requestData['access_request_id']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Grant project access'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$employeeName ($employeeEmail) wants to join:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                projectName.isEmpty ? 'Unknown project' : projectName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => BudgetSetupScreen(
                          initialEmployeeEmail: employeeEmail,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create a new project instead'),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: requestId.isEmpty
                ? null
                : () async {
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    final bool ok = await store.decideProjectAccess(
                      requestId,
                      true,
                    );
                    if (!context.mounted) return;
                    if (ok) {
                      AppSnack.success(
                        context,
                        '$employeeName assigned successfully.',
                      );
                    } else {
                      AppSnack.error(context, 'Could not approve the request.');
                    }
                  },
            child: const Text('Confirm & grant access'),
          ),
        ],
      ),
    );
  }

  void _handleDeny(
    BuildContext context,
    Map<String, dynamic> requestData,
    ExpenseStore store,
  ) {
    final String employeeName = requestData['name']?.toString() ?? 'Unknown';
    final String requestId = requestData['access_request_id']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppPalette palette = context.palette;
        return AlertDialog(
          title: Text('Deny access for $employeeName?'),
          content: const Text(
            'This will dismiss the request.',
            style: TextStyle(fontSize: 13),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: palette.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: requestId.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      final bool ok = await store.decideProjectAccess(
                        requestId,
                        false,
                      );
                      if (!context.mounted) return;
                      if (ok) {
                        AppSnack.info(
                          context,
                          'Project access request denied.',
                        );
                      } else {
                        AppSnack.error(context, 'Could not deny the request.');
                      }
                    },
              child: const Text('Yes, deny'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseStore store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        // Data path: GET /api/v1/access-requests?status=pending
        // (store.projectRequests, migration 0002 flow).
        //
        // The list is read straight from the store. It used to be
        // wrapped in a FutureBuilder, which started a new request
        // on every rebuild — and the fetch notifies listeners, so
        // the screen refetched itself forever.
        final List<Map<String, dynamic>> requests = store.projectRequests;

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('Project access requests')),
          body: requests.isEmpty
              ? Center(
                  child: EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'All caught up',
                    message: 'No one is waiting for a project assignment.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                  itemCount: requests.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final Map<String, dynamic> request = requests[index];
                    final String name =
                        request['name']?.toString() ?? 'Unknown';
                    return AppCard(
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: palette.gold.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              store.getInitials(name),
                              style: TextStyle(
                                color: palette.gold,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${request['email'] ?? ''} · wants to join '
                                  '${request['projectName'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: palette.danger,
                              side: BorderSide(
                                color: palette.danger.withValues(alpha: 0.4),
                              ),
                            ),
                            onPressed: () =>
                                _handleDeny(context, request, store),
                            child: const Text('Deny'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () =>
                                _showApproveDialog(context, request, store),
                            child: const Text('Approve'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
