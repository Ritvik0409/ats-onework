import 'dart:async'; 
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProjectRecord {
  final String id;
  final String name;
  final double budget;
  final List<String> assignedEmails;
  final bool isActive;

  ProjectRecord({
    required this.id,
    required this.name,
    required this.budget,
    required this.assignedEmails,
    required this.isActive,
  });

  factory ProjectRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ProjectRecord(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Project',
      budget: (data['budget'] ?? 0.0).toDouble(),
      assignedEmails: List<String>.from(data['assignedEmails'] ?? []),
      isActive: data['isActive'] ?? true,
    );
  }
}

class ExpenseRecord {
  final String firestoreDocId;
  final String id; 
  final String name;
  final String email;
  final String type; 
  final double amount;
  final String date; 
  final String description;
  String status; 
  bool decrypted; 
  String? rejectionReason; 
  final String? receiptBase64;
  String? processedBy; 
  final String? projectName; 
  final String uploaderRole; 

  ExpenseRecord({
    this.firestoreDocId = '',
    required this.id,
    required this.name,
    required this.email,
    required this.type,
    required this.amount,
    required this.date,
    required this.description,
    this.status = 'Pending Verification',
    this.decrypted = false,
    this.rejectionReason,
    this.receiptBase64,
    this.processedBy,
    this.projectName,
    this.uploaderRole = 'employee', 
  });

  String get amountFormatted => '₹${amount.toStringAsFixed(2)}';

  factory ExpenseRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ExpenseRecord(
      firestoreDocId: doc.id,
      id: data['employeeId'] ?? 'EMP-UNKNOWN',
      name: data['employeeName'] ?? 'Unknown Employee',
      email: data['email'] ?? 'employee@company.com',
      type: data['type'] ?? 'General',
      amount: (data['amount'] ?? 0.0).toDouble(),
      date: data['date'] ?? 'Unknown Date',
      description: data['description'] ?? 'No description provided',
      status: data['status'] ?? 'Pending Verification',
      rejectionReason: data['rejectionReason'],
      receiptBase64: data['receiptBase64'] ?? data['receiptUrl'],
      processedBy: data['processedBy'],
      projectName: data['projectName'],
      uploaderRole: data['uploaderRole'] ?? 'employee', 
    );
  }
}

class AppNotification {
  final String expenseId;
  final String title; 
  final String subtitle;
  final String time;
  final String type; 

  AppNotification({
    required this.expenseId,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.type,
  });
}

class ExpenseStore extends ChangeNotifier {
  ExpenseStore._internal() {
    _loadThemePreference();
    _listenToDatabase();
    _listenToEmployeeStatus();
    _listenToBudget();
    _listenToProjects(); 
    _listenToProjectRequests();
  }

  static final ExpenseStore instance = ExpenseStore._internal();

  bool isDarkMode = true; 

  Color get bg => isDarkMode ? const Color(0xFF0D0D11) : const Color(0xFFF8F9FA);
  Color get card => isDarkMode ? const Color(0xFF16161F) : const Color(0xFFFFFFFF);
  Color get textFrost => isDarkMode ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937);
  Color get textMuted => isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get accentGold => const Color(0xFFE2B93B); 
  Color get border => isDarkMode ? const Color(0xFFE2B93B).withValues(alpha: 0.15) : const Color(0xFFE5E7EB);

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    // Dynamically grab the correct email based on their role
    final activeEmail = currentUserRole == 'employee' ? currentEmployeeEmail : currentManagerEmail;
    final key = activeEmail.isNotEmpty ? 'theme_$activeEmail' : 'isDarkMode';
    
    isDarkMode = prefs.getBool(key) ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    isDarkMode = !isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    
    final activeEmail = currentUserRole == 'employee' ? currentEmployeeEmail : currentManagerEmail;
    final key = activeEmail.isNotEmpty ? 'theme_$activeEmail' : 'isDarkMode';
    
    await prefs.setBool(key, isDarkMode);
    notifyListeners();
  }

  List<ExpenseRecord> expenses = [];
  List<ProjectRecord> projects = []; 
  List<Map<String, dynamic>> projectRequests = []; 
  final List<AppNotification> notifications = [];

  String currentManagerEmail = 'manager@company.com';
  String currentManagerName = 'Manager';
  String currentEmployeeEmail = 'employee@company.com';
  String currentEmployeeName = 'Employee';
  String currentEmployeeId = 'E00128';
  String currentUserRole = 'manager';
  
  bool get isHR => currentUserRole == 'hr';
  final Map<String, bool> employeeActiveStatus = {};
  final FirebaseFirestore _db = FirebaseFirestore.instance; 

  double currentMonthBudget = 60000.0;

  DateTime? _parseDate(String dateStr) {
    try {
      if (dateStr.contains(RegExp(r'[a-zA-Z]'))) {
        final parts = dateStr.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          int d = int.parse(parts[0]);
          String mStr = parts[1].toLowerCase().substring(0, 3);
          int y = int.parse(parts[2]);
          const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
          int m = months.indexOf(mStr) + 1;
          if (m > 0) return DateTime(y, m, d);
        }
      }
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length >= 3) {
          if (parts[0].length == 4) return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          if (parts[2].length == 4) return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        }
      } else if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length >= 3) {
          if (parts[2].length == 4) {
            int m = int.parse(parts[0]);
            int d = int.parse(parts[1]);
            if (m > 12) { m = int.parse(parts[1]); d = int.parse(parts[0]); }
            return DateTime(int.parse(parts[2]), m, d);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isCurrentMonth(String dateStr) {
    final d = _parseDate(dateStr);
    if (d == null) return false;
    final now = DateTime.now();
    return d.month == now.month && d.year == now.year;
  }

  void _listenToBudget() {
    final monthKey = _monthKey(DateTime.now());
    _db.collection('budgets').doc(monthKey).snapshots().listen((doc) {
      if (doc.exists) {
        currentMonthBudget = (doc.data()?['amount'] as num?)?.toDouble() ?? 60000.0;
      } else {
        currentMonthBudget = 60000.0;
      }
      notifyListeners();
    });
  }

  void _listenToProjects() {
    _db.collection('projects').snapshots().listen((snapshot) {
      projects = snapshot.docs.map((doc) => ProjectRecord.fromFirestore(doc)).toList();
      notifyListeners();
    });
  }

  void _listenToProjectRequests() {
    _db.collection('project_requests').snapshots().listen((snapshot) {
      projectRequests = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      notifyListeners();
    });
  }

  Future<void> submitProjectAccessRequest() async {
    await _db.collection('project_requests').doc(currentEmployeeEmail).set({
      'email': currentEmployeeEmail,
      'name': currentEmployeeName,
      'status': 'Pending Assignment',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- BULLETPROOF MANAGEMENT METHODS ---

  Future<void> updateProjectBudget(String projectId, double newBudget) async {
    // 1. Optimistic UI Update (Forces instant screen change)
    final pIndex = projects.indexWhere((p) => p.id == projectId);
    String pName = '';
    if (pIndex != -1) {
      pName = projects[pIndex].name;
      final old = projects[pIndex];
      projects[pIndex] = ProjectRecord(
        id: old.id,
        name: old.name,
        budget: newBudget, 
        assignedEmails: old.assignedEmails,
        isActive: old.isActive,
      );
      notifyListeners();
    }

    // 2. Bulletproof Firestore Update (Failsafe by name if ID misses)
    try {
      var docRef = _db.collection('projects').doc(projectId);
      var docSnap = await docRef.get();
      
      if (!docSnap.exists && pName.isNotEmpty) {
        final query = await _db.collection('projects').where('name', isEqualTo: pName).limit(1).get();
        if (query.docs.isNotEmpty) docRef = query.docs.first.reference;
      }
      await docRef.update({'budget': newBudget});
    } catch (e) {
      debugPrint('Error updating project budget: $e');
    }
  }

  Future<void> addMembersToProject(String projectId, List<String> emails) async {
    final pIndex = projects.indexWhere((p) => p.id == projectId);
    String pName = '';
    if (pIndex != -1) {
      pName = projects[pIndex].name;
      final old = projects[pIndex];
      final newEmails = List<String>.from(old.assignedEmails);
      for (var email in emails) {
        if (!newEmails.contains(email)) newEmails.add(email);
      }
      projects[pIndex] = ProjectRecord(
        id: old.id, name: old.name, budget: old.budget,
        assignedEmails: newEmails, isActive: old.isActive,
      );
      notifyListeners();
    }

    try {
      var docRef = _db.collection('projects').doc(projectId);
      var docSnap = await docRef.get();
      if (!docSnap.exists && pName.isNotEmpty) {
        final query = await _db.collection('projects').where('name', isEqualTo: pName).limit(1).get();
        if (query.docs.isNotEmpty) docRef = query.docs.first.reference;
      }
      await docRef.update({'assignedEmails': FieldValue.arrayUnion(emails)});
    } catch (e) {
      debugPrint('Error adding members: $e');
    }
  }

  Future<void> removeMemberFromProject(String projectId, String email) async {
    final pIndex = projects.indexWhere((p) => p.id == projectId);
    String pName = '';
    if (pIndex != -1) {
      pName = projects[pIndex].name;
      final old = projects[pIndex];
      final newEmails = List<String>.from(old.assignedEmails)..remove(email);
      projects[pIndex] = ProjectRecord(
        id: old.id, name: old.name, budget: old.budget,
        assignedEmails: newEmails, isActive: old.isActive,
      );
      notifyListeners();
    }

    try {
      var docRef = _db.collection('projects').doc(projectId);
      var docSnap = await docRef.get();
      if (!docSnap.exists && pName.isNotEmpty) {
        final query = await _db.collection('projects').where('name', isEqualTo: pName).limit(1).get();
        if (query.docs.isNotEmpty) docRef = query.docs.first.reference;
      }
      await docRef.update({'assignedEmails': FieldValue.arrayRemove([email])});
    } catch (e) {
      debugPrint('Error removing member: $e');
    }
  }

  Future<void> approveProjectAccess(String requestEmail, String projectId) async {
    final pIndex = projects.indexWhere((p) => p.id == projectId);
    String pName = '';
    if (pIndex != -1) {
      pName = projects[pIndex].name;
      final old = projects[pIndex];
      if (!old.assignedEmails.contains(requestEmail)) {
        final newEmails = List<String>.from(old.assignedEmails)..add(requestEmail);
        projects[pIndex] = ProjectRecord(
          id: old.id, name: old.name, budget: old.budget,
          assignedEmails: newEmails, isActive: old.isActive,
        );
        notifyListeners();
      }
    }

    projectRequests.removeWhere((r) => r['email'] == requestEmail);
    notifyListeners();

    try {
      var docRef = _db.collection('projects').doc(projectId);
      var docSnap = await docRef.get();
      if (!docSnap.exists && pName.isNotEmpty) {
        final query = await _db.collection('projects').where('name', isEqualTo: pName).limit(1).get();
        if (query.docs.isNotEmpty) docRef = query.docs.first.reference;
      }
      await docRef.update({'assignedEmails': FieldValue.arrayUnion([requestEmail])});
      await _db.collection('project_requests').doc(requestEmail).delete();
    } catch (e) {
      debugPrint('Error approving project access: $e');
    }
  }

  Future<void> closeProject(String projectId) async {
    final pIndex = projects.indexWhere((p) => p.id == projectId);
    String pName = '';
    if (pIndex != -1) pName = projects[pIndex].name;
    
    projects.removeWhere((p) => p.id == projectId);
    notifyListeners();

    try {
      var docRef = _db.collection('projects').doc(projectId);
      var docSnap = await docRef.get();
      if (!docSnap.exists && pName.isNotEmpty) {
        final query = await _db.collection('projects').where('name', isEqualTo: pName).limit(1).get();
        if (query.docs.isNotEmpty) docRef = query.docs.first.reference;
      }
      await docRef.delete();
    } catch (e) {
      debugPrint('Error closing project: $e');
    }
  }

  // --- FIX: SMART PROJECT FILTERING ---
  List<ProjectRecord> get myProjects {
    // 1. If it's a standard employee, strictly filter by their assigned email
    if (currentUserRole == 'employee') {
      final myEmail = currentEmployeeEmail.trim().toLowerCase();
      return projects.where((p) => 
        p.isActive && 
        p.assignedEmails.any((email) => email.trim().toLowerCase() == myEmail)
      ).toList();
    }
    
    // 2. For Management/HR/Admin (God Mode), return all active projects
    return projects.where((p) => p.isActive).toList();
  }
  double getProjectBurnAmount(String projectName) {
    return expenses
        .where((e) => e.projectName == projectName && (e.status == 'Approved' || e.status == 'Paid'))
        .fold(0.0, (totalAmount, e) => totalAmount + e.amount);
  }

  Future<void> createProject(String name, double budget, List<String> emails) async {
    try {
      final docRef = await _db.collection('projects').add({
        'name': name,
        'budget': budget,
        'assignedEmails': emails,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final instantProject = ProjectRecord(
        id: docRef.id,
        name: name,
        budget: budget,
        assignedEmails: emails, 
        isActive: true,
      );
      
      projects.insert(0, instantProject);
      notifyListeners(); 
    } catch (e) {
      debugPrint('Error creating project: $e');
    }
  }

  bool _canViewExpense(ExpenseRecord e) {
    final uploaderEmail = e.email.trim().toLowerCase();
    final myEmployeeEmail = currentEmployeeEmail.trim().toLowerCase();
    final myManagerEmail = currentManagerEmail.trim().toLowerCase();
    
    if (uploaderEmail == myEmployeeEmail || uploaderEmail == myManagerEmail) {
      return false; 
    }
    return true; 
  }

  int get pendingCount => expenses.where((e) => e.status == 'Pending Verification' && _isCurrentMonth(e.date) && _canViewExpense(e)).length;
  int get approvedCount => expenses.where((e) => e.status == 'Approved' && _isCurrentMonth(e.date) && _canViewExpense(e)).length;
  int get rejectedCount => expenses.where((e) => e.status == 'Rejected' && _isCurrentMonth(e.date) && _canViewExpense(e)).length;

  double get currentMonthBurnAmount {
    double total = 0;
    for (var e in expenses) {
      if ((e.status == 'Approved' || e.status == 'Paid') && _isCurrentMonth(e.date)) {
        total += e.amount;
      }
    }
    return total;
  }

  double get currentMonthBurnPercentage {
    if (currentMonthBudget <= 0) return 0.0;
    final pct = currentMonthBurnAmount / currentMonthBudget;
    return pct > 1.0 ? 1.0 : pct;
  }

  Map<String, double> get categorySpend {
    Map<String, double> breakdown = {};
    for (var e in expenses) {
      if ((e.status == 'Approved' || e.status == 'Paid') && _isCurrentMonth(e.date)) {
        breakdown[e.type] = (breakdown[e.type] ?? 0) + e.amount;
      }
    }
    var sortedKeys = breakdown.keys.toList(growable: false)..sort((k1, k2) => breakdown[k2]!.compareTo(breakdown[k1]!));
    Map<String, double> sortedBreakdown = {};
    for (var k in sortedKeys) {
      sortedBreakdown[k] = breakdown[k]!;
    }
    return sortedBreakdown;
  }

  List<Map<String, dynamic>> get urgentRequests {
    final pending = expenses.where((e) => e.status == 'Pending Verification' && _canViewExpense(e)).toList();
    List<Map<String, dynamic>> urgent = [];
    final now = DateTime.now();

    ExpenseRecord? stale;
    int maxDays = -1;
    for (var p in pending) {
      final d = _parseDate(p.date);
      if (d != null) {
        final diff = now.difference(d).inDays;
        if (diff >= 2 && diff > maxDays) {
          maxDays = diff;
          stale = p;
        }
      }
    }

    if (stale != null) {
      urgent.add({'expense': stale, 'reason': 'SLA Breach: $maxDays Days Old', 'isSla': true});
    }

    ExpenseRecord? high;
    double maxAmt = 0;
    for (var p in pending) {
      if (stale != null && p.id == stale.id) continue;
      if (p.amount > maxAmt) {
        maxAmt = p.amount;
        high = p;
      }
    }

    if (high != null) {
      urgent.add({'expense': high, 'reason': 'High Value Request', 'isSla': false});
    }

    return urgent;
  }

  List<Map<String, dynamic>> getChartData(String timeframe) {
    final now = DateTime.now();
    int monthsToFetch = 5; 

   if (timeframe == 'This Month') {
      monthsToFetch = 1;
    } else if (timeframe == 'Last 3 Months') {
      monthsToFetch = 3;
    } else if (timeframe == 'Last 6 Months') {
      monthsToFetch = 6;
    } else if (timeframe == 'Year to Date') {
      monthsToFetch = now.month;
    }

    final List<Map<String, dynamic>> chartData = [];
    const monthLabels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    double maxAmount = currentMonthBudget > 0 ? currentMonthBudget : 1.0; 
    
    List<double> monthlyTotals = List.filled(monthsToFetch, 0.0);
    List<String> labels = [];

    for (int i = monthsToFetch - 1; i >= 0; i--) {
      int m = now.month - i;
      int y = now.year;
      while (m <= 0) {
        m += 12;
        y -= 1;
      }
      labels.add(monthLabels[m - 1]);

      double total = 0;
      for (var e in expenses) {
        if (e.status == 'Approved' || e.status == 'Paid') {
          final d = _parseDate(e.date);
          if (d != null && d.month == m && d.year == y) {
            total += e.amount;
          }
        }
      }
      monthlyTotals[(monthsToFetch - 1) - i] = total;
    }

    for (int i = 0; i < monthsToFetch; i++) {
      double pct = monthlyTotals[i] / maxAmount;
      if (pct > 1.0) pct = 1.0; 
      
      chartData.add({
        'label': labels[i],
        'percentage': pct,
      });
    }
    return chartData;
  }

  void setCurrentManager({required String email}) {
    currentManagerEmail = email;
    currentManagerName = _deriveName(email, fallback: 'Manager');
    currentEmployeeEmail = email; 
    currentEmployeeName = currentManagerName; 
    
    _loadThemePreference(); 
    notifyListeners();
  }

  void setManagerName(String name) {
    currentManagerName = name;
    currentEmployeeName = name; 
    notifyListeners();
  }

  void setCurrentEmployee({required String email}) {
    currentEmployeeEmail = email;
    currentEmployeeName = _deriveName(email, fallback: 'Employee');   
    _loadThemePreference(); // <-- FIX: Load the employee's personal theme choice!
    notifyListeners();
  }

  void setEmployeeName(String name) {
    currentEmployeeName = name;
    notifyListeners();
  }

  String _deriveName(String email, {required String fallback}) {
    final localPart = email.split('@').first;
    final parts = localPart.split(RegExp(r'[._]+')).where((p) => p.isNotEmpty);
    final name = parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
    return name.trim().isEmpty ? fallback : name;
  }

  Future<void> updateName(String newName, bool isManager) async {
    final email = isManager ? currentManagerEmail : currentEmployeeEmail;
    try {
      await _db.collection('users').doc(email).set({
        'name': newName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (isManager) {
        currentManagerName = newName;
      } else {
        currentEmployeeName = newName;
      }
      notifyListeners();
    } catch (e) {
      if (isManager) {
        currentManagerName = newName;
      } else {
        currentEmployeeName = newName;
      }
      notifyListeners();
    }
  }

  String getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  String _generateTrackingId() {
    final uniqueSuffix = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    return 'EMP-2026-$uniqueSuffix';
  }

  void _listenToDatabase() {
    _db.collection('expenses').snapshots().listen((snapshot) {
      expenses = snapshot.docs.map((doc) => ExpenseRecord.fromFirestore(doc)).toList();
      notifyListeners(); 
    });
  }

  Future<void> loadCurrentUserRole(String email) async {
    try {
      final doc = await _db.collection('users').doc(email).get();
      if (doc.exists) {
        final data = doc.data();
        currentUserRole = (data?['role'] as String?) ?? 'manager';
      } else {
        currentUserRole = 'manager';
      }
    } catch (_) {
      currentUserRole = 'manager';
    }
    notifyListeners();
  }

  String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<double?> getBudgetForMonth(DateTime month) async {
    final doc = await _db.collection('budgets').doc(_monthKey(month)).get();
    if (!doc.exists) return null;
    return (doc.data()?['amount'] as num?)?.toDouble();
  }

  Future<String?> setBudgetForMonth(DateTime month, double amount) async {
    if (amount <= 0) return 'Budget must be greater than zero.';
    await _db.collection('budgets').doc(_monthKey(month)).set({
      'amount': amount,
      'setByEmail': currentManagerEmail,
      'setByName': currentManagerName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return null;
  }

  void _listenToEmployeeStatus() {
    _db.collection('employee_status').snapshots().listen((snapshot) {
      employeeActiveStatus.clear();
      for (final doc in snapshot.docs) {
        employeeActiveStatus[doc.id] = doc.data()['isActive'] ?? true;
      }
      notifyListeners();
    });
  }

  bool isEmployeeActive(String email) => employeeActiveStatus[email] ?? true;

  List<Map<String, String>> get allEmployees {
    final map = <String, Map<String, String>>{};
    for (final e in expenses) {
      map[e.email] = {'email': e.email, 'name': e.name, 'id': e.id};
    }
    final list = map.values.toList();
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  Future<void> setEmployeeActive(String email, bool isActive) async {
    await _db.collection('employee_status').doc(email).set({
      'email': email,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': currentManagerEmail,
    }, SetOptions(merge: true));
  }

  Future<String?> submitExpense({
    required String type,
    required double amount,
    required String date, 
    required String description,
    required DateTime rawDate,
    Uint8List? receiptBytes, 
    String? projectName, 
  }) async {
    if (type.trim().isEmpty) return 'Please select an expense type.';
    if (description.trim().isEmpty) return 'Please enter a description.';
    if (amount <= 0) return 'Amount must be a positive, non-zero value.';
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(rawDate.year, rawDate.month, rawDate.day);
    if (dateOnly.isAfter(todayOnly)) return 'Date cannot be in the future.';

    final trackingId = _generateTrackingId();
    String? base64Image;

    if (receiptBytes != null) {
      try {
        base64Image = base64Encode(receiptBytes);
        if (base64Image.length > 800000) {
          return 'Receipt image is too large. Please use a smaller image.';
        }
      } catch (e) {
        return 'Failed to encode receipt image.';
      }
    }

    try {
      final instantExpense = ExpenseRecord(
        id: trackingId,
        name: currentEmployeeName,
        email: currentEmployeeEmail,
        type: type,
        amount: amount,
        date: date,
        description: description,
        status: 'Pending Verification',
        receiptBase64: base64Image,
        projectName: projectName,
        uploaderRole: currentUserRole,
      );
      
      expenses.insert(0, instantExpense);
      notifyListeners(); 

      await _db.collection('expenses').add({
        'employeeId': trackingId,
        'employeeName': currentEmployeeName,
        'email': currentEmployeeEmail,
        'type': type,
        'amount': amount,
        'date': date,
        'description': description,
        'status': 'Pending Verification',
        'receiptBase64': base64Image, 
        'projectName': projectName, 
        'uploaderRole': currentUserRole, 
      }).timeout(const Duration(seconds: 10)); 
      
      return null; 
    } catch (e) {
      expenses.removeWhere((expense) => expense.id == trackingId);
      notifyListeners();
      return 'Upload failed or timed out. Please check your internet or try a smaller image.';
    }
  }

  List<ExpenseRecord> get myExpenses =>
      expenses.where((e) => e.email.trim().toLowerCase() == currentEmployeeEmail.trim().toLowerCase()).toList();

  int get myPendingCount => myExpenses.where((e) => e.status == 'Pending Verification').length;
  int get myApprovedCount => myExpenses.where((e) => e.status == 'Approved').length;
  int get myRejectedCount => myExpenses.where((e) => e.status == 'Rejected').length;
  int get myTotalUploads => myExpenses.length;

  ExpenseRecord byId(String id) => expenses.firstWhere((e) => e.id == id);

  bool isLocked(String id) {
    final status = byId(id).status;
    return status == 'Approved' || status == 'Rejected' || status == 'Paid';
  }

  void _addNotification(String expenseId, String title, String subtitle, String type) {
    final now = DateTime.now();
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    int hr = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final timeString = 'Today, $hr:${now.minute.toString().padLeft(2, '0')} $ampm';

    notifications.insert(0, AppNotification(
      expenseId: expenseId,
      title: title,
      subtitle: subtitle,
      time: timeString,
      type: type,
    ));
    notifyListeners();
  }

  void approve(String id) {
    final expense = byId(id);
    if (isLocked(id)) return;
    
    final name = currentManagerName.isNotEmpty ? currentManagerName : 'Manager';
    final role = currentUserRole.isNotEmpty ? currentUserRole.toUpperCase() : 'MANAGER';
    final processedStr = '$name ($role)';
    
    expense.status = 'Approved';
    expense.processedBy = processedStr; 
    notifyListeners();
    
    _safeUpdate(expense, {
      'status': 'Approved',
      'processedBy': processedStr 
    });
    _addNotification(expense.id, expense.name, 'Expense request of ${expense.amountFormatted} has been approved.', 'approved');
  }

  void reject(String id, {required String reason}) {
    final expense = byId(id);
    if (isLocked(id)) return;
    
    final name = currentManagerName.isNotEmpty ? currentManagerName : 'Manager';
    final role = currentUserRole.isNotEmpty ? currentUserRole.toUpperCase() : 'MANAGER';
    final processedStr = '$name ($role)';
    
    expense.status = 'Rejected';
    expense.rejectionReason = reason;
    expense.processedBy = processedStr; 
    notifyListeners();
    
    _safeUpdate(expense, {
      'status': 'Rejected',
      'rejectionReason': reason,
      'processedBy': processedStr 
    });
    _addNotification(expense.id, expense.name, 'Expense request of ${expense.amountFormatted} was rejected.', 'rejected');
  }

  void requestMoreInfo(String id) {
    final expense = byId(id);
    if (isLocked(id)) return;
    
    expense.status = 'Info Requested';
    notifyListeners();
    
    _safeUpdate(expense, {'status': 'Info Requested'});
    _addNotification(expense.id, expense.name, 'Additional details requested for ${expense.amountFormatted}.', 'info');
  }

  void markPaid(String id) {
    final expense = byId(id);
    
    expense.status = 'Paid';
    notifyListeners();
    
    _safeUpdate(expense, {
      'status': 'Paid',
      'paidAt': FieldValue.serverTimestamp()
    });
    _addNotification(expense.id, expense.name, 'Payment for ${expense.amountFormatted} has been disbursed.', 'paid');
  }

  Future<void> _safeUpdate(ExpenseRecord expense, Map<String, dynamic> data) async {
    try {
      if (expense.firestoreDocId.isNotEmpty) {
        await _db.collection('expenses').doc(expense.firestoreDocId).update(data);
      } else {
        final snap = await _db.collection('expenses').where('employeeId', isEqualTo: expense.id).limit(1).get();
        if (snap.docs.isNotEmpty) {
          await snap.docs.first.reference.update(data);
        }
      }
    } catch (e) {
      debugPrint('Silent update error: $e');
    }
  }

  void toggleDecrypt(String id) {
    final expense = byId(id);
    expense.decrypted = !expense.decrypted;
    notifyListeners();
  }

  Future<void> nukeAllExpenses() async {
    final snapshots = await _db.collection('expenses').get();
    final batch = _db.batch();
    for (var doc in snapshots.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}