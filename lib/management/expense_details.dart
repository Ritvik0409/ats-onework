import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class ExpenseDetailsScreen extends StatefulWidget {
  final String expenseId;

  const ExpenseDetailsScreen({super.key, required this.expenseId});

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  final ExpenseStore _store = ExpenseStore.instance;

  void _handleApprove() {
    _confirmAction(
      title: 'Approve this expense?',
      message: 'This will mark the request as Approved. This action cannot be undone.',
      confirmLabel: 'Yes, Approve',
      confirmColor: Colors.green.shade700,
      onConfirmed: () {
        _store.approve(widget.expenseId);
        _showResultSnack('Expense approved', Colors.greenAccent.shade400);
      },
    );
  }

  void _handleReject() {
    _confirmAction(
      title: 'Reject this expense?',
      message: 'This will mark the request as Rejected. This action cannot be undone.',
      confirmLabel: 'Yes, Reject',
      confirmColor: Colors.red.shade700,
      onConfirmed: () {
        _store.reject(widget.expenseId);
        _showResultSnack('Expense rejected', Colors.redAccent.shade400);
      },
    );
  }

  void _handleRequestInfo() {
    _confirmAction(
      title: 'Request more information?',
      message: 'The employee will be notified that additional details are needed for this expense.',
      confirmLabel: 'Yes, Request Info',
      confirmColor: champagneGold,
      confirmTextColor: obsidianBlack,
      onConfirmed: () {
        _store.requestMoreInfo(widget.expenseId);
        _showResultSnack('Additional info requested from employee', champagneGold);
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
        ),
        title: Text(title, style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(message, style: const TextStyle(color: textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onConfirmed();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: confirmTextColor,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final employeeData = _store.byId(widget.expenseId);
        final isLocked = _store.isLocked(widget.expenseId);

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            foregroundColor: textFrost,
            elevation: 0,
            title: const Text('Expense Management', style: TextStyle(fontWeight: FontWeight.bold)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: champagneGold.withValues(alpha: 0.1),
                            child: Text(
                              employeeData.name.substring(0, 1),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: champagneGold),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employeeData.name,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textFrost),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  employeeData.email,
                                  style: const TextStyle(color: textMuted, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Employee ID: ${employeeData.id}',
                                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: champagneGold, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.shade700.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Verified',
                                  style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Submitted: ${employeeData.date}',
                                style: const TextStyle(color: textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Receipt (Encrypted)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: employeeData.decrypted ? Colors.greenAccent.withValues(alpha: 0.3) : champagneGold.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            employeeData.decrypted ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                            size: 36,
                            color: employeeData.decrypted ? Colors.greenAccent : champagneGold,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            employeeData.decrypted
                                ? 'Receipt decrypted — visible to verified management only.'
                                : 'This receipt is encrypted for security.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _store.toggleDecrypt(widget.expenseId),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: obsidianBlack,
                              foregroundColor: employeeData.decrypted ? Colors.greenAccent : champagneGold,
                              side: BorderSide(color: employeeData.decrypted ? Colors.greenAccent : champagneGold, width: 1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: Text(
                              employeeData.decrypted ? 'Hide Receipt' : 'Decrypt & View',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Request Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('Expense Type', employeeData.type, true),
                          _buildDetailRow('Amount', employeeData.amountFormatted, true),
                          _buildDetailRow('Description', employeeData.description, true),
                          _buildDetailRow('Date', employeeData.date, false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Approval Action', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textFrost)),
                        if (isLocked)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (employeeData.status == 'Approved' ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${employeeData.status} • Locked',
                              style: TextStyle(
                                color: employeeData.status == 'Approved' ? Colors.greenAccent : Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: isLocked ? null : _handleApprove,
                              icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                              label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                disabledBackgroundColor: Colors.green.shade900,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: isLocked ? null : _handleReject,
                              icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.white),
                              label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                disabledBackgroundColor: Colors.red.shade900,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: isLocked ? null : _handleRequestInfo,
                              icon: Icon(Icons.info_rounded, size: 18, color: isLocked ? textMuted : champagneGold),
                              label: Text('Request Info', style: TextStyle(fontWeight: FontWeight.bold, color: isLocked ? textMuted : champagneGold)),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: darkCharcoal,
                                side: BorderSide(color: champagneGold.withValues(alpha: isLocked ? 0.1 : 0.3)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, bool showBorder) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: showBorder ? const Border(bottom: BorderSide(color: Color(0xFF262633), width: 1)) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFFF3F4F6), fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}