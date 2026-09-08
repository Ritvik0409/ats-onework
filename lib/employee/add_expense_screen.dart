import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- NEW: Required for strict keyboard locks
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ats_onework/employee/receipt_capture_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/employee/my_requests_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedExpenseType;
  DateTime _selectedDate = DateTime.now();
  Uint8List? _receiptBytes;
  bool _isSubmitting = false;

  final List<String> _expenseTypes = ['Travel', 'Meals', 'Supplies', 'Lodging', 'Software', 'Other'];
  String? _selectedProject;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      if (mounted) {
        _showPreviewDialog(bytes);
      }
    }
  }

  void _showPreviewDialog(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          final store = ExpenseStore.instance;
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), 
              side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))
            ),
            title: Center(child: Text('Receipt Preview', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold))),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceAround,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _pickFromGallery(); 
                },
                child: Text('Retake', style: TextStyle(color: store.textMuted)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  setState(() => _receiptBytes = bytes); 
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: store.accentGold,
                  foregroundColor: store.isDarkMode ? store.bg : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Use This Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _submitExpense() async {
    if (_formKey.currentState!.validate()) {
      if (_receiptBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a receipt before submitting.'), backgroundColor: Colors.redAccent));
        return;
      }
      
      setState(() => _isSubmitting = true);

      final store = ExpenseStore.instance;
      final dateStr = DateFormat('d MMM yyyy').format(_selectedDate);
      final error = await store.submitExpense(
        type: _selectedExpenseType ?? 'Other',
        amount: double.parse(_amountController.text),
        date: dateStr,
        description: _descriptionController.text.trim(),
        rawDate: _selectedDate,
        receiptBytes: _receiptBytes,
        projectName: _selectedProject,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Expense submitted successfully!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: store.accentGold));
          
          _descriptionController.clear();
          _amountController.clear();
          setState(() {
            _selectedExpenseType = null;
            _selectedProject = null;
            _receiptBytes = null;
            _selectedDate = DateTime.now();
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;
    final bool isManagement = store.currentUserRole != 'employee';
    final availableProjects = store.myProjects;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;
        final champagneGold = store.accentGold;
        
        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            elevation: 0,
            iconTheme: IconThemeData(color: textFrost),
            title: Text('Add New Expense', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
            actions: [
              if (isManagement)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, top: 8.0, bottom: 8.0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt_rounded, size: 16),
                    label: const Text('My Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: champagneGold,
                      side: BorderSide(color: champagneGold.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const MyRequestsScreen()));
                    },
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (availableProjects.isNotEmpty) ...[
                        Text('Tag to Project (Optional)', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProject,
                          dropdownColor: darkCharcoal,
                          style: TextStyle(color: textFrost),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: darkCharcoal,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                          ),
                          items: [
                            DropdownMenuItem<String>(value: null, child: Text('No Project (General Expense)', style: TextStyle(color: textMuted))),
                            ...availableProjects.map((p) => DropdownMenuItem<String>(value: p.name, child: Text(p.name))),
                          ],
                          onChanged: (value) => setState(() => _selectedProject = value),
                        ),
                        const SizedBox(height: 20),
                      ],

                      Text('Expense Type', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedExpenseType,
                        dropdownColor: darkCharcoal,
                        style: TextStyle(color: textFrost),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: darkCharcoal,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                        ),
                        items: _expenseTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                        onChanged: (value) => setState(() => _selectedExpenseType = value),
                        validator: (value) => value == null ? 'Please select a type' : null,
                      ),
                      const SizedBox(height: 20),

                      Text('Description', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        style: TextStyle(color: textFrost),
                        decoration: InputDecoration(
                          hintText: 'e.g. Client meeting travel expense',
                          hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 14),
                          filled: true,
                          fillColor: darkCharcoal,
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter a description' : null,
                      ),
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Amount (₹)', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _amountController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  // FIX: Strict regex lock added here to block letters
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                                  ],
                                  style: TextStyle(color: textFrost),
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5), fontSize: 14),
                                    filled: true,
                                    fillColor: darkCharcoal,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return 'Required';
                                    if (double.tryParse(value) == null) return 'Invalid';
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Date', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final DateTime? picked = await showDatePicker(
                                      context: context,
                                      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
                                      firstDate: DateTime(2000),
                                      lastDate: now,
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme: store.isDarkMode 
                                              ? ColorScheme.dark(primary: champagneGold, onPrimary: obsidianBlack, surface: darkCharcoal, onSurface: textFrost)
                                              : ColorScheme.light(primary: champagneGold, onPrimary: Colors.white, surface: darkCharcoal, onSurface: textFrost), dialogTheme: DialogThemeData(backgroundColor: darkCharcoal),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );
                                    if (picked != null && picked != _selectedDate) {
                                      setState(() => _selectedDate = picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: darkCharcoal,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(DateFormat('d MMM yyyy').format(_selectedDate), style: TextStyle(color: textFrost, fontSize: 14)),
                                        Icon(Icons.calendar_today_rounded, color: champagneGold, size: 18),
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

                      Text('Upload Receipt / Bill', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _receiptBytes != null ? Colors.greenAccent.withValues(alpha: 0.3) : (store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2))),
                          boxShadow: cardShadows,
                        ),
                        child: Column(
                          children: [
                            if (_receiptBytes != null) ...[
                              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 40),
                              const SizedBox(height: 12),
                              const Text('Receipt will be encoded and stored securely.', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => setState(() => _receiptBytes = null),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text('Remove'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ] else ...[
                              Icon(Icons.security_rounded, color: champagneGold, size: 32),
                              const SizedBox(height: 12),
                              Text('Receipt will be encoded and stored securely.', style: TextStyle(color: textMuted, fontSize: 13)),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final Uint8List? capturedImage = await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => const ReceiptCaptureScreen()),
                                        );
                                        if (capturedImage != null) {
                                          setState(() => _receiptBytes = capturedImage);
                                        }
                                      },
                                      icon: const Icon(Icons.camera_alt_rounded, size: 16),
                                      label: const Text('Scan with Camera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        foregroundColor: champagneGold,
                                        side: BorderSide(color: champagneGold.withValues(alpha: 0.3)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickFromGallery,
                                      icon: const Icon(Icons.photo_library_rounded, size: 16),
                                      label: const Text('Choose from Gallery', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        foregroundColor: champagneGold,
                                        side: BorderSide(color: champagneGold.withValues(alpha: 0.3)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitExpense,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: champagneGold,
                            foregroundColor: store.isDarkMode ? Colors.black : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isSubmitting
                              ? SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: store.isDarkMode ? Colors.black : Colors.white, strokeWidth: 2))
                              : const Text('Submit Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
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
}