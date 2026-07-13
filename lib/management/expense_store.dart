import 'package:flutter/foundation.dart';

/// A single expense claim record.
class ExpenseRecord {
  final String id; // e.g. EMP-2026-118
  final String name;
  final String email;
  final String type; // Travel, Meals, Medical, Equipment...
  final double amount;
  final String date; // display date, e.g. 20 May 2024
  final String description;
  String status; // 'Pending Verification', 'Approved', 'Rejected'
  bool decrypted; // whether manager has decrypted the receipt in this session

  ExpenseRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.type,
    required this.amount,
    required this.date,
    required this.description,
    this.status = 'Pending Verification',
    this.decrypted = false,
  });

  String get amountFormatted => '₹${amount.toStringAsFixed(2)}';
}

/// A single notification feed item.
class AppNotification {
  final String expenseId;
  final String title; // "Rahul Sharma (E00123)"
  final String subtitle;
  final String time;
  final String type; // 'approved' | 'rejected' | 'info'

  AppNotification({
    required this.expenseId,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.type,
  });
}

/// Central in-memory store shared across the Management portal AND Employee portal.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore._internal() {
    _seed();
  }

  static final ExpenseStore instance = ExpenseStore._internal();

  final List<ExpenseRecord> expenses = [];
  final List<AppNotification> notifications = [];

  String currentManagerEmail = 'manager@company.com';
  String currentManagerName = 'Manager';

  String currentEmployeeEmail = 'employee@company.com';
  String currentEmployeeName = 'Employee';
  String currentEmployeeId = 'E00128';

  int _trackingSeq = 200;

  void setCurrentManager({required String email}) {
    currentManagerEmail = email;
    currentManagerName = _deriveName(email, fallback: 'Manager');
    notifyListeners();
  }

  void setCurrentEmployee({required String email}) {
    currentEmployeeEmail = email;
    currentEmployeeName = _deriveName(email, fallback: 'Employee');
    notifyListeners();
  }

  String _deriveName(String email, {required String fallback}) {
    final localPart = email.split('@').first;
    final parts = localPart.split(RegExp(r'[._]+')).where((p) => p.isNotEmpty);
    final name = parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
    return name.trim().isEmpty ? fallback : name;
  }

  /// Generates a unique tracking ID, per the design doc requirement.
  String _generateTrackingId() {
    _trackingSeq += 1;
    return 'EMP-2026-${_trackingSeq.toString().padLeft(3, '0')}';
  }

  /// Employee submits a new expense claim. Returns a validation error message, or null on success.
  String? submitExpense({
    required String type,
    required double amount,
    required String date, // display format e.g. '20 May 2024'
    required String description,
    required DateTime rawDate,
  }) {
    if (type.trim().isEmpty) return 'Please select an expense type.';
    if (description.trim().isEmpty) return 'Please enter a description.';
    if (amount <= 0) return 'Amount must be a positive, non-zero value.';
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(rawDate.year, rawDate.month, rawDate.day);
    if (dateOnly.isAfter(todayOnly)) return 'Date cannot be in the future.';

    expenses.insert(
      0,
      ExpenseRecord(
        id: _generateTrackingId(),
        name: currentEmployeeName,
        email: currentEmployeeEmail,
        type: type,
        amount: amount,
        date: date,
        description: description,
        status: 'Pending Verification',
      ),
    );
    notifyListeners();
    return null;
  }

  List<ExpenseRecord> get myExpenses =>
      expenses.where((e) => e.email == currentEmployeeEmail).toList();

  int get myPendingCount => myExpenses.where((e) => e.status == 'Pending Verification').length;
  int get myApprovedCount => myExpenses.where((e) => e.status == 'Approved').length;
  int get myRejectedCount => myExpenses.where((e) => e.status == 'Rejected').length;
  int get myTotalUploads => myExpenses.length;

  void _seed() {
    expenses.addAll([
      ExpenseRecord(
        id: 'EMP-2026-118',
        name: 'Aman Singh',
        email: 'aman@company.com',
        type: 'Travel',
        amount: 2450.00,
        date: '20 May 2024',
        description: 'Client meeting travel expense',
        status: 'Pending Verification',
      ),
      ExpenseRecord(
        id: 'EMP-2026-122',
        name: 'Priya Patel',
        email: 'priya@company.com',
        type: 'Medical',
        amount: 12400.00,
        date: '18 May 2024',
        description: 'Medical reimbursement claim',
        status: 'Approved',
      ),
      ExpenseRecord(
        id: 'EMP-2026-095',
        name: 'Amit Kumar',
        email: 'amit.k@company.com',
        type: 'Meals',
        amount: 1200.00,
        date: '19 May 2024',
        description: 'Team lunch expense',
        status: 'Rejected',
      ),
      ExpenseRecord(
        id: 'EMP-2026-044',
        name: 'Sneha Iyer',
        email: 'sneha@company.com',
        type: 'Equipment',
        amount: 3150.00,
        date: '15 May 2024',
        description: 'Office equipment purchase',
        status: 'Pending Verification',
      ),
      // Seeded record for the default employee, so "My Requests" isn't empty on first run.
      ExpenseRecord(
        id: 'EMP-2026-201',
        name: 'Employee',
        email: 'employee@company.com',
        type: 'Travel',
        amount: 950.00,
        date: '20 May 2024',
        description: 'Delhi trip taxi receipt',
        status: 'Pending Verification',
      ),
      ExpenseRecord(
        id: 'EMP-2026-202',
        name: 'Employee',
        email: 'employee@company.com',
        type: 'Medical',
        amount: 12400.00,
        date: '18 May 2024',
        description: 'Apollo hospital bill',
        status: 'Approved',
      ),
      ExpenseRecord(
        id: 'EMP-2026-203',
        name: 'Employee',
        email: 'employee@company.com',
        type: 'Equipment',
        amount: 3150.00,
        date: '15 May 2024',
        description: 'Office supplies',
        status: 'Rejected',
      ),
    ]);

    notifications.addAll([
      AppNotification(
        expenseId: 'EMP-2026-118',
        title: 'Rahul Sharma (E00123)',
        subtitle: 'Expense request of ₹2,450.00 has been approved.',
        time: 'Today, 10:30 AM',
        type: 'approved',
      ),
      AppNotification(
        expenseId: 'EMP-2026-095',
        title: 'Amit Kumar (E00125)',
        subtitle: 'Expense request of ₹1,200.00 has been rejected.',
        time: 'Today, 09:15 AM',
        type: 'rejected',
      ),
      AppNotification(
        expenseId: 'EMP-2026-044',
        title: 'Sneha Iyer (E00126)',
        subtitle: 'Additional information requested for expense of ₹3,150.00.',
        time: 'Yesterday, 05:40 PM',
        type: 'info',
      ),
      AppNotification(
        expenseId: 'EMP-2026-122',
        title: 'Vikram Singh (E00127)',
        subtitle: 'Expense request of ₹980.00 has been approved.',
        time: 'Yesterday, 03:20 PM',
        type: 'approved',
      ),
    ]);
  }

  ExpenseRecord byId(String id) => expenses.firstWhere((e) => e.id == id);

  bool isLocked(String id) {
    final status = byId(id).status;
    return status == 'Approved' || status == 'Rejected';
  }

  void approve(String id) {
    final expense = byId(id);
    if (isLocked(id)) return;
    expense.status = 'Approved';
    notifications.insert(
      0,
      AppNotification(
        expenseId: id,
        title: '${expense.name} (${expense.id})',
        subtitle: 'Expense request of ${expense.amountFormatted} has been approved.',
        time: 'Just now',
        type: 'approved',
      ),
    );
    notifyListeners();
  }

  void reject(String id) {
    final expense = byId(id);
    if (isLocked(id)) return;
    expense.status = 'Rejected';
    notifications.insert(
      0,
      AppNotification(
        expenseId: id,
        title: '${expense.name} (${expense.id})',
        subtitle: 'Expense request of ${expense.amountFormatted} has been rejected.',
        time: 'Just now',
        type: 'rejected',
      ),
    );
    notifyListeners();
  }

  void requestMoreInfo(String id) {
    final expense = byId(id);
    if (isLocked(id)) return;
    notifications.insert(
      0,
      AppNotification(
        expenseId: id,
        title: '${expense.name} (${expense.id})',
        subtitle: 'Additional information requested for expense of ${expense.amountFormatted}.',
        time: 'Just now',
        type: 'info',
      ),
    );
    notifyListeners();
  }

  void toggleDecrypt(String id) {
    final expense = byId(id);
    expense.decrypted = !expense.decrypted;
    notifyListeners();
  }

  int get pendingCount => expenses.where((e) => e.status == 'Pending Verification').length;
  int get approvedCount => expenses.where((e) => e.status == 'Approved').length;
  int get rejectedCount => expenses.where((e) => e.status == 'Rejected').length;
}