import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/api_client.dart';

class ExpenseDetailsScreen extends StatefulWidget {
  final String expenseId;

  const ExpenseDetailsScreen({super.key, required this.expenseId});

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;

  // Custom soft amber color to replace harsh bright yellow snackbars
  static const Color _softAmber = Color(0xFFD4AF37);

  void _showMarkPaidDialog(BuildContext context, String expenseId, ExpenseStore store) {
    final txController = TextEditingController();
    Uint8List? paymentReceiptBytes;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: store.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: store.accentGold.withValues(alpha: 0.2)),
          ),
          title: Text('Mark Expense as Paid', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Transaction ID is compulsory.', style: TextStyle(color: store.textMuted, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: txController,
                style: TextStyle(color: store.textFrost),
                decoration: InputDecoration(
                  labelText: 'Transaction ID *',
                  labelStyle: TextStyle(color: store.textMuted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: store.accentGold.withValues(alpha: 0.3))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final image = await picker.pickImage(source: ImageSource.gallery);
                        if (image == null) return;
                        final bytes = await image.readAsBytes();
                        // The dialog can be dismissed while the gallery
                        // picker is open.
                        if (!dialogContext.mounted) return;
                        setDialogState(() => paymentReceiptBytes = bytes);
                      },
                      icon: Icon(Icons.receipt_long_rounded, color: store.accentGold, size: 18),
                      label: Text(paymentReceiptBytes == null ? 'Attach Receipt (Opt.)' : 'Receipt Attached', style: TextStyle(color: store.accentGold)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: store.accentGold.withValues(alpha: 0.3))),
                    ),
                  ),
                  if (paymentReceiptBytes != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => setDialogState(() => paymentReceiptBytes = null),
                    ),
                  ]
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: store.accentGold),
              onPressed: () async {
                if (txController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction ID is compulsory.'), backgroundColor: Colors.redAccent));
                  return;
                }
                // Capture the messenger before the async gap — using
                // context after `markPaid` may hit a disposed widget.
                final messenger = ScaffoldMessenger.of(context);
                final error = await store.markPaid(
                  expenseId,
                  txController.text.trim(),
                  receiptBytes: paymentReceiptBytes,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (error != null) {
                  messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
                } else {
                  messenger.showSnackBar(SnackBar(content: const Text('Expense marked as Paid!'), backgroundColor: _softAmber));
                }
              },
              child: const Text('Confirm Payment', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _handleApprove() {
    _confirmAction(
      title: 'Approve this expense?',
      message: 'This will mark the request as Approved. This action cannot be undone.',
      confirmLabel: 'Yes, Approve',
      confirmColor: Colors.green.shade700,
      onConfirmed: () async {
        // await the backend call — no success toast before the server
        // confirms (approve() rolls the optimistic status back on failure).
        final ok = await _store.approve(widget.expenseId);
        if (!mounted) return;
        if (ok) {
          _showResultSnack('Expense approved', Colors.greenAccent.shade400);
          Navigator.pop(context);
        } else {
          _showResultSnack('Could not approve the expense.', Colors.redAccent);
        }
      },
    );
  }

  void _handleReject() {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<String>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          return AlertDialog(
            backgroundColor: _store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _store.accentGold.withValues(alpha: 0.2))),
            title: Text('Reject this expense?', style: TextStyle(color: _store.textFrost, fontWeight: FontWeight.bold, fontSize: 17)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This will mark the request as Rejected. This action cannot be undone.', style: TextStyle(color: _store.textMuted, fontSize: 13)),
                  const SizedBox(height: 16),
                  Text('Reason for rejection', style: TextStyle(color: _store.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: reasonController,
                    maxLines: 3,
                    style: TextStyle(color: _store.textFrost, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Missing itemized receipt, amount exceeds policy limit...',
                      hintStyle: TextStyle(color: _store.textMuted.withValues(alpha: 0.5), fontSize: 12),
                      filled: true,
                      fillColor: _store.isDarkMode ? _store.bg : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _store.accentGold, width: 1.5)),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'A reason is required so the employee understands why' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: _store.textMuted))),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, reasonController.text.trim());
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Yes, Reject', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    ).then((reason) async {
      if (reason == null) return;
      // await the backend call — no success toast before the server confirms.
      final ok = await _store.reject(widget.expenseId, reason: reason);
      if (!mounted) return;
      if (ok) {
        _showResultSnack('Expense rejected', Colors.redAccent.shade400);
        Navigator.pop(context);
      } else {
        _showResultSnack('Could not reject the expense.', Colors.redAccent);
      }
    });
  }

  void _handleRequestInfo() {
    // Like reject, request-info needs the manager's actual question — a
    // bare confirm would produce a backend notification with empty help.
    final messageController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _store.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _store.accentGold.withValues(alpha: 0.2))),
        title: Text('Request more information?', style: TextStyle(color: _store.textFrost, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The employee will be notified with the message below.', style: TextStyle(color: _store.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                maxLines: 3,
                style: TextStyle(color: _store.textFrost, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Please attach the itemized receipt...',
                  hintStyle: TextStyle(color: _store.textMuted.withValues(alpha: 0.5), fontSize: 12),
                  filled: true,
                  fillColor: _store.isDarkMode ? _store.bg : Colors.grey.shade100,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _store.accentGold, width: 1.5)),
                ),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Tell the employee what is missing' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: _store.textMuted))),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, messageController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _store.accentGold, foregroundColor: _store.isDarkMode ? _store.bg : Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Send Request', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((message) async {
      if (message == null) return;
      final ok = await _store.requestMoreInfo(widget.expenseId, message: message);
      if (!mounted) return;
      if (ok) {
        _showResultSnack('Additional info requested from employee', _softAmber);
        Navigator.pop(context);
      } else {
        _showResultSnack('Could not send the info request.', Colors.redAccent);
      }
    });
  }

  void _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    Color confirmTextColor = Colors.white,
    required VoidCallback onConfirmed,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          return AlertDialog(
            backgroundColor: _store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: _store.accentGold.withValues(alpha: 0.2))),
            title: Text(title, style: TextStyle(color: _store.textFrost, fontWeight: FontWeight.bold, fontSize: 17)),
            content: Text(message, style: TextStyle(color: _store.textMuted, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: _store.textMuted))),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  onConfirmed();
                },
                style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: confirmTextColor, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showResultSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
      final comma = receipt.indexOf(',');
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
    final imageProvider = _receiptImageProvider(receipt);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
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
            Positioned(top: 20, right: 20, child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom; 
    final double extraBottomPadding = isMobile && bottomSafeArea > 0 ? bottomSafeArea + 16 : 0.0;

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final obsidianBlack = _store.bg;
        final darkCharcoal = _store.card;
        final champagneGold = _store.accentGold;
        final textFrost = _store.textFrost;
        final textMuted = _store.textMuted;
        
        final List<BoxShadow> cardShadows = _store.isDarkMode ? [] : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
        ];

        final employeeData = _store.byIdOrNull(widget.expenseId);
        if (employeeData == null) {
          // Stale row (deleted/refetched away) — render a friendly state
          // instead of red-screening (byId used to throw StateError here).
          return Scaffold(
            backgroundColor: obsidianBlack,
            appBar: AppBar(
              backgroundColor: darkCharcoal,
              foregroundColor: textFrost,
              elevation: 0,
              title: Text('Expense Details', style: TextStyle(fontWeight: FontWeight.bold, color: textFrost)),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, size: 48, color: textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'This expense record is no longer available.',
                    style: TextStyle(color: textMuted),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          );
        }
        final isLocked = _store.isLocked(widget.expenseId);
        final isFinance = _store.currentUserRole == 'finance';
        
        // --- IDENTITY LOCK IMPLEMENTATION ---
        final isOwnExpense = employeeData.email.trim().toLowerCase() == _store.currentUserEmail.trim().toLowerCase();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            elevation: 0,
            title: Text('Expense Details', style: TextStyle(fontWeight: FontWeight.bold, color: textFrost)),
            bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1)),
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 24.0 + extraBottomPadding),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: darkCharcoal, borderRadius: BorderRadius.circular(16), border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 28, backgroundColor: champagneGold.withValues(alpha: 0.1), child: Text(employeeData.name.isNotEmpty ? employeeData.name.substring(0, 1) : 'E', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: champagneGold))),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(employeeData.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textFrost)),
                                const SizedBox(height: 2),
                                Text(employeeData.email, style: TextStyle(color: textMuted, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text('Employee ID: ${employeeData.id}', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: champagneGold, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.greenAccent.shade700.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: const Text('Verified', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(height: 8),
                              Text('Submitted: ${employeeData.date}', style: TextStyle(color: textMuted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Receipt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                        boxShadow: cardShadows,
                      ),
                      child: Column(
                        children: [
                          if (employeeData.receiptBase64 != null && employeeData.receiptBase64!.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _showFullScreenImage(employeeData.receiptBase64!),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Container(color: _store.isDarkMode ? Colors.black45 : Colors.grey.shade200, child: Image(image: _receiptImageProvider(employeeData.receiptBase64!), height: 300, width: double.infinity, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: Text('Receipt file unavailable.', style: TextStyle(color: Colors.grey)))))),
                                  const Padding(padding: EdgeInsets.all(8.0), child: CircleAvatar(radius: 16, backgroundColor: Colors.black54, child: Icon(Icons.fullscreen, color: Colors.white, size: 20))),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Tap the image to view full screen.', textAlign: TextAlign.center, style: TextStyle(color: textMuted, fontSize: 12)),
                          ] else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('No receipt image attached.', style: TextStyle(color: textMuted, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Request Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: darkCharcoal, borderRadius: BorderRadius.circular(16), border: Border.all(color: _store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
                      child: Column(
                        children: [
                          if (employeeData.projectName != null && employeeData.projectName!.isNotEmpty)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _store.isDarkMode ? const Color(0xFF262633) : Colors.grey.shade200, width: 1))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Project Assigned', style: TextStyle(color: textMuted, fontSize: 14)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: champagneGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: champagneGold.withValues(alpha: 0.5))), child: Text(employeeData.projectName!, style: TextStyle(color: champagneGold, fontSize: 13, fontWeight: FontWeight.bold)))])),
                          _buildDetailRow('Expense Type', employeeData.type, true, textFrost, textMuted),
                          _buildDetailRow('Amount', employeeData.amountFormatted, true, textFrost, textMuted),
                          _buildDetailRow('Description', employeeData.description, true, textFrost, textMuted),
                          _buildDetailRow('Date', employeeData.date, employeeData.status == 'Rejected' && employeeData.rejectionReason != null || employeeData.processedBy != null, textFrost, textMuted),
                          if (employeeData.status == 'Rejected' && employeeData.rejectionReason != null) _buildDetailRow('Rejection Reason', employeeData.rejectionReason!, employeeData.processedBy != null, textFrost, textMuted),
                          if (employeeData.status == 'Info Requested' && employeeData.infoMessage != null)
                            _buildDetailRow('Manager asked', employeeData.infoMessage!, false, textFrost, textMuted),
                          if (employeeData.processedBy != null) _buildDetailRow('Processed By', employeeData.processedBy!, false, textFrost, textMuted),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (isFinance && employeeData.status == 'Approved') ...[
                      Text('Finance Action', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity, height: 54,
                        child: ElevatedButton.icon(
                          onPressed: () => _showMarkPaidDialog(context, widget.expenseId, _store),
                          icon: Icon(Icons.payments_rounded, size: 22, color: _store.isDarkMode ? obsidianBlack : Colors.white),
                          label: Text('Mark as Paid & Disburse', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _store.isDarkMode ? obsidianBlack : Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: champagneGold, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                      ),
                    ] else if (!isFinance) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Approval Action', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                          if (isLocked)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: (employeeData.status == 'Approved' || employeeData.status == 'Paid' ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Text('${employeeData.status == 'Approved' ? 'Approved • Payment Pending' : employeeData.status} • Locked', style: TextStyle(color: employeeData.status == 'Approved' || employeeData.status == 'Paid' ? Colors.greenAccent : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)))
                          else if (isOwnExpense) // --- IDENTITY LOCK STATUS ---
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: const Text('Self-Submitted • Locked', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // --- IDENTITY LOCK CONDITION ---
                      if (!isLocked && !isOwnExpense)
                        Row(
                          children: [
                            Expanded(child: SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _handleApprove, icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white), label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))))),
                            const SizedBox(width: 10),
                            Expanded(child: SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _handleReject, icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.white), label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))))),
                            const SizedBox(width: 10),
                            Expanded(child: SizedBox(height: 46, child: OutlinedButton.icon(onPressed: _handleRequestInfo, icon: Icon(Icons.info_rounded, size: 18, color: champagneGold), label: Text('Request Info', style: TextStyle(fontWeight: FontWeight.bold, color: champagneGold)), style: OutlinedButton.styleFrom(backgroundColor: darkCharcoal, side: BorderSide(color: champagneGold.withValues(alpha: 0.3)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))))),
                          ],
                        ),
                      
                      // --- IDENTITY LOCK FALLBACK UI ---
                      if (!isLocked && isOwnExpense)
                        Container(
                          width: double.infinity, 
                          padding: const EdgeInsets.symmetric(vertical: 16), 
                          decoration: BoxDecoration(color: Colors.orangeAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3))), 
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center, 
                            children: [
                              Icon(Icons.lock_person_rounded, color: Colors.orangeAccent), 
                              SizedBox(width: 8), 
                              Text('You cannot approve your own expenses.', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold))
                            ]
                          )
                        ),
                    ] else if (isFinance && employeeData.status == 'Paid') ...[
                      Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_rounded, color: Colors.greenAccent), SizedBox(width: 8), Text('Payment Disbursed Successfully', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))]))
                    ]
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, bool showBorder, Color textFrost, Color textMuted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(border: showBorder ? Border(bottom: BorderSide(color: _store.isDarkMode ? const Color(0xFF262633) : Colors.grey.shade200, width: 1)) : null),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: textMuted, fontSize: 14)), Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.bold)))]),
    );
  }
}
