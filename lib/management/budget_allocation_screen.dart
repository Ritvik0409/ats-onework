import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatting.dart';
import '../management/budget_reports_screen.dart';
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Sets the monthly budget limit the organization may spend.
class BudgetAllocationScreen extends StatefulWidget {
  const BudgetAllocationScreen({super.key});

  @override
  State<BudgetAllocationScreen> createState() => _BudgetAllocationScreenState();
}

class _BudgetAllocationScreenState extends State<BudgetAllocationScreen> {
  final ExpenseStore store = ExpenseStore.instance;
  final TextEditingController _amountController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late DateTime _currentMonth;
  late DateTime _nextMonth;
  double? _currentMonthBudget;
  double? _nextMonthBudget;

  bool _loading = true;
  bool _saving = false;
  bool _isEditingCurrentMonth = true;

  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final List<double> _quickSelectAmounts = <double>[10000, 50000, 100000];

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _nextMonth = DateTime(now.year, now.month + 1);
    _loadBudgets();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadBudgets() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final double? current = await store.getBudgetForMonth(_currentMonth);
      final double? next = await store.getBudgetForMonth(_nextMonth);
      if (!mounted) return;
      setState(() {
        _currentMonthBudget = current;
        _nextMonthBudget = next;
        _loading = false;
        _updateTextFieldForSelectedMonth();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnack.error(context, 'Could not load the budgets from the backend.');
    }
  }

  void _updateTextFieldForSelectedMonth() {
    final double? target = _isEditingCurrentMonth
        ? _currentMonthBudget
        : _nextMonthBudget;
    // The field carries the number only — the currency symbol is the
    // field's prefix.
    _amountController.text = target == null
        ? ''
        : formatMoney(target).replaceAll('₹', '').trim();
  }

  void _switchMonthToggle(bool toCurrent) {
    if (_isEditingCurrentMonth == toCurrent) return;
    setState(() {
      _isEditingCurrentMonth = toCurrent;
      _updateTextFieldForSelectedMonth();
    });
  }

  /// The quick amounts only fill the field — nothing is saved until the
  /// allocation is authorised.
  void _applyQuickSelect(double amountToAdd) {
    final String currentText = _amountController.text
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .trim();
    final double currentAmount = double.tryParse(currentText) ?? 0;
    setState(() {
      _amountController.text = formatMoney(
        currentAmount + amountToAdd,
      ).replaceAll('₹', '').trim();
    });
  }

  bool get _isNearMonthEnd {
    final DateTime now = DateTime.now();
    final int lastDay = DateTime(now.year, now.month + 1, 0).day;
    return now.day >= lastDay - 2;
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      final String cleanText = _amountController.text
          .replaceAll(',', '')
          .replaceAll('₹', '')
          .trim();
      final double amount = double.parse(cleanText);
      final DateTime targetMonth = _isEditingCurrentMonth
          ? _currentMonth
          : _nextMonth;

      final String? error = await store.setBudgetForMonth(targetMonth, amount);

      if (!mounted) return;
      setState(() => _saving = false);

      if (error != null) {
        AppSnack.error(context, error);
        return;
      }

      AppSnack.success(
        context,
        '${formatMoney(amount)} allocated for '
        '${_monthNames[targetMonth.month - 1]}',
      );
      await _loadBudgets();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnack.error(context, 'Failed to save the budget.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime targetMonth = _isEditingCurrentMonth
        ? _currentMonth
        : _nextMonth;
    final String selectedMonthName = _monthNames[targetMonth.month - 1];
    final double? selectedBudget = _isEditingCurrentMonth
        ? _currentMonthBudget
        : _nextMonthBudget;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            title: const Text('Budget allocation'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Reports',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const BudgetReportsScreen(),
                  ),
                ),
                icon: const Icon(Icons.bar_chart_rounded),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: <Widget>[
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (_isNearMonthEnd && _nextMonthBudget == null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: AppCard(
                                      borderColor: palette.gold.withValues(
                                        alpha: 0.35,
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          Icon(
                                            Icons.info_outline_rounded,
                                            color: palette.gold,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Pending action: set the '
                                              '${_monthNames[_nextMonth.month - 1]} '
                                              'budget before month-end.',
                                              style: TextStyle(
                                                color: palette.text,
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                AppFilterBar(
                                  options: <String>[
                                    '${_monthNames[_currentMonth.month - 1]} '
                                        '(current)',
                                    '${_monthNames[_nextMonth.month - 1]} '
                                        '(upcoming)',
                                  ],
                                  value: _isEditingCurrentMonth
                                      ? '${_monthNames[_currentMonth.month - 1]} '
                                            '(current)'
                                      : '${_monthNames[_nextMonth.month - 1]} '
                                            '(upcoming)',
                                  onChanged: (String value) =>
                                      _switchMonthToggle(
                                        value.startsWith(
                                          _monthNames[_currentMonth.month - 1],
                                        ),
                                      ),
                                ),
                                const SizedBox(height: 18),

                                AppCard(
                                  padding: const EdgeInsets.all(22),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: <Widget>[
                                          Text(
                                            'Authorised limit',
                                            style: TextStyle(
                                              color: palette.muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                          AppTag(
                                            label: selectedBudget != null
                                                ? 'Active'
                                                : 'Pending',
                                            color: selectedBudget != null
                                                ? palette.success
                                                : palette.warning,
                                            dense: true,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        selectedBudget != null
                                            ? formatMoney(selectedBudget)
                                            : 'Not configured',
                                        style: TextStyle(
                                          color: selectedBudget != null
                                              ? palette.text
                                              : palette.muted,
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Divider(height: 1, color: palette.border),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: <Widget>[
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            color: palette.muted,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Fiscal period: '
                                            '$selectedMonthName '
                                            '${targetMonth.year}',
                                            style: TextStyle(
                                              color: palette.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 26),
                                const SectionHeader(title: 'Modify allocation'),
                                const SizedBox(height: 12),
                                Form(
                                  key: _formKey,
                                  child: TextFormField(
                                    controller: _amountController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.,]'),
                                      ),
                                    ],
                                    style: TextStyle(
                                      color: palette.text,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: const InputDecoration(
                                      prefixText: '₹ ',
                                      hintText: '0',
                                    ),
                                    validator: (String? value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Allocation amount is required';
                                      }
                                      final double? parsed = double.tryParse(
                                        value
                                            .replaceAll(',', '')
                                            .replaceAll('₹', '')
                                            .trim(),
                                      );
                                      if (parsed == null) {
                                        return 'Invalid numerical format';
                                      }
                                      if (parsed <= 0) {
                                        return 'Allocation must exceed zero';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 14),
                                AppGrid(
                                  minItemWidth: 110,
                                  children: _quickSelectAmounts
                                      .map(
                                        (double amount) => ActionTile(
                                          icon: Icons.add_rounded,
                                          label:
                                              '+${(amount / 1000).toStringAsFixed(0)}k',
                                          accent: palette.info,
                                          onTap: () =>
                                              _applyQuickSelect(amount),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _saving ? null : _handleSave,
                          child: _saving
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: palette.isDark
                                        ? AppTokens.darkBg
                                        : Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Authorise budget',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
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
}
