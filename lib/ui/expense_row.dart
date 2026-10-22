import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/status.dart';
import '../management/expense_store.dart';
import 'tokens.dart';
import 'widgets.dart';

/// The one expense row the list screens share.
///
/// The employee's "my claims", the review queue, the payout lists and
/// the project pages all showed the same information in four different
/// ways — four copies of the card decoration, the initials bubble, the
/// status pill and the amount block. This widget is that row, themed
/// once.
class ExpenseRow extends StatelessWidget {
  const ExpenseRow({
    super.key,
    required this.expense,
    this.onTap,
    this.showOwner = true,
    this.showId = false,
    this.highValueThreshold = 30000,
    this.trailing,
    this.note,
  });

  final ExpenseRecord expense;
  final VoidCallback? onTap;

  /// Shows the submitter's name. Off for the employee's own list, where
  /// the name is always the same person.
  final bool showOwner;

  /// Appends the claim id next to the date.
  final bool showId;

  /// Amounts above this are flagged for the reviewer.
  final double highValueThreshold;

  /// Extra control under the status badge (a resubmit button, a pay
  /// button).
  final Widget? trailing;

  /// A note under the row — a rejection reason or a manager's question.
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color tone = statusColor(expense.status, palette);
    final bool highValue = expense.amount > highValueThreshold;

    final List<String> meta = <String>[
      if (showOwner && expense.name.isNotEmpty) expense.name,
      if (expense.date.isNotEmpty) expense.date,
      if (showId && expense.id.isNotEmpty) expense.id,
    ];

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      borderColor: highValue ? palette.danger.withValues(alpha: 0.35) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(expense.name),
              style: TextStyle(
                color: tone,
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
                // The claim type always leads on its own line; the project
                // tag sits in its own steady slot below it. A Wrap of
                // title+tag used to make the tag jump between "beside the
                // title" and "under it" depending on length, so adjacent
                // cards never looked related.
                Text(
                  expense.type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (expense.projectName != null &&
                    expense.projectName!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  AppTag(
                    label: expense.projectName!,
                    icon: Icons.workspaces_rounded,
                    dense: true,
                  ),
                ],
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
                if (note != null) ...<Widget>[const SizedBox(height: 6), note!],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (highValue) ...<Widget>[
                    Icon(
                      Icons.warning_amber_rounded,
                      color: palette.danger,
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    formatMoney(expense.amount),
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              StatusBadge(
                status: expense.status,
                color: tone,
                label: statusLabel(expense.status),
              ),
              // An approved claim is not paid yet — say so under the
              // badge instead of stretching the badge across the row.
              if (expense.status == 'Approved') ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'Payment pending',
                  style: TextStyle(color: palette.muted, fontSize: 10),
                ),
              ],
              if (trailing != null) ...<Widget>[
                const SizedBox(height: 8),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
