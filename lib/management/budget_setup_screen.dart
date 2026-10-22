import 'package:flutter/material.dart';

import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Creates a project budget and assigns people to it.
class BudgetSetupScreen extends StatefulWidget {
  const BudgetSetupScreen({super.key, this.initialEmployeeEmail});

  /// Pre-selects a person — the access-request queue sends the employee
  /// who asked for access straight into this form.
  final String? initialEmployeeEmail;

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final List<String> _selectedEmails = <String>[];
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final String? email = widget.initialEmployeeEmail;
    if (email != null && email.isNotEmpty) _selectedEmails.add(email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedEmails.isEmpty) {
      AppSnack.error(context, 'Select at least one employee.');
      return;
    }
    setState(() => _isSaving = true);
    final String? error = await ExpenseStore.instance.createProject(
      _nameController.text.trim(),
      double.tryParse(_budgetController.text.trim()) ?? 0,
      _selectedEmails.toList(),
    );
    // The screen can be popped while the request is in flight, so the
    // state update has to be guarded before it happens, not after.
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (error != null) {
      AppSnack.error(context, error);
      return;
    }
    Navigator.of(context).pop();
    AppSnack.success(context, 'Project created.');
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseStore store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        final List<Map<String, dynamic>> allEmployees = store.allEmployees;
        final String query = _searchQuery.trim().toLowerCase();
        final List<Map<String, dynamic>> filtered = allEmployees
            .where((Map<String, dynamic> employee) {
              if (query.isEmpty) return true;
              return (employee['name']?.toString() ?? '')
                      .toLowerCase()
                      .contains(query) ||
                  (employee['email']?.toString() ?? '').toLowerCase().contains(
                    query,
                  );
            })
            .toList(growable: false);

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('Create project budget')),
          body: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const AppFieldLabel('Project name'),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Project Alpha',
                          ),
                          validator: (String? value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        const AppFieldLabel('Allocated budget (₹)'),
                        TextFormField(
                          controller: _budgetController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(hintText: '0.00'),
                          validator: (String? value) {
                            final double? amount = double.tryParse(
                              (value ?? '').trim(),
                            );
                            if (amount == null || amount <= 0) {
                              return 'Must be greater than 0';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        const SectionHeader(title: 'Assign employees'),
                        const SizedBox(height: 10),
                        if (_selectedEmails.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedEmails
                                  .map((String email) {
                                    final String name =
                                        allEmployees.firstWhere(
                                              (Map<String, dynamic> e) =>
                                                  e['email'] == email,
                                              orElse: () => <String, dynamic>{
                                                'name': email,
                                              },
                                            )['name']
                                            as String;
                                    return InputChip(
                                      label: Text(name),
                                      onDeleted: () => setState(
                                        () => _selectedEmails.remove(email),
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          ),
                        AppSearchField(
                          hint: 'Search by name or email…',
                          onChanged: (String value) =>
                              setState(() => _searchQuery = value),
                        ),
                        const SizedBox(height: 12),
                        AppCard(
                          padding: EdgeInsets.zero,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: filtered.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Center(
                                      child: Text(
                                        'No employees match your search.',
                                        style: TextStyle(color: palette.muted),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: filtered.length,
                                    separatorBuilder:
                                        (BuildContext context, int index) =>
                                            Divider(
                                              height: 1,
                                              color: palette.border,
                                            ),
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                          final Map<String, dynamic> employee =
                                              filtered[index];
                                          final String email =
                                              employee['email']?.toString() ??
                                              '';
                                          final bool isSelected =
                                              _selectedEmails.contains(email);

                                          return CheckboxListTile(
                                            value: isSelected,
                                            activeColor: palette.gold,
                                            checkColor: palette.isDark
                                                ? AppTokens.darkBg
                                                : Colors.white,
                                            title: Text(
                                              employee['name']?.toString() ??
                                                  '',
                                              style: TextStyle(
                                                color: palette.text,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            subtitle: Text(
                                              email,
                                              style: TextStyle(
                                                color: palette.muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                            onChanged: (bool? value) {
                                              setState(() {
                                                if (value == true) {
                                                  _selectedEmails.add(email);
                                                } else {
                                                  _selectedEmails.remove(email);
                                                }
                                              });
                                            },
                                          );
                                        },
                                  ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: _isSaving ? null : _handleSave,
                            child: _isSaving
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: palette.isDark
                                          ? AppTokens.darkBg
                                          : Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Create project budget',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
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
