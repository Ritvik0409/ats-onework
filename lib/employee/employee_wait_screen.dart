import 'package:flutter/material.dart';

import '../management/expense_store.dart';
import '../shared/api_client.dart';
import '../shared/app_snack.dart';
import '../shared/login_screen.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Shown to an employee who is verified but has not been assigned to a
/// project yet — they cannot submit claims without one.
class EmployeeWaitScreen extends StatelessWidget {
  const EmployeeWaitScreen({super.key});

  /// Requests are per-project (migration 0002): pick a project first,
  /// then POST /projects/{id}/access-requests.
  Future<void> _pickAndRequestProject(
    BuildContext context,
    ExpenseStore store,
  ) async {
    // Keep the project list fresh before choosing.
    await store.fetchProjectsFromBackend();
    final List<ProjectRecord> activeProjects = store.projects
        .where((ProjectRecord p) => p.isActive)
        .toList(growable: false);
    if (!context.mounted) return;

    String? selectedProjectId;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final AppPalette palette = context.palette;
          return AlertDialog(
            title: const Text('Request project access'),
            content: activeProjects.isEmpty
                ? Text(
                    'No projects are currently synced. Ask your manager to '
                    'create one.',
                    style: TextStyle(color: palette.muted),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: selectedProjectId,
                    dropdownColor: palette.surfaceAlt,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select a project',
                    ),
                    items: activeProjects
                        .map(
                          (ProjectRecord p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? value) =>
                        setDialogState(() => selectedProjectId = value),
                  ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedProjectId == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Send request'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedProjectId == null || !context.mounted) {
      return;
    }
    final bool sent = await store.submitProjectAccessRequest(
      selectedProjectId!,
    );
    if (!context.mounted) return;
    if (sent) {
      AppSnack.success(
        context,
        'Access request sent — a manager will review it.',
      );
    } else {
      AppSnack.error(context, 'Could not send the access request.');
    }
  }

  Future<void> _refreshProjects() async {
    await ExpenseStore.instance.fetchProjectsFromBackend();
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseStore store = ExpenseStore.instance;
    final AppPalette palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(title: const Text('Account setup')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AppCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: palette.gold.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.gold, width: 1.5),
                    ),
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      color: palette.gold,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Awaiting assignment',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your account is verified, but you have not been assigned '
                    'to a project yet. A claim needs a project.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () => _pickAndRequestProject(context, store),
                      icon: const Icon(Icons.mail_outline_rounded, size: 18),
                      label: const Text('Request project access'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton.icon(
                      onPressed: _refreshProjects,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Refresh — maybe you were just assigned',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.danger,
                        side: BorderSide(
                          color: palette.danger.withValues(alpha: 0.5),
                        ),
                      ),
                      onPressed: () async {
                        // Revokes the refresh token and clears the
                        // local JWT store (api_client.dart).
                        await ApiClient.signOut();
                        // Drop the previous user's data from the shared
                        // store.
                        ExpenseStore.instance.resetForSignOut();
                        if (!context.mounted) return;
                        Navigator.of(
                          context,
                          rootNavigator: true,
                        ).pushAndRemoveUntil(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const UniversalLoginScreen(),
                          ),
                          (Route<dynamic> route) => false,
                        );
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
