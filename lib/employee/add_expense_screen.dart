import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/employee/receipt_capture_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _expenseType = 'Travel';
  DateTime _selectedDate = DateTime.now();
  String? _receiptFileName;
  bool _isSubmitting = false;

  static const List<String> _types = ['Travel', 'Meals', 'Medical', 'Equipment', 'Office Supplies', 'Other'];

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatDate(DateTime date) {
    return '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(), // per doc: cannot select future dates
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: champagneGold, onPrimary: obsidianBlack, surface: darkCharcoal),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _openCapture({required bool gallery}) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => ReceiptCaptureScreen(useGallery: gallery)),
    );
    if (result != null) setState(() => _receiptFileName = result);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return; // block duplicate/rapid taps
    if (!_formKey.currentState!.validate()) return;

    if (_receiptFileName == null) {
      _showSnack('Please attach a receipt before submitting.', Colors.redAccent);
      return;
    }

    setState(() => _isSubmitting = true);

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final displayDate = _formatDate(_selectedDate);

    final error = ExpenseStore.instance.submitExpense(
      type: _expenseType,
      amount: amount,
      date: displayDate,
      description: _descriptionController.text.trim(),
      rawDate: _selectedDate,
    );

    // Brief delay keeps the button visibly disabled and absorbs rapid re-taps.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    if (error != null) {
      setState(() => _isSubmitting = false);
      _showSnack(error, Colors.redAccent);
      return;
    }

    _showSnack('Expense submitted for review', Colors.greenAccent);
    setState(() {
      _isSubmitting = false;
      _amountController.clear();
      _descriptionController.clear();
      _receiptFileName = null;
      _expenseType = 'Travel';
      _selectedDate = DateTime.now();
    });
  }

  void _showSnack(String message, Color color) {
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
    return Scaffold(
      backgroundColor: obsidianBlack,
      appBar: AppBar(
        backgroundColor: darkCharcoal,
        elevation: 0,
        title: const Text('Add Expense', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Expense Type', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: champagneGold.withValues(alpha: 0.15)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _expenseType,
                        isExpanded: true,
                        dropdownColor: darkCharcoal,
                        style: const TextStyle(color: textFrost, fontSize: 14),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: champagneGold),
                        items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setState(() => _expenseType = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Description', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    style: const TextStyle(color: textFrost),
                    decoration: InputDecoration(
                      hintText: 'e.g. Client meeting travel expense',
                      hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 13),
                      filled: true,
                      fillColor: darkCharcoal,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: champagneGold, width: 1.5),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Amount (₹)', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              style: const TextStyle(color: textFrost),
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                                filled: true,
                                fillColor: darkCharcoal,
                                contentPadding: const EdgeInsets.all(14),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: champagneGold.withValues(alpha: 0.15)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: champagneGold, width: 1.5),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                final amt = double.tryParse(v.trim());
                                if (amt == null) return 'Invalid number';
                                if (amt <= 0) return 'Must be > 0';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Date', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _pickDate,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: darkCharcoal,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: champagneGold.withValues(alpha: 0.15)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDate(_selectedDate), style: const TextStyle(color: textFrost, fontSize: 14)),
                                    const Icon(Icons.calendar_today_rounded, color: champagneGold, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Upload Receipt / Bill', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _receiptFileName != null ? Colors.greenAccent.withValues(alpha: 0.4) : champagneGold.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _receiptFileName != null ? Icons.check_circle_rounded : Icons.shield_outlined,
                          color: _receiptFileName != null ? Colors.greenAccent : champagneGold,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _receiptFileName != null ? 'Receipt attached — will be encrypted before upload.' : 'Receipt will be encrypted and stored securely.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openCapture(gallery: false),
                                icon: const Icon(Icons.camera_alt_rounded, size: 16, color: champagneGold),
                                label: const Text('Scan with Camera', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: champagneGold.withValues(alpha: 0.4)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openCapture(gallery: true),
                                icon: const Icon(Icons.photo_library_rounded, size: 16, color: champagneGold),
                                label: const Text('Choose from Gallery', style: TextStyle(color: champagneGold, fontSize: 12, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: champagneGold.withValues(alpha: 0.4)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: champagneGold,
                        foregroundColor: obsidianBlack,
                        disabledBackgroundColor: champagneGold.withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: obsidianBlack),
                            )
                          : const Text('Submit Expense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}