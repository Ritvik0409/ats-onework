import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/formatting.dart';
import '../management/expense_store.dart';
import 'tokens.dart';

/// What happened in the "mark as paid" dialog.
enum MarkPaidOutcome {
  /// The server confirmed the payout.
  paid,

  /// The user closed the dialog without paying.
  cancelled,

  /// The server refused the payout. The dialog stays open so the
  /// transaction ID the user typed is not thrown away.
  failed,
}

/// Opens the "mark as paid" dialog and runs the payout.
///
/// Both the finance dashboard and the claim detail screen use this — the
/// payout flow is the same action with the same audit requirements, and
/// it used to exist twice with different behaviour (one of them closed
/// the dialog even when the payment failed).
Future<MarkPaidOutcome> showMarkPaidDialog(
  BuildContext context,
  ExpenseRecord expense, {
  ExpenseStore? store,
}) async {
  final ExpenseStore expenseStore = store ?? ExpenseStore.instance;
  final TextEditingController txController = TextEditingController();
  Uint8List? paymentReceiptBytes;
  String? serverError;
  MarkPaidOutcome outcome = MarkPaidOutcome.cancelled;

  // Double-submit guard: a second tap while the payout call is in
  // flight must not send the same payment twice.
  bool submitting = false;

  await showDialog<void>(
    context: context,
    // An accidental tap outside the dialog must not discard the
    // typed transaction ID, so barrier dismissal is off — the only
    // way out is Cancel or a completed payment.
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        final AppPalette palette = AppPalette.of(context);

        // One guarded submit path, shared by the keyboard (Enter on
        // the transaction ID field) and the confirm button.
        Future<void> submitPayment() async {
          if (submitting) return;
          if (txController.text.trim().isEmpty) {
            serverError = 'Transaction ID is compulsory.';
            setDialogState(() {});
            return;
          }
          setDialogState(() => submitting = true);
          final String? failure = await expenseStore.markPaid(
            expense.id,
            txController.text.trim(),
            receiptBytes: paymentReceiptBytes,
          );
          if (!dialogContext.mounted) return;
          setDialogState(() => submitting = false);
          if (failure != null) {
            // Keep the dialog open so the typed reference survives.
            serverError = failure;
            setDialogState(() {});
            return;
          }
          outcome = MarkPaidOutcome.paid;
          Navigator.pop(dialogContext);
        }

        return AlertDialog(
          title: const Text('Mark expense as paid'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Transaction ID is required for the audit trail. '
                  '${formatMoney(expense.amount)} to ${expense.name}.',
                  style: TextStyle(color: palette.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: txController,
                  autofocus: true,
                  // The transaction ID is the last field in the dialog,
                  // so the keyboard's action closes it out.
                  textInputAction: TextInputAction.done,
                  // Enter on the keyboard runs the same guarded path
                  // as the confirm button.
                  onSubmitted: (_) => submitPayment(),
                  decoration: InputDecoration(
                    labelText: 'Transaction ID *',
                    hintText: 'UPI / NEFT reference',
                    errorText: serverError,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final XFile? image = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                          );
                          if (image == null) return;
                          final Uint8List bytes = await image.readAsBytes();
                          // The dialog can be dismissed while the gallery
                          // picker is open.
                          if (!dialogContext.mounted) return;
                          setDialogState(() => paymentReceiptBytes = bytes);
                        },
                        icon: Icon(
                          paymentReceiptBytes == null
                              ? Icons.receipt_long_rounded
                              : Icons.check_circle_rounded,
                          size: 18,
                        ),
                        label: Text(
                          paymentReceiptBytes == null
                              ? 'Attach receipt (optional)'
                              : 'Receipt attached',
                        ),
                      ),
                    ),
                    if (paymentReceiptBytes != null) ...<Widget>[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Remove receipt',
                        onPressed: () =>
                            setDialogState(() => paymentReceiptBytes = null),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ],
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
              // Locked while a payout is in flight so the guard above
              // also shows up as a disabled button, not just as a
              // silently ignored tap.
              onPressed: submitting ? null : () => submitPayment(),
              child: const Text('Confirm payment'),
            ),
          ],
        );
      },
    ),
  );

  txController.dispose();
  return outcome;
}
