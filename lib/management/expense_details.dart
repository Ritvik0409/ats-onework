import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/status.dart';
import '../shared/api_client.dart';
import '../shared/app_snack.dart';
import '../ui/mark_paid_dialog.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'expense_store.dart';

/// One claim in full: who sent it, the receipt, the details and the
/// action the signed-in person is allowed to take on it.
class ExpenseDetailsScreen extends StatefulWidget {
  const ExpenseDetailsScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;

  // ---------------------------------------------------------------- actions

  Future<void> _handleApprove() async {
    final bool? confirmed = await _confirm(
      title: 'Approve this expense?',
      message:
          'This will mark the request as Approved. The action cannot be undone.',
      confirmLabel: 'Yes, approve',
      confirmColor: context.palette.success,
    );
    if (confirmed != true || !mounted) return;
    // Wait for the backend — no success toast before the server confirms.
    final bool ok = await _store.approve(widget.expenseId);
    if (!mounted) return;
    if (ok) {
      AppSnack.success(context, 'Expense approved.');
      Navigator.of(context).pop();
    } else {
      AppSnack.error(context, 'Could not approve the expense.');
    }
  }

  Future<void> _handleReject() async {
    final String? reason = await _askForReason(
      title: 'Reject this expense?',
      message:
          'This will mark the request as Rejected. The action cannot be undone.',
      hint: 'e.g. Missing itemised receipt, amount exceeds the policy limit…',
      validationMessage:
          'A reason is required so the employee understands why.',
      confirmLabel: 'Yes, reject',
      confirmColor: context.palette.danger,
    );
    if (reason == null || !mounted) return;
    final bool ok = await _store.reject(widget.expenseId, reason: reason);
    if (!mounted) return;
    if (ok) {
      AppSnack.success(context, 'Expense rejected.');
      Navigator.of(context).pop();
    } else {
      AppSnack.error(context, 'Could not reject the expense.');
    }
  }

  Future<void> _handleRequestInfo() async {
    final String? message = await _askForReason(
      title: 'Request more information?',
      message: 'The employee will be notified with the message below.',
      hint: 'e.g. Please attach the itemised receipt…',
      validationMessage: 'Tell the employee what is missing.',
      confirmLabel: 'Send request',
      confirmColor: context.palette.gold,
    );
    if (message == null || !mounted) return;
    final bool ok = await _store.requestMoreInfo(
      widget.expenseId,
      message: message,
    );
    if (!mounted) return;
    if (ok) {
      AppSnack.success(context, 'Additional info requested from the employee.');
      Navigator.of(context).pop();
    } else {
      AppSnack.error(context, 'Could not send the info request.');
    }
  }

  Future<void> _handleMarkPaid(ExpenseRecord expense) async {
    final MarkPaidOutcome outcome = await showMarkPaidDialog(
      context,
      expense,
      store: _store,
    );
    if (!mounted) return;
    if (outcome == MarkPaidOutcome.paid) {
      AppSnack.success(context, 'Expense marked as paid.');
    }
  }

  /// A yes/no confirmation. Returns null when the user backs out.
  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// A dialog that needs a written reason — a rejection or a question.
  /// Returns null when the user backs out.
  Future<String?> _askForReason({
    required String title,
    required String message,
    required String hint,
    required String validationMessage,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final TextEditingController controller = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(message, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              TextFormField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(hintText: hint),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                    ? validationMessage
                    : null,
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
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  // ---------------------------------------------------------------- receipt

  /// The receipt field holds a server URL (after §15 object storage) — or
  /// legacy base64 data from before the migration. Render accordingly.
  ///
  /// The backend stores receipts under a *relative* path
  /// (`/uploads/receipts/...`), so it is resolved against the API base
  /// URL. Decoding it as base64 threw a FormatException from inside
  /// `build`, which `errorBuilder` cannot catch.
  ImageProvider<Object> _receiptImageProvider(String receipt) {
    if (receipt.startsWith('http://') || receipt.startsWith('https://')) {
      return NetworkImage(receipt);
    }
    if (receipt.startsWith('/')) {
      return NetworkImage('${ApiClient.baseUrl}$receipt');
    }
    if (receipt.startsWith('data:')) {
      final int comma = receipt.indexOf(',');
      if (comma > 0) {
        return MemoryImage(base64Decode(receipt.substring(comma + 1)));
      }
    }
    // Legacy inline base64 without a data-URI prefix.
    try {
      return MemoryImage(base64Decode(receipt));
    } catch (_) {
      return NetworkImage('${ApiClient.baseUrl}/$receipt');
    }
  }

  void _showFullScreenImage(String receipt) {
    final ImageProvider<Object> imageProvider = _receiptImageProvider(receipt);
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image(
                image: imageProvider,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Text(
                    'Receipt file unavailable.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final ExpenseRecord? expense = _store.byIdOrNull(widget.expenseId);

        if (expense == null) {
          // Stale row (deleted or refetched away) — a friendly state
          // instead of a red screen.
          return Scaffold(
            backgroundColor: palette.bg,
            appBar: AppBar(title: const Text('Expense details')),
            body: Center(
              child: EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'This claim is no longer available',
                message:
                    'It was removed or is outside the loaded page. Pull to '
                    'refresh the list and try again.',
                action: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go back'),
                ),
              ),
            ),
          );
        }

        final bool isLocked = _store.isLocked(widget.expenseId);
        // The capability decides, not the name of a role: disbursing is
        // whoever holds `reimbursement.transition`.
        final bool canPay = _store.canPayReimbursements;
        final bool isOwnExpense = _store.isOwnExpense(expense);

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('Expense details')),
          body: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _header(expense, palette),
                      const SizedBox(height: 18),
                      _section('Receipt', palette, _receipt(expense, palette)),
                      const SizedBox(height: 18),
                      _section(
                        'Request details',
                        palette,
                        _details(expense, palette),
                      ),
                      const SizedBox(height: 26),
                      _actions(
                        expense,
                        palette,
                        canPay,
                        isLocked,
                        isOwnExpense,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(ExpenseRecord expense, AppPalette palette) {
    final Color tone = statusColor(expense.status, palette);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              expense.name.isNotEmpty ? expense.name.substring(0, 1) : '?',
              style: TextStyle(
                color: tone,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  expense.name,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  expense.email,
                  style: TextStyle(color: palette.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    AppTag(
                      label: expense.id,
                      icon: Icons.badge_outlined,
                      dense: true,
                    ),
                    StatusBadge(
                      status: expense.status,
                      color: tone,
                      label: statusLabel(expense.status),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatMoney(expense.amount),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                expense.date,
                style: TextStyle(color: palette.muted, fontSize: 11.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(String title, AppPalette palette, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: title),
        child,
      ],
    );
  }

  Widget _receipt(ExpenseRecord expense, AppPalette palette) {
    final String? receipt = expense.receiptBase64;
    if (receipt == null || receipt.isEmpty) {
      return AppCard(
        child: EmptyState(
          icon: Icons.image_not_supported_outlined,
          title: 'No receipt attached',
          message: 'The submitter did not upload a receipt for this claim.',
          compact: true,
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          GestureDetector(
            onTap: () => _showFullScreenImage(receipt),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  child: Container(
                    color: palette.surfaceAlt,
                    child: Image(
                      image: _receiptImageProvider(receipt),
                      height: 280,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          'Receipt file unavailable.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black54,
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap the image to view it full screen.',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _details(ExpenseRecord expense, AppPalette palette) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          if (expense.projectName != null && expense.projectName!.isNotEmpty)
            _detailRow(
              'Project assigned',
              expense.projectName!,
              palette,
              tag: true,
            ),
          _detailRow('Expense type', expense.type, palette),
          _detailRow('Amount', formatMoney(expense.amount), palette),
          if (expense.description.isNotEmpty)
            _detailRow('Description', expense.description, palette),
          _detailRow('Date', expense.date, palette),
          if (expense.status == 'Rejected' && expense.rejectionReason != null)
            _detailRow('Rejection reason', expense.rejectionReason!, palette),
          if (expense.status == 'Info Requested' && expense.infoMessage != null)
            _detailRow('Reviewer asked', expense.infoMessage!, palette),
          if (expense.infoResponse != null && expense.infoResponse!.isNotEmpty)
            _detailRow('Employee answered', expense.infoResponse!, palette),
          if (expense.processedBy != null)
            _detailRow('Processed by', expense.processedBy!, palette),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    AppPalette palette, {
    bool tag = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: tag
                ? Align(
                    alignment: Alignment.centerRight,
                    child: AppTag(label: value),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _actions(
    ExpenseRecord expense,
    AppPalette palette,
    bool canPay,
    bool isLocked,
    bool isOwnExpense,
  ) {
    if (canPay && expense.status == 'Approved') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Finance action'),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _handleMarkPaid(expense),
              icon: const Icon(Icons.payments_rounded, size: 20),
              label: const Text(
                'Mark as paid & disburse',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      );
    }

    if (canPay && expense.status == 'Paid') {
      return AppCard(
        borderColor: palette.success.withValues(alpha: 0.35),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: palette.success),
            const SizedBox(width: 8),
            Text(
              'Payment disbursed successfully',
              style: TextStyle(
                color: palette.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    // The approver's side.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Approval action',
          trailing: isLocked
              ? StatusBadge(
                  status: expense.status,
                  color: statusColor(expense.status, palette),
                  label: statusLabel(expense.status),
                  icon: Icons.lock_rounded,
                )
              : isOwnExpense
              ? StatusBadge(
                  status: 'Self-submitted',
                  color: palette.warning,
                  label: 'You cannot approve this',
                  icon: Icons.person_off_rounded,
                )
              : null,
        ),
        if (!isLocked && !isOwnExpense)
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _handleApprove,
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _handleReject,
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.gold,
                      side: BorderSide(
                        color: palette.gold.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _handleRequestInfo,
                    icon: const Icon(Icons.info_rounded, size: 18),
                    label: const Text('Ask'),
                  ),
                ),
              ),
            ],
          ),
        if (!isLocked && isOwnExpense)
          AppCard(
            borderColor: palette.warning.withValues(alpha: 0.35),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.lock_person_rounded, color: palette.warning),
                const SizedBox(width: 8),
                Text(
                  'You cannot approve your own expenses.',
                  style: TextStyle(
                    color: palette.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
