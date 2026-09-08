import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/budget_reports_screen.dart';

class BudgetAllocationScreen extends StatefulWidget {
  const BudgetAllocationScreen({super.key});

  @override
  State<BudgetAllocationScreen> createState() => _BudgetAllocationScreenState();
}

class _BudgetAllocationScreenState extends State<BudgetAllocationScreen> {
  final store = ExpenseStore.instance;
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late DateTime _currentMonth;
  late DateTime _nextMonth;
  double? _currentMonthBudget;
  double? _nextMonthBudget;
  
  bool _loading = true;
  bool _saving = false;
  bool _isEditingCurrentMonth = true;

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final List<double> _quickSelectAmounts = [10000, 50000, 100000];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _nextMonth = DateTime(now.year, now.month + 1);
    _loadBudgets();
  }

  String _formatWithCommas(double amount) {
    return amount.toStringAsFixed(0).replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');
  }

  Future<void> _loadBudgets() async {
    setState(() => _loading = true);
    final current = await store.getBudgetForMonth(_currentMonth);
    final next = await store.getBudgetForMonth(_nextMonth);
    
    if (!mounted) return;
    
    setState(() {
      _currentMonthBudget = current;
      _nextMonthBudget = next;
      _loading = false;
      _updateTextFieldForSelectedMonth();
    });
  }
  
  void _updateTextFieldForSelectedMonth() {
    final targetBudget = _isEditingCurrentMonth ? _currentMonthBudget : _nextMonthBudget;
    _amountController.text = targetBudget != null ? _formatWithCommas(targetBudget) : '';
  }

  void _switchMonthToggle(bool toCurrent) {
    if (_isEditingCurrentMonth == toCurrent) return;
    setState(() {
      _isEditingCurrentMonth = toCurrent;
      _updateTextFieldForSelectedMonth();
    });
  }

  // --- UPDATED: Actually ADDS the amount and AUTO-SAVES instantly ---
  void _applyQuickSelect(double amountToAdd) {
    final currentText = _amountController.text.replaceAll(',', '').trim();
    double currentAmount = 0.0;
    
    if (currentText.isNotEmpty) {
      currentAmount = double.tryParse(currentText) ?? 0.0;
    }
    
    final newAmount = currentAmount + amountToAdd;
    
    setState(() {
      _amountController.text = _formatWithCommas(newAmount);
    });
    
    // Automatically trigger the save logic for seamless UX
    _handleSave();
  }

  bool get _isNearMonthEnd {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 2;
  }

  // --- UPDATED: Wrapped in a robust try/catch to prevent silent failures ---
  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    
    try {
      final cleanText = _amountController.text.replaceAll(',', '').trim();
      final amount = double.parse(cleanText);
      final targetMonth = _isEditingCurrentMonth ? _currentMonth : _nextMonth;
      
      final error = await store.setBudgetForMonth(targetMonth, amount);
      
      if (!mounted) return;
      setState(() => _saving = false);
      
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error, style: const TextStyle(fontWeight: FontWeight.w600)), backgroundColor: Colors.redAccent),
        );
        return;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: store.isDarkMode ? store.bg : Colors.white),
              const SizedBox(width: 12),
              Text('₹${_formatWithCommas(amount)} allocated for ${_monthNames[targetMonth.month - 1]}', 
                   style: TextStyle(fontWeight: FontWeight.bold, color: store.isDarkMode ? store.bg : Colors.white)),
            ],
          ),
          backgroundColor: store.accentGold,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      _loadBudgets();
      
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save budget: $e', style: const TextStyle(fontWeight: FontWeight.w600)), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetMonth = _isEditingCurrentMonth ? _currentMonth : _nextMonth;
    final selectedMonthName = _monthNames[targetMonth.month - 1];
    final selectedMonthYear = targetMonth.year.toString();
    final selectedBudget = _isEditingCurrentMonth ? _currentMonthBudget : _nextMonthBudget;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final double bottomSafeArea = MediaQuery.of(context).padding.bottom; 
    final double extraBottomPadding = isMobile && bottomSafeArea > 0 ? bottomSafeArea + 16 : 0.0;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;
        
        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[BoxShadow(color: champagneGold.withValues(alpha: 0.03), blurRadius: 24, offset: const Offset(0, 8))]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: obsidianBlack,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: textFrost),
            title: Text('Budget Allocation', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: darkCharcoal, height: 1), 
            ),
          ),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: champagneGold))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isNearMonthEnd && _nextMonthBudget == null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 24),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: champagneGold.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: champagneGold, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Pending Action: Set the ${_monthNames[_nextMonth.month - 1]} budget before month-end.",
                                        style: TextStyle(color: textFrost, fontSize: 13, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 45,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: darkCharcoal,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: _buildTab('${_monthNames[_currentMonth.month - 1]} (Current)', _isEditingCurrentMonth, () => _switchMonthToggle(true), champagneGold, textMuted),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 45,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: darkCharcoal,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: _buildTab('${_monthNames[_nextMonth.month - 1]} (Upcoming)', !_isEditingCurrentMonth, () => _switchMonthToggle(false), champagneGold, textMuted),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 10,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => const BudgetReportsScreen()),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: darkCharcoal,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.2),
                                        ),
                                        child: Tooltip(
                                          message: 'Reports',
                                          child: Icon(Icons.download_rounded, color: champagneGold, size: 20),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 32),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: darkCharcoal,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2), width: 1),
                                boxShadow: cardShadows,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Authorized Limit',
                                        style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: selectedBudget != null ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          selectedBudget != null ? 'ACTIVE' : 'PENDING',
                                          style: TextStyle(
                                            color: selectedBudget != null ? Colors.greenAccent : Colors.orangeAccent, 
                                            fontSize: 10, 
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    selectedBudget != null ? '₹${_formatWithCommas(selectedBudget)}' : 'Not Configured',
                                    style: TextStyle(
                                      color: selectedBudget != null ? textFrost : textMuted, 
                                      fontSize: 36, 
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Container(height: 1, color: store.isDarkMode ? obsidianBlack : Colors.grey.shade200),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_rounded, color: textMuted, size: 14),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Fiscal Period: $selectedMonthName $selectedMonthYear',
                                        style: TextStyle(color: textMuted, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 40),
                            
                            Text('Modify Allocation', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                            const SizedBox(height: 16),
                            
                            Form(
                              key: _formKey,
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [_CurrencyFormatter()],
                                style: TextStyle(color: textFrost, fontSize: 20, fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  prefixIcon: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Text('₹', style: TextStyle(color: textMuted, fontSize: 22, fontWeight: FontWeight.w400)),
                                  ),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                  hintText: '0',
                                  hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.3), fontSize: 20),
                                  filled: true,
                                  fillColor: darkCharcoal,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: store.isDarkMode ? obsidianBlack : Colors.grey.shade300, width: 2),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: champagneGold, width: 2),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.redAccent, width: 1),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return 'Allocation amount is required';
                                  final cleanValue = value.replaceAll(',', '').trim();
                                  final parsed = double.tryParse(cleanValue);
                                  if (parsed == null) return 'Invalid numerical format';
                                  if (parsed <= 0) return 'Allocation must exceed zero';
                                  return null;
                                },
                              ),
                            ),
                            
                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: _quickSelectAmounts.map((amount) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: amount == _quickSelectAmounts.last ? 0 : 8.0),
                                    child: InkWell(
                                      onTap: () => _applyQuickSelect(amount),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: darkCharcoal,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: store.isDarkMode ? darkCharcoal : Colors.grey.shade300),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '+${(amount / 1000).toStringAsFixed(0)}k',
                                          style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    Container(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + extraBottomPadding),
                      decoration: BoxDecoration(
                        color: darkCharcoal,
                        border: Border(top: BorderSide(color: store.isDarkMode ? obsidianBlack : Colors.grey.shade300, width: 2)),
                      ),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _handleSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: champagneGold,
                              foregroundColor: store.isDarkMode ? obsidianBlack : Colors.white,
                              disabledBackgroundColor: champagneGold.withValues(alpha: 0.3),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _saving
                                ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: store.isDarkMode ? obsidianBlack : Colors.white, strokeWidth: 2.5))
                                : const Text('Authorize Budget', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTab(String title, bool isSelected, VoidCallback onTap, Color champagneGold, Color textMuted) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent, 
          borderRadius: BorderRadius.circular(8),
          border: isSelected 
              ? Border.all(color: champagneGold, width: 1.2) 
              : Border.all(color: Colors.transparent, width: 1.2),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? champagneGold : textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CurrencyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    String cleanText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanText.isEmpty) return newValue;
    String formatted = cleanText.replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}