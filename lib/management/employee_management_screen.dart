import 'package:flutter/material.dart';

import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The directory: who is in the organization and whether their access is
/// active.
class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final ExpenseStore store = ExpenseStore.instance;
  String _searchQuery = '';

  Future<void> _confirmToggle(
    String email,
    String name,
    bool currentlyActive,
  ) async {
    final String action = currentlyActive ? 'Deactivate' : 'Reactivate';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final AppPalette palette = context.palette;
        return AlertDialog(
          title: Text('$action $name?'),
          content: Text(
            currentlyActive
                ? '$name will no longer be able to sign in or submit '
                      'expenses.'
                : '$name will regain access to the portal.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: currentlyActive
                    ? palette.danger
                    : palette.success,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await store.setEmployeeActive(email, !currentlyActive);
    if (!mounted) return;
    if (currentlyActive) {
      AppSnack.error(context, '$name deactivated');
    } else {
      AppSnack.success(context, '$name reactivated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;

        final List<Map<String, dynamic>> employees = store.allEmployees
            .where((Map<String, dynamic> e) {
              final String query = _searchQuery.trim().toLowerCase();
              if (query.isEmpty) return true;
              return (e['name']?.toString() ?? '').toLowerCase().contains(
                    query,
                  ) ||
                  (e['email']?.toString() ?? '').toLowerCase().contains(query);
            })
            .toList(growable: false);

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('People')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: AppSearchField(
                  hint: 'Search by name or email…',
                  onChanged: (String value) =>
                      setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: !store.usersLoaded
                    ? const Center(child: CircularProgressIndicator())
                    : employees.isEmpty
                    ? Center(
                        child: EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: _searchQuery.isEmpty
                              ? 'No people yet'
                              : 'No matches',
                          message: _searchQuery.isEmpty
                              ? 'People appear here once they join the '
                                    'organization.'
                              : 'Try another name or email.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                        itemCount: employees.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> person = employees[index];
                          final String email =
                              person['email']?.toString() ?? '';
                          final String name = person['name']?.toString() ?? '';
                          final bool isActive = store.isEmployeeActive(email);
                          final Color tone = isActive
                              ? palette.success
                              : palette.danger;

                          return AppCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: palette.gold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.radiusSm,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: palette.gold,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      AppTag(
                                        label: isActive
                                            ? 'Active'
                                            : 'Deactivated',
                                        color: tone,
                                        dense: true,
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeThumbColor: palette.gold,
                                  onChanged: (_) =>
                                      _confirmToggle(email, name, isActive),
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
