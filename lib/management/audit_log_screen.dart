import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../data/audit_repository.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The organization's audit trail: who changed what, and when.
///
/// The backend owns the trail (admin-only, cursor-paginated); this screen
/// reads it, filters it by the table that changed and lets a row expand
/// into the values before and after the change.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  static const List<String> _tables = <String>[
    'All',
    'expenses',
    'budgets',
    'projects',
    'users',
    'project_members',
  ];

  final AuditRepository _repository = const AuditRepository();
  final List<AuditEntry> _entries = <AuditEntry>[];

  String _table = 'All';
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _entries.clear();
      _cursor = null;
    });
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final AuditPage page = await _repository.fetchPage(
        cursor: _cursor,
        tableName: _table == 'All' ? null : _table,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the audit trail.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _fetch();
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: const Text('Audit trail'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reload',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: AppFilterBar(
              options: _tables,
              value: _table,
              onChanged: (String value) {
                setState(() => _table = value);
                _load();
              },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load the audit trail',
                      message: _error!,
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  )
                : _entries.isEmpty
                ? Center(
                    child: EmptyState(
                      icon: Icons.history_toggle_off_rounded,
                      title: 'No entries yet',
                      message:
                          'Changes to expenses, budgets and projects are '
                          'recorded here.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                    itemCount: _entries.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      if (index >= _entries.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _loadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton.icon(
                                    onPressed: _loadMore,
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Load more'),
                                  ),
                          ),
                        );
                      }
                      return _AuditRow(entry: _entries[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the trail, expandable into the values that changed.
class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color tone = _tone(entry.action, palette);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Icon(_icon(entry.action), color: tone, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.readableAction,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.tableName} · record ${entry.recordId}'
                      '${entry.actorId == null ? '' : ' · by #${entry.actorId}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDateTime(entry.createdAt),
                      style: TextStyle(
                        color: palette.muted.withValues(alpha: 0.75),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entry.oldValues != null || entry.newValues != null) ...<Widget>[
            const SizedBox(height: 10),
            _ValueTable(
              title: 'Before',
              values: entry.oldValues,
              palette: palette,
            ),
            const SizedBox(height: 6),
            _ValueTable(
              title: 'After',
              values: entry.newValues,
              palette: palette,
            ),
          ],
        ],
      ),
    );
  }

  static Color _tone(String action, AppPalette palette) {
    if (action.contains('reject') || action.contains('delete')) {
      return palette.danger;
    }
    if (action.contains('approve') || action.contains('create')) {
      return palette.success;
    }
    if (action.contains('update') || action.contains('submit')) {
      return palette.info;
    }
    return palette.gold;
  }

  static IconData _icon(String action) {
    if (action.contains('reject')) return Icons.cancel_outlined;
    if (action.contains('approve')) return Icons.check_circle_outline_rounded;
    if (action.contains('budget')) return Icons.account_balance_wallet_rounded;
    if (action.contains('project')) return Icons.workspaces_outlined;
    if (action.contains('user')) return Icons.person_outline_rounded;
    if (action.contains('expense')) return Icons.receipt_long_rounded;
    return Icons.history_rounded;
  }
}

/// The values of one side of a change.
class _ValueTable extends StatelessWidget {
  const _ValueTable({
    required this.title,
    required this.values,
    required this.palette,
  });

  final String title;
  final Map<String, dynamic>? values;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> map = values ?? const <String, dynamic>{};
    if (map.isEmpty) {
      return Text(
        '$title: —',
        style: TextStyle(color: palette.muted, fontSize: 11.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: palette.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: map.entries
              .map(
                (MapEntry<String, dynamic> e) =>
                    AppTag(label: '${e.key}: ${e.value}', dense: true),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}
