import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class BudgetSetupScreen extends StatefulWidget {
  // --- NEW: Accept the employee's email from the previous screen ---
  final String? initialEmployeeEmail;
  const BudgetSetupScreen({super.key, this.initialEmployeeEmail});

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController();
  final Set<String> _selectedEmails = {};
  
  String _searchQuery = ''; 
  bool _isSaving = false;

  // --- NEW: Automatically select the employee if their email was passed ---
  @override
  void initState() {
    super.initState();
    if (widget.initialEmployeeEmail != null) {
      _selectedEmails.add(widget.initialEmployeeEmail!);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one employee.'), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isSaving = true);
    final store = ExpenseStore.instance;

    await store.createProject(
      _nameController.text.trim(),
      double.tryParse(_budgetController.text.trim()) ?? 0,
      _selectedEmails.toList(),
    );

    setState(() => _isSaving = false);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project Budget Created!'), backgroundColor: Colors.greenAccent));
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final obsidianBlack = store.bg;
        final darkCharcoal = store.card;
        final champagneGold = store.accentGold;
        final textFrost = store.textFrost;
        final textMuted = store.textMuted;

        final List<BoxShadow> cardShadows = store.isDarkMode
            ? <BoxShadow>[]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, -1)),
              ];

        final allEmployees = store.allEmployees;
        final filteredEmployees = allEmployees.where((emp) {
          final q = _searchQuery.toLowerCase();
          return emp['name']!.toLowerCase().contains(q) || emp['email']!.toLowerCase().contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: obsidianBlack,
          appBar: AppBar(
            backgroundColor: darkCharcoal,
            title: Text('Create Project Budget', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
            iconTheme: IconThemeData(color: textFrost),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: champagneGold.withValues(alpha: 0.15), height: 1),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Project Name', style: TextStyle(color: textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: textFrost),
                        decoration: InputDecoration(
                          filled: true, fillColor: darkCharcoal,
                          hintText: 'e.g. Project Alpha', 
                          hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      Text('Allocated Budget (₹)', style: TextStyle(color: textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _budgetController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: textFrost),
                        decoration: InputDecoration(
                          filled: true, fillColor: darkCharcoal,
                          hintText: '0.00',
                          hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                        ),
                        validator: (v) {
                          final amt = double.tryParse(v ?? '');
                          if (amt == null || amt <= 0) return 'Must be greater than 0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                      
                      Text('Assign Employees', style: TextStyle(color: textFrost, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      if (_selectedEmails.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedEmails.map((email) {
                              final empName = allEmployees.firstWhere((e) => e['email'] == email, orElse: () => {'name': email})['name']!;
                              return Chip(
                                label: Text(empName, style: TextStyle(color: store.isDarkMode ? obsidianBlack : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                backgroundColor: champagneGold,
                                deleteIcon: Icon(Icons.close_rounded, size: 16, color: store.isDarkMode ? obsidianBlack : Colors.white),
                                onDeleted: () {
                                  setState(() => _selectedEmails.remove(email));
                                },
                              );
                            }).toList(),
                          ),
                        ),

                      TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: TextStyle(color: textFrost, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search by name or email...',
                          hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.5)),
                          prefixIcon: Icon(Icons.search_rounded, color: champagneGold, size: 20),
                          filled: true,
                          fillColor: darkCharcoal,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.isDarkMode ? Colors.transparent : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: champagneGold, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Container(
                        decoration: BoxDecoration(
                          color: darkCharcoal,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.3)),
                          boxShadow: cardShadows,
                        ),
                        constraints: const BoxConstraints(maxHeight: 300), 
                        child: filteredEmployees.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Center(child: Text('No employees match your search.', style: TextStyle(color: textMuted))),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredEmployees.length,
                                separatorBuilder: (_, _) => Divider(color: store.isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200, height: 1),
                                itemBuilder: (context, index) {
                                  final emp = filteredEmployees[index];
                                  final email = emp['email']!;
                                  final isSelected = _selectedEmails.contains(email);

                                  return CheckboxListTile(
                                    value: isSelected,
                                    activeColor: champagneGold,
                                    checkColor: store.isDarkMode ? obsidianBlack : Colors.white,
                                    title: Text(emp['name']!, style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
                                    subtitle: Text(email, style: TextStyle(color: textMuted, fontSize: 12)),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
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
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: champagneGold, 
                            foregroundColor: store.isDarkMode ? obsidianBlack : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _isSaving
                              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: store.isDarkMode ? obsidianBlack : Colors.white))
                              : const Text('Create Project Budget', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    );
  }
}