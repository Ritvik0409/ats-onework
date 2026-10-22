import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/formatting.dart';
import '../management/expense_store.dart';
import '../shared/app_snack.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';
import 'receipt_capture_screen.dart';

/// The submission form: type, project, amount, date and the receipt.
///
/// The fields rely on the app theme for their styling — the old screen
/// repeated the same five border definitions on every input.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  String? _selectedExpenseType;
  String? _selectedProject;
  DateTime _selectedDate = DateTime.now();
  Uint8List? _receiptBytes;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (image == null) return;
    final Uint8List bytes = await image.readAsBytes();
    if (!mounted) return;
    await _showPreviewDialog(bytes);
  }

  Future<void> _showPreviewDialog(Uint8List bytes) async {
    final bool? use = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Receipt preview'),
        // A fixed 420×320 box overflowed narrow phones; the AlertDialog
        // already caps its own width, so only constrain the preview and
        // let the aspect ratio scale it.
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Pick another'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use this receipt'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (use == true) {
      setState(() => _receiptBytes = bytes);
    } else if (use == false) {
      // "Pick another" — go straight back to the gallery.
      await _pickFromGallery();
    }
  }

  Future<void> _captureWithCamera() async {
    final Uint8List? captured = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        builder: (BuildContext context) => const ReceiptCaptureScreen(),
      ),
    );
    if (captured != null && mounted) {
      setState(() => _receiptBytes = captured);
    }
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submitExpense() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_receiptBytes == null) {
      AppSnack.error(context, 'Please attach a receipt before submitting.');
      return;
    }

    setState(() => _isSubmitting = true);

    final ExpenseStore store = ExpenseStore.instance;
    final String? error = await store.submitExpense(
      type: _selectedExpenseType ?? 'Other',
      amount: double.parse(_amountController.text),
      date: formatDate(_selectedDate),
      description: _descriptionController.text.trim(),
      rawDate: _selectedDate,
      receiptBytes: _receiptBytes,
      projectId: _selectedProject,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error != null) {
      AppSnack.error(context, error);
      return;
    }

    AppSnack.success(context, 'Expense submitted for approval.');
    _descriptionController.clear();
    _amountController.clear();
    setState(() {
      _selectedExpenseType = null;
      _selectedProject = null;
      _receiptBytes = null;
      _selectedDate = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ExpenseStore store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? _) {
        final AppPalette palette = context.palette;
        // Read inside the builder: captured outside, the list never
        // refreshed when the store did.
        final List<ProjectRecord> availableProjects = store.myProjects;

        return Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(title: const Text('Add expense')),
          body: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (!store.projectsLoaded) ...<Widget>[
                          const AppFieldLabel('Project (optional)'),
                          // While the project list is still on its way
                          // the field stays visible but disabled —
                          // hiding it made the form jump when it
                          // appeared.
                          DropdownButtonFormField<String>(
                            dropdownColor: palette.surfaceAlt,
                            isExpanded: true,
                            items: const <DropdownMenuItem<String>>[],
                            onChanged: null,
                            disabledHint: const Text('Loading projects…'),
                          ),
                          const SizedBox(height: 18),
                        ] else if (availableProjects.isNotEmpty) ...<Widget>[
                          const AppFieldLabel('Project (optional)'),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedProject,
                            dropdownColor: palette.surfaceAlt,
                            isExpanded: true,
                            items: <DropdownMenuItem<String>>[
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('No project — general expense'),
                              ),
                              // Keyed by backend id: display names are not
                              // unique across budgets, and a duplicated
                              // value crashes the DropdownButton assertion.
                              ...availableProjects.map(
                                (ProjectRecord project) =>
                                    DropdownMenuItem<String>(
                                      value: project.id,
                                      child: Text(project.name),
                                    ),
                              ),
                            ],
                            onChanged: (String? value) =>
                                setState(() => _selectedProject = value),
                          ),
                          const SizedBox(height: 18),
                        ],

                        const AppFieldLabel('Expense type'),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedExpenseType,
                          dropdownColor: palette.surfaceAlt,
                          isExpanded: true,
                          items: store.availableExpenseTypes
                              .map(
                                (String type) => DropdownMenuItem<String>(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (String? value) =>
                              setState(() => _selectedExpenseType = value),
                          validator: (String? value) =>
                              value == null ? 'Please select a type' : null,
                        ),
                        const SizedBox(height: 18),

                        const AppFieldLabel('Description'),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 3,
                          // Multiline: Enter inserts a line break instead
                          // of submitting the form.
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Client meeting travel expense',
                          ),
                          validator: (String? value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Please enter a description'
                              : null,
                        ),
                        const SizedBox(height: 18),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const AppFieldLabel('Amount (₹)'),
                                  TextFormField(
                                    controller: _amountController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textInputAction: TextInputAction.done,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d*'),
                                      ),
                                    ],
                                    decoration: const InputDecoration(
                                      hintText: '0.00',
                                    ),
                                    validator: (String? value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Required';
                                      }
                                      final double? amount = double.tryParse(
                                        value,
                                      );
                                      if (amount == null) return 'Invalid';
                                      if (amount <= 0) {
                                        return 'Must be more than zero';
                                      }
                                      return null;
                                    },
                                    // Enter on the amount submits — this
                                    // is the last editable field of the
                                    // form.
                                    onFieldSubmitted: (String _) {
                                      if (!_isSubmitting) _submitExpense();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const AppFieldLabel('Date'),
                                  InkWell(
                                    onTap: _pickDate,
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.radiusMd,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: palette.surfaceAlt,
                                        borderRadius: BorderRadius.circular(
                                          AppTokens.radiusMd,
                                        ),
                                        border: Border.all(
                                          color: palette.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: <Widget>[
                                          Text(
                                            formatDate(_selectedDate),
                                            style: TextStyle(
                                              color: palette.text,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            color: palette.gold,
                                            size: 17,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),

                        const SectionHeader(
                          title: 'Receipt',
                          subtitle: 'A receipt is required to submit',
                        ),
                        _receiptCard(palette),
                        const SizedBox(height: 26),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _isSubmitting ? null : _submitExpense,
                            child: _isSubmitting
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    // Dark ink in dark mode — plain white
                                    // washes out on the gold button there.
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: palette.isDark
                                          ? AppTokens.darkBg
                                          : Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Submit expense',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
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

  Widget _receiptCard(AppPalette palette) {
    if (_receiptBytes != null) {
      return AppCard(
        borderColor: palette.success.withValues(alpha: 0.35),
        child: Column(
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: palette.success, size: 36),
            const SizedBox(height: 10),
            Text(
              'Receipt attached',
              style: TextStyle(
                color: palette.success,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => setState(() => _receiptBytes = null),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Remove'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.danger,
                side: BorderSide(color: palette.danger.withValues(alpha: 0.45)),
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        children: <Widget>[
          Icon(Icons.receipt_long_rounded, color: palette.gold, size: 30),
          const SizedBox(height: 10),
          Text(
            'Scan or choose the bill for this expense.',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _captureWithCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text(
                    'Scan',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 16),
                  label: const Text(
                    'Gallery',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
