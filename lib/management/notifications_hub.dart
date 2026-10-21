import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'expense_store.dart';

/// The single notification feed. The backend endpoint is owner-scoped,
/// so the same screen serves employees and managers; grouping is done
/// with filters instead of four PageViews.
class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({super.key});

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen> {
  static const List<String> _filters = <String>[
    'All',
    'Action needed',
    'Approved',
    'Rejected',
  ];

  final ExpenseStore _store = ExpenseStore.instance;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await _store.fetchNotificationsFromBackend();
    await _store.markNotificationsSeen();
  }

  List<AppNotification> _visible() {
    final List<AppNotification> all = _store.notifications;
    switch (_filter) {
      case 'Action needed':
        return all
            .where(
              (AppNotification n) => n.type == 'info' || n.type == 'resubmit',
            )
            .toList(growable: false);
      case 'Approved':
        return all
            .where((AppNotification n) => n.type == 'approved')
            .toList(growable: false);
      case 'Rejected':
        return all
            .where((AppNotification n) => n.type == 'rejected')
            .toList(growable: false);
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final List<AppNotification> items = _visible();

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: AppPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _filters
                      .map(
                        (String filter) => ChoiceChip(
                          label: Text(filter),
                          selected: _filter == filter,
                          onSelected: (bool selected) {
                            if (selected) setState(() => _filter = filter);
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: _filter == 'All'
                          ? 'No activity yet'
                          : 'Nothing in this filter',
                      message: _filter == 'All'
                          ? 'Approvals, questions and payments will appear here.'
                          : 'Try another filter to see the rest of your feed.',
                    ),
                  )
                else
                  ...items.map(
                    (AppNotification item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _NotificationCard(item: item),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final (IconData icon, Color color) = switch (item.type) {
      'approved' => (Icons.check_circle_rounded, palette.success),
      'rejected' => (Icons.cancel_rounded, palette.danger),
      'info' => (Icons.help_outline_rounded, palette.warning),
      'paid' => (Icons.payments_rounded, palette.success),
      'resubmit' => (Icons.replay_rounded, palette.info),
      'project-added' => (Icons.workspaces_rounded, palette.info),
      'project-approved' => (Icons.verified_rounded, palette.success),
      'project-rejected' => (Icons.block_rounded, palette.danger),
      _ => (Icons.notifications_none_rounded, palette.gold),
    };

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title.isEmpty ? 'Notification' : item.title,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (item.subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
                if (item.time.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _when(item),
                    style: TextStyle(
                      color: palette.muted.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "2h ago" for the last week, the date for anything older.
  String _when(AppNotification item) {
    final DateTime? createdAt = item.createdAt;
    if (createdAt == null) return item.time;
    final Duration age = DateTime.now().difference(createdAt);
    if (age.inDays >= 7 || age.isNegative) return item.time;
    return relativeTime(createdAt);
  }
}

/// Kept for existing deep links; the employee feed is now the shared hub
/// so both portals show the same notifications with the same styling.
class EmployeeNotificationsScreen extends StatelessWidget {
  const EmployeeNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotificationsHubScreen();
}
