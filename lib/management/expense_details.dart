import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class ExpenseDetailsScreen extends StatefulWidget {
  final String expenseId;

  const ExpenseDetailsScreen({super.key, required this.expenseId});

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  final ExpenseStore _store = ExpenseStore.instance;

  // --- FIX: Restored synchronous calls to ExpenseStore to fix UI state freezing ---
  void _handleApprove() {
    _confirmAction(
      title: 'Approve this expense?',
      message: 'This will mark the request as Approved. This action cannot be undone.',
      confirmLabel: 'Yes, Approve',
      confirmColor: Colors.green.shade700,
      onConfirmed: () {
        try {
          _store.approve(widget.expenseId);
          _showResultSnack('Expense approved', Colors.greenAccent.shade400);
          if (mounted) Navigator.pop(context);
        } catch (e) {
          _showResultSnack('Error: $e', Colors.redAccent);
        }
      },
    );
  }

  void _handleReject() {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
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
                    Navigator.pop(dialogContext);
                    try {
                      _store.reject(widget.expenseId, reason: reasonController.text.trim());
                      _showResultSnack('Expense rejected', Colors.redAccent.shade400);
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      _showResultSnack('Error: $e', Colors.redAccent);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Yes, Reject', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleRequestInfo() {
    _confirmAction(
      title: 'Request more information?',
      message: 'The employee will be notified that additional details are needed for this expense.',
      confirmLabel: 'Yes, Request Info',
      confirmColor: _store.accentGold,
      confirmTextColor: _store.isDarkMode ? _store.bg : Colors.white,
      onConfirmed: () {
        try {
          _store.requestMoreInfo(widget.expenseId);
          _showResultSnack('Additional info requested from employee', _store.accentGold);
          if (mounted) Navigator.pop(context);
        } catch (e) {
          _showResultSnack('Error: $e', Colors.redAccent);
        }
      },
    );
  }

  void _handleMarkPaid() {
    _confirmAction(
      title: 'Process Payout?',
      message: 'This will mark the expense as Paid and notify the employee. Only proceed if funds have been disbursed.',
      confirmLabel: 'Confirm Payout',
      confirmColor: _store.accentGold,
      confirmTextColor: _store.isDarkMode ? _store.bg : Colors.white,
      onConfirmed: () {
        try {
          _store.markPaid(widget.expenseId);
          _showResultSnack('Payout Processed Successfully!', Colors.greenAccent);
          if (mounted) Navigator.pop(context);
        } catch (e) {
          _showResultSnack('Error processing payout: $e', Colors.redAccent);
        }
      },
    );
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

  void _showFullScreenImage(String base64Image) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(minScale: 1.0, maxScale: 4.0, child: Image.memory(base64Decode(base64Image), fit: BoxFit.contain)),
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

        final employeeData = _store.byId(widget.expenseId);
        final isLocked = _store.isLocked(widget.expenseId);
        final isFinance = _store.currentUserRole == 'finance';

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
                    Text('Receipt (Encrypted & Interactive Viewer)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: employeeData.decrypted ? Colors.greenAccent.withValues(alpha: 0.3) : (_store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2))),
                        boxShadow: cardShadows,
                      ),
                      child: Column(
                        children: [
                          Icon(employeeData.decrypted ? Icons.lock_open_rounded : Icons.lock_outline_rounded, size: 36, color: employeeData.decrypted ? Colors.greenAccent : champagneGold),
                          const SizedBox(height: 12),
                          Text(employeeData.decrypted ? 'Receipt decrypted — tap image to view full screen.' : 'This receipt is encrypted for security.', textAlign: TextAlign.center, style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w500)),
                          if (employeeData.decrypted) ...[
                            const SizedBox(height: 16),
                            if (employeeData.receiptBase64 != null && employeeData.receiptBase64!.isNotEmpty)
                              GestureDetector(
                                onTap: () => _showFullScreenImage(employeeData.receiptBase64!),
                                child: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Container(color: _store.isDarkMode ? Colors.black45 : Colors.grey.shade200, child: Image.memory(base64Decode(employeeData.receiptBase64!), height: 300, width: double.infinity, fit: BoxFit.contain))),
                                    const Padding(padding: EdgeInsets.all(8.0), child: CircleAvatar(radius: 16, backgroundColor: Colors.black54, child: Icon(Icons.fullscreen, color: Colors.white, size: 20))),
                                  ],
                                ),
                              )
                            else Text('No receipt image attached.', style: TextStyle(color: textMuted, fontSize: 12)),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _store.toggleDecrypt(widget.expenseId),
                            style: ElevatedButton.styleFrom(backgroundColor: obsidianBlack, foregroundColor: employeeData.decrypted ? Colors.greenAccent : champagneGold, side: BorderSide(color: employeeData.decrypted ? Colors.greenAccent : champagneGold, width: 1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                            child: Text(employeeData.decrypted ? 'Hide Receipt' : 'Decrypt & View', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                          onPressed: _handleMarkPaid,
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
                            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: (employeeData.status == 'Approved' || employeeData.status == 'Paid' ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Text('${employeeData.status} • Locked', style: TextStyle(color: employeeData.status == 'Approved' || employeeData.status == 'Paid' ? Colors.greenAccent : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!isLocked)
                        Row(
                          children: [
                            Expanded(child: SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _handleApprove, icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white), label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))))),
                            const SizedBox(width: 10),
                            Expanded(child: SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _handleReject, icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.white), label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))))),
                            const SizedBox(width: 10),
                            Expanded(child: SizedBox(height: 46, child: OutlinedButton.icon(onPressed: _handleRequestInfo, icon: Icon(Icons.info_rounded, size: 18, color: champagneGold), label: Text('Request Info', style: TextStyle(fontWeight: FontWeight.bold, color: champagneGold)), style: OutlinedButton.styleFrom(backgroundColor: darkCharcoal, side: BorderSide(color: champagneGold.withValues(alpha: 0.3)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))))),
                          ],
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