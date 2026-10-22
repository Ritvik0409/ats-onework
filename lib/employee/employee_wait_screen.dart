import 'package:flutter/material.dart';

import '../management/expense_store.dart';
import '../shared/api_client.dart';
import '../shared/app_snack.dart';
import '../shared/login_screen.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Shown to an employee who is verified but has not been assigned to a
/// project yet — they cannot submit claims without one.
class EmployeeWaitScreen extends StatefulWidget {
  const EmployeeWaitScreen({super.key});

  @override
  State<EmployeeWaitScreen> createState() => _EmployeeWaitScreenState();
}

class _EmployeeWaitScreenState extends State<EmployeeWaitScreen> {
  /// One request at a time: the button locks while the access request is
  /// in flight so a second tap cannot stack a second dialog on top of
  /// the first one.
  bool _requesting = false;

  /// True while sign-out is actually running — the button shows a
  /// spinner instead of spawning a second sign-out.
  bool _signingOut = false;

  /// Requests are per-project (migration 0002): pick a project first,
  /// then POST /projects/{id}/access-requests.
  Future<void> _pickAndRequestProject() async {
    if (_requesting || _signingOut) return;
    setState(() => _requesting = true);
    try {
      final ExpenseStore store = ExpenseStore.instance;
      // Keep the project list fresh before choosing.
      await store.fetchProjectsFromBackend();
      if (!mounted) return;
      final String? selectedProjectId = await _showProjectPickerDialog(store);
      if (selectedProjectId == null || !mounted) return;
      final bool sent = await store.submitProjectAccessRequest(
        selectedProjectId,
      );
      if (!mounted) return;
      if (sent) {
        AppSnack.success(
          context,
          'Access request sent — a manager will review it.',
        );
      } else {
        AppSnack.error(context, 'Could not send the access request.');
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  /// The project picker. Returns the chosen project id, or null when the
  /// dialog was dismissed (or a retry of a failed load left nothing to
  /// pick from).
  Future<String?> _showProjectPickerDialog(ExpenseStore store) {
    String? selectedProjectId;
    bool retrying = false;
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final AppPalette palette = context.palette;
          final List<ProjectRecord> activeProjects = store.projects
              .where((ProjectRecord p) => p.isActive)
              .toList(growable: false);
          return AlertDialog(
            title: const Text('Request project access'),
            content: store.projectsError != null
                ? EmptyState(
                    // A failed sync is not "ask your manager to create a
                    // project" — show the real reason and let the user
                    // retry before the picker is worth opening again.
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load projects",
                    message: store.projectsError,
                    compact: true,
                    action: OutlinedButton(
                      onPressed: retrying
                          ? null
                          : () async {
                              setDialogState(() => retrying = true);
                              await store.fetchProjectsFromBackend();
                              if (dialogContext.mounted) {
                                setDialogState(() => retrying = false);
                              }
                            },
                      child: const Text('Retry'),
                    ),
                  )
                : activeProjects.isEmpty
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedProjectId == null
                    ? null
                    : () => Navigator.pop(dialogContext, selectedProjectId),
                child: const Text('Send request'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refreshProjects() async {
    await ExpenseStore.instance.fetchProjectsFromBackend();
  }

  /// Confirm first — sign-out is instant and irreversible — then run it
  /// while the button is locked.
  Future<void> _signOut() async {
    if (_signingOut) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppPalette palette = context.palette;
        return AlertDialog(
          title: Text(
            'Log out?',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You will need to sign in again.',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: palette.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Log out',
                style: TextStyle(
                  color: palette.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    // Revokes the refresh token and clears the local JWT store
    // (api_client.dart).
    await ApiClient.signOut();
    // Drop the previous user's data from the shared store.
    ExpenseStore.instance.resetForSignOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const UniversalLoginScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: (_requesting || _signingOut)
                          ? null
                          : _pickAndRequestProject,
                      icon: _requesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mail_outline_rounded, size: 18),
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
                      onPressed: (_requesting || _signingOut) ? null : _signOut,
                      icon: _signingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.logout_rounded, size: 18),
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
