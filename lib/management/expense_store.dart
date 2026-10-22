import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/core/formatting.dart';
import 'package:ats_onework/ui/tokens.dart';

/// Tolerant double parse — backend money fields (pydantic ``Decimal``) can
/// arrive as either a JSON number or a string depending on serialization.
double? parseBackendDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

class ProjectRecord {
  final String id;
  final String name;
  final double budget;

  /// Budget row the project references — needed for PATCH budget editing.
  final String? budgetId;
  final int memberCount;

  /// Ids of the employees assigned to the project. The backend sends
  /// these as ``assigned_employee_ids``; without them a client cannot
  /// tell which projects the signed-in employee can act in.
  final List<String> assignedEmails;
  final bool isActive;

  ProjectRecord({
    required this.id,
    required this.name,
    required this.budget,
    this.budgetId,
    this.memberCount = 0,
    required this.assignedEmails,
    required this.isActive,
  });

  factory ProjectRecord.fromJson(Map<String, dynamic> json) {
    final assigned = json['assigned_employee_ids'] ?? json['assignedEmails'];
    return ProjectRecord(
      id: (json['project_id'] ?? json['id'])?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Project',
      budget:
          parseBackendDouble(json['budget'] ?? json['budget_amount']) ?? 0.0,
      budgetId: json['budget_id']?.toString(),
      memberCount: int.tryParse(json['member_count']?.toString() ?? '0') ?? 0,
      assignedEmails: assigned is List
          ? assigned.map((e) => e.toString()).toList()
          : const <String>[],
      isActive: (json['is_active'] ?? json['isActive']) ?? true,
    );
  }
}

class ExpenseRecord {
  final String firestoreDocId;
  final String id;
  final String name;
  final String email;

  /// Employee id of the submitter — the stable key for "my expenses".
  /// The email is not: the backend exposes it, but matching on the id
  /// is what the API itself scopes by.
  final String employeeId;
  final String type;
  final double amount;
  final String date;
  final String description;
  String status;
  String? rejectionReason;

  /// The manager's question while a request sits in 'Info Requested'.
  String? infoMessage;

  /// The employee's answer to that question.
  String? infoResponse;
  final String? receiptBase64;
  String? processedBy;
  final String? projectName;
  final String uploaderRole;

  ExpenseRecord({
    this.firestoreDocId = '',
    required this.id,
    required this.name,
    required this.email,
    this.employeeId = '',
    required this.type,
    required this.amount,
    required this.date,
    required this.description,
    this.status = 'Pending Verification',
    this.rejectionReason,
    this.infoMessage,
    this.infoResponse,
    this.receiptBase64,
    this.processedBy,
    this.projectName,
    this.uploaderRole = 'employee',
  });

  String get amountFormatted => '₹${amount.toStringAsFixed(2)}';

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    // Supports both legacy Firebase shape and new FastAPI shape
    // (expense_id, expense_date, status lowercase, receipts[]).
    final receipts = json['receipts'];
    String? receipt;
    if (receipts is List && receipts.isNotEmpty) {
      final first = receipts.first;
      if (first is Map) receipt = first['receipt_url']?.toString();
    }
    final rawStatus = (json['status']?.toString() ?? 'pending').toLowerCase();
    final status = switch (rawStatus) {
      'pending' => 'Pending Verification',
      'info_requested' => 'Info Requested',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'reimbursed' || 'paid' => 'Paid',
      _ => json['status']?.toString() ?? 'Pending Verification',
    };
    // The API sends the resolved names; the legacy field names are kept
    // as fallbacks for older payloads.
    final typeName = json['expense_type_name']?.toString();
    final typeId = json['expense_type_id']?.toString();
    return ExpenseRecord(
      firestoreDocId: (json['expense_id'] ?? json['id'])?.toString() ?? '',
      id:
          (json['expense_id'] ?? json['employeeId'] ?? json['id'])
              ?.toString() ??
          'EMP-UNKNOWN',
      name:
          (json['employee_name'] ?? json['employeeName'] ?? json['name'])
              ?.toString() ??
          'Unknown Employee',
      email:
          (json['employee_email'] ?? json['email'])?.toString() ??
          'employee@company.com',
      employeeId: (json['employee_id'] ?? json['employeeId'])?.toString() ?? '',
      type: (typeName != null && typeName.isNotEmpty)
          ? typeName
          : (json['type']?.toString() ?? typeId ?? 'General'),
      // Money arrives as a JSON string ("1000.00") — the serializer
      // emits Decimal as text. A bare `as num?` cast threw a TypeError
      // on the first row and the whole expense list stayed empty.
      amount: parseBackendDouble(json['amount']) ?? 0.0,
      date:
          json['date']?.toString() ??
          json['expense_date']?.toString() ??
          'Unknown Date',
      description: json['description']?.toString() ?? 'No description provided',
      status: status,
      rejectionReason: (json['rejectionReason'] ?? json['rejection_reason'])
          ?.toString(),
      infoMessage: (json['infoMessage'] ?? json['info_message'])?.toString(),
      infoResponse: json['info_response']?.toString(),
      receiptBase64:
          json['receiptBase64']?.toString() ??
          json['receiptUrl']?.toString() ??
          receipt,
      processedBy: json['processedBy']?.toString(),
      projectName: (json['project_name'] ?? json['projectName'])?.toString(),
      uploaderRole: json['uploaderRole']?.toString() ?? 'employee',
    );
  }
}

class AppNotification {
  final String expenseId;
  final String title;
  final String subtitle;
  final String time;
  final String type;

  /// When the notification was created, when the backend said so. The
  /// feed shows "2h ago" for recent items and the date for older ones.
  final DateTime? createdAt;

  AppNotification({
    required this.expenseId,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.type,
    this.createdAt,
  });
}

/// Maps a backend notification ``type`` (e.g. ``expense.info_requested``)
/// onto the short tokens the notification screens style by.
String normalizeNotificationType(String backendType) {
  if (backendType.startsWith('expense.approved')) return 'approved';
  if (backendType.startsWith('expense.rejected')) return 'rejected';
  if (backendType.startsWith('expense.info_requested')) return 'info';
  if (backendType.startsWith('expense.resubmit')) return 'resubmit';
  if (backendType.contains('.paid')) return 'paid';
  if (backendType.startsWith('project.member.added')) return 'project-added';
  if (backendType.startsWith('project.member.removed')) {
    return 'project-removed';
  }
  if (backendType.startsWith('project_access.approved')) {
    return 'project-approved';
  }
  if (backendType.startsWith('project_access.rejected')) {
    return 'project-rejected';
  }
  return 'other';
}

/// Measurable membership — one row of GET /projects/{id}/members (§49 24a).
class ProjectMemberRecord {
  final String employeeId;
  final String name;
  final String email;
  final String roleName;

  ProjectMemberRecord({
    required this.employeeId,
    required this.name,
    required this.email,
    required this.roleName,
  });

  factory ProjectMemberRecord.fromJson(Map<String, dynamic> json) {
    return ProjectMemberRecord(
      employeeId: (json['employee_id'] ?? json['employeeId'] ?? '').toString(),
      name: json['employee_name']?.toString() ?? '',
      email: json['employee_email']?.toString() ?? '',
      roleName: json['role_name']?.toString() ?? '',
    );
  }
}

/// One page of a cursor-paginated list: the rows, and the cursor of the
/// next page — or nothing when the list is exhausted. [failed] marks a
/// non-200 response so callers can tell "no data" from "load refused".
class _Page {
  const _Page(this.items, this.nextCursor, {this.failed = false});

  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final bool failed;
}

class ExpenseStore extends ChangeNotifier {
  ExpenseStore._internal() {
    _loadThemePreference();
    // Only fetch when a session already exists — the store singleton is
    // first touched by the login screens, so an unconditional bootstrap
    // used to fire doomed requests with no token on every cold start.
    // Login and session-resume call [primeSessionData] explicitly.
    _bootstrapWhenAuthenticated();
  }

  Future<void> _bootstrapWhenAuthenticated() async {
    if ((await ApiClient.getToken()).isEmpty) return;
    await primeSessionData();
  }

  /// Loads the signed-in user's working set (dashboards, projects, users,
  /// request queues). Awaiting this lets callers hold the UI until data
  /// is on screen. Individual fetches swallow their own errors.
  Future<void> primeSessionData() async {
    await Future.wait([
      fetchExpensesFromBackend(),
      fetchProjectsFromBackend(),
      fetchProjectRequestsFromBackend(),
      fetchUsersFromBackend(),
      fetchEmployeeStatusFromBackend(),
      fetchExpenseTypesFromBackend(),
      fetchNotificationsFromBackend(),
    ]);
    fetchBudgetFromBackend();
  }

  static final ExpenseStore instance = ExpenseStore._internal();

  bool isDarkMode = true;

  // Per-user device-local notification preferences. The profile screens
  // present them as "saved on this device", so they must actually survive
  // a restart — previously they were plain State fields that reset on
  // every launch while claiming to be saved.
  bool emailAlerts = true;
  bool pushAlerts = true;
  bool statusUpdateAlerts = true;

  // Palette aliases kept for the screens that still read colours from the
  // store. New code uses `context.palette`; both resolve to AppTokens, so
  // there is one source of truth and the light theme is never a different
  // gold.
  Color get bg => isDarkMode ? AppTokens.darkBg : AppTokens.lightBg;
  Color get card => isDarkMode ? AppTokens.darkSurface : AppTokens.lightSurface;
  Color get textFrost => isDarkMode ? AppTokens.darkText : AppTokens.lightText;
  Color get textMuted =>
      isDarkMode ? AppTokens.darkMuted : AppTokens.lightMuted;
  Color get accentGold => isDarkMode ? AppTokens.gold : AppTokens.goldDeep;
  Color get border => isDarkMode ? AppTokens.darkBorder : AppTokens.lightBorder;

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final activeEmail = currentUserRole == 'employee'
        ? currentEmployeeEmail
        : currentManagerEmail;

    final key = activeEmail.isNotEmpty
        ? 'theme_${activeEmail}_$currentUserRole'
        : 'isDarkMode_$currentUserRole';

    isDarkMode = prefs.getBool(key) ?? true;
    lastSeenNotificationCount =
        prefs.getInt(_notificationSeenKey(activeEmail)) ?? 0;

    final prefsKey = _perUserPrefsKey(activeEmail);
    emailAlerts = prefs.getBool('${prefsKey}_email') ?? true;
    pushAlerts = prefs.getBool('${prefsKey}_push') ?? true;
    statusUpdateAlerts = prefs.getBool('${prefsKey}_status') ?? true;

    notifyListeners();
  }

  String _perUserPrefsKey(String activeEmail) =>
      'notification_prefs_${activeEmail.isEmpty ? currentUserRole : activeEmail}';

  /// Persists a device-local notification preference for the signed-in
  /// user. Called by the profile screens' preference switches so the
  /// "saved on this device" wording is true.
  Future<void> setNotificationPreference(String which, bool value) async {
    switch (which) {
      case 'email':
        emailAlerts = value;
      case 'push':
        pushAlerts = value;
      case 'status':
        statusUpdateAlerts = value;
      default:
        return;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final activeEmail = currentUserRole == 'employee'
        ? currentEmployeeEmail
        : currentManagerEmail;
    await prefs.setBool('${_perUserPrefsKey(activeEmail)}_$which', value);
  }

  /// How many notifications had been seen when the feed was last opened.
  int lastSeenNotificationCount = 0;

  int get unreadNotificationCount {
    final int unread = notifications.length - lastSeenNotificationCount;
    return unread > 0 ? unread : 0;
  }

  String _notificationSeenKey(String activeEmail) =>
      'notifications_seen_${activeEmail.isEmpty ? currentUserRole : activeEmail}';

  /// Called when the notification hub opens. Persisted per user so the
  /// badge does not reappear on every launch.
  Future<void> markNotificationsSeen() async {
    if (notifications.isEmpty) return;
    lastSeenNotificationCount = notifications.length;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final activeEmail = currentUserRole == 'employee'
        ? currentEmployeeEmail
        : currentManagerEmail;
    await prefs.setInt(
      _notificationSeenKey(activeEmail),
      lastSeenNotificationCount,
    );
  }

  /// Public re-read of the persisted theme for the active user/role —
  /// used by session resume in main.dart after re-resolving identity.
  Future<void> reloadThemePreference() => _loadThemePreference();

  List<String> customExpenseTypes = [];

  List<String> get availableExpenseTypes {
    const base = ['Travel', 'Meals', 'Supplies', 'Lodging', 'Software'];
    final combined = <String>{...base, ...customExpenseTypes};
    return combined.toList();
  }

  /// The organization the signed-in user is working in. Set when the
  /// session is established, so screens can read it without a round-trip.
  int? currentOrganizationId;

  Future<int?> _orgId() async {
    if (currentOrganizationId != null) return currentOrganizationId;
    return ApiClient.getOrganizationId();
  }

  Future<void> fetchExpenseTypesFromBackend() async {
    try {
      final orgId = await _orgId();
      if (orgId == null) return;
      final response = await ApiClient.get(
        '/organizations/$orgId/expense-types',
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        customExpenseTypes = data
            .map((item) => (item as Map<String, dynamic>)['name'].toString())
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Network error fetching expense types: $e');
    }
  }

  Future<void> addNewExpenseType(String typeName) async {
    final clean = typeName.trim();
    if (clean.isEmpty) return;
    try {
      final orgId = await _orgId();
      if (orgId == null) return;
      final response = await ApiClient.post(
        '/organizations/$orgId/expense-types',
        {'name': clean},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchExpenseTypesFromBackend();
      }
    } catch (e) {
      debugPrint('Error adding expense type: $e');
    }
  }

  List<Map<String, String>> usersList = [];

  /// One-time-load markers so screens can tell "still loading" apart from
  /// an genuinely empty list (empty states used to double as loading states).
  bool expensesLoaded = false;
  bool projectsLoaded = false;
  bool usersLoaded = false;

  /// What went wrong the last time a collection failed to load, or null
  /// when the last attempt succeeded. An empty list and a failed fetch
  /// look identical without this, so a network blip was shown as "No
  /// claims yet" — a false statement of fact.
  String? usersError;
  String? expensesError;
  String? projectsError;

  Future<void> fetchUsersFromBackend() async {
    try {
      final page = await _fetchPage('/users');
      usersList = page.items.map(_userRow).toList();
      usersCursor = page.nextCursor;
      usersError = null;
      notifyListeners();
    } catch (e) {
      usersError = "Couldn't load the member directory.";
      debugPrint('Network error fetching users: $e');
      notifyListeners();
    } finally {
      usersLoaded = true;
    }
  }

  /// Loads the next page of the member directory and appends it.
  Future<void> loadMoreUsers() async {
    final cursor = usersCursor;
    if (cursor == null || usersLoadingMore) return;
    usersLoadingMore = true;
    try {
      final page = await _fetchPage('/users', cursor: cursor);
      usersList = [...usersList, ...page.items.map(_userRow)];
      usersCursor = page.nextCursor;
      notifyListeners();
    } catch (e) {
      debugPrint('Network error loading more users: $e');
    } finally {
      usersLoadingMore = false;
    }
  }

  bool get hasMoreUsers => usersCursor != null;

  /// The cursor of the next page of the member directory.
  String? usersCursor;

  bool usersLoadingMore = false;

  /// The member directory's row shape.
  static Map<String, String> _userRow(Map<String, dynamic> u) => {
    'id': (u['employee_id'] ?? u['employeeId'] ?? u['id'] ?? '').toString(),
    'name': (u['name'] ?? 'Unknown').toString(),
    'email': (u['email'] ?? '').toString(),
    'account_status': (u['account_status'] ?? 'active').toString(),
  };

  /// Admin action: toggle a user's account_status via PATCH /users/{id}.
  /// Returns true when the backend confirmed the change (list refreshed).
  Future<bool> updateUserAccountStatus(String employeeId, bool active) async {
    try {
      final response = await ApiClient.patch('/users/$employeeId', {
        'account_status': active ? 'active' : 'inactive',
      });
      if (response.statusCode == 200) {
        await fetchUsersFromBackend();
        return true;
      }
      debugPrint('updateUserAccountStatus failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('updateUserAccountStatus error: $e');
    }
    return false;
  }

  Future<void> toggleTheme() async {
    isDarkMode = !isDarkMode;
    final prefs = await SharedPreferences.getInstance();

    final activeEmail = currentUserRole == 'employee'
        ? currentEmployeeEmail
        : currentManagerEmail;

    final key = activeEmail.isNotEmpty
        ? 'theme_${activeEmail}_$currentUserRole'
        : 'isDarkMode_$currentUserRole';

    await prefs.setBool(key, isDarkMode);
    notifyListeners();
  }

  List<ExpenseRecord> expenses = [];
  List<ProjectRecord> projects = [];

  /// Clears every piece of user data held in memory.
  ///
  /// The store is a singleton, so without this the next person to use the
  /// device saw the previous user's expenses, projects and directory
  /// until a refetch happened to overwrite them.
  void resetForSignOut() {
    expenses = [];
    projects = [];
    usersList = [];
    projectRequests = [];
    notifications = [];
    // The seen-count belongs to the person who just signed out — the next
    // user must not inherit their badge.
    lastSeenNotificationCount = 0;
    notificationsLoaded = false;
    notificationsError = null;
    employeeActiveStatus.clear();
    currentUserRoles = <String>[];
    grantedPermissions = <String>{};
    isSuperUser = false;
    currentOrganizationId = null;
    expensesLoaded = false;
    projectsLoaded = false;
    usersLoaded = false;
    usersError = null;
    expensesError = null;
    projectsError = null;
    currentUserId = '';
    currentUserEmail = '';
    currentUserName = '';
    currentEmployeeId = '';
    currentEmployeeEmail = '';
    currentEmployeeName = '';
    currentManagerEmail = '';
    currentManagerName = '';
    notifyListeners();
  }

  /// Replace the cached project list wholesale and notify listeners in one
  /// step — used by login-priming flows that bypass [fetchProjectsFromBackend]
  /// (external mutations of a ChangeNotifier's fields don't notify).
  void setProjects(List<ProjectRecord> value) {
    projects = value;
    notifyListeners();
  }

  List<Map<String, dynamic>> projectRequests = [];

  /// Backend notification feed (§49 #36 — owner-scoped). Refreshed from
  /// GET /notifications; local inserts remain as optimistic cache entries
  /// until the next refresh reconciles them.
  List<AppNotification> notifications = [];

  /// Whether the feed has completed its first fetch.
  bool notificationsLoaded = false;

  /// Null unless the last feed fetch failed and produced nothing usable.
  String? notificationsError;

  /// Loads the signed-in user's real notification feed from the backend
  /// (GET /notifications — already scoped to the token's employee).
  /// Returns `false` when the load failed — the reason is in
  /// [notificationsError] for the hub screen to show with a retry.
  Future<bool> fetchNotificationsFromBackend() async {
    try {
      final response = await ApiClient.get(
        '/notifications',
        query: {'limit': '50'},
      );
      if (response.statusCode != 200) {
        notificationsError =
            "Couldn't load notifications (server ${response.statusCode}).";
        return false;
      }
      final items = ApiClient.pageItems(response);
      notifications = items.map((raw) {
        final map = raw as Map<String, dynamic>;
        final createdAt = DateTime.tryParse(
          map['created_at']?.toString() ?? '',
        );
        return AppNotification(
          expenseId: map['reference_id']?.toString() ?? '',
          title: map['title']?.toString() ?? '',
          subtitle: map['message']?.toString() ?? '',
          time: createdAt == null ? '' : _timeLabel(createdAt),
          createdAt: createdAt,
          type: normalizeNotificationType(map['type']?.toString() ?? ''),
        );
      }).toList();
      notificationsError = null;
      notifyListeners();
      return true;
    } catch (e) {
      notificationsError =
          "Couldn't load notifications. Check your connection.";
      debugPrint('Network error fetching notifications: $e');
      return false;
    } finally {
      notifyListeners();
      notificationsLoaded = true;
    }
  }

  String _timeLabel(DateTime d) {
    final now = DateTime.now();
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    int hr = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return 'Today, $hr:${d.minute.toString().padLeft(2, '0')} $ampm';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}, $hr:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  String currentManagerEmail = 'manager@company.com';
  String currentManagerName = 'Manager';
  String currentEmployeeEmail = 'employee@company.com';
  String currentEmployeeName = 'Employee';
  String currentEmployeeId = 'E00128';
  String currentUserRole = 'manager';
  String currentUserName = 'User';
  String currentUserEmail = '';
  String currentUserId = '';

  /// The roles the server reports for the signed-in user in the active
  /// organization. Empty until the profile has been read.
  List<String> currentUserRoles = <String>[];

  /// Every capability the server reports for the signed-in user. The
  /// API decides what the user may do; the client only reflects it.
  Set<String> grantedPermissions = <String>{};

  /// Whether the user is a platform super administrator — an account
  /// that administers the access model itself, across organizations.
  bool isSuperUser = false;

  /// Whether the signed-in user holds a capability.
  bool can(String capability) => grantedPermissions.contains(capability);

  bool get canReadAllExpenses => can('expense.read_all');
  bool get canApproveExpenses => can('expense.approve');
  bool get canPayReimbursements => can('reimbursement.transition');
  bool get canManagePeople => can('user.manage');
  bool get canManageAccess => can('role.manage');
  bool get canReadAuditLog => can('audit.read');
  bool get canSeeReports => can('audit.read') || can('expense.read_all');

  bool get isHR => currentUserRole == 'hr';

  /// The capabilities that make the management portal relevant.
  ///
  /// These are the ones a manager, finance user, director or HR user
  /// holds. The ``is_admin`` flag is *not* the test: that flag means
  /// "owns this organization", which is a different thing entirely.
  static const Set<String> managementCapabilities = <String>{
    'expense.read_all',
    'expense.approve',
    'expense.request_info',
    'reimbursement.create',
    'reimbursement.transition',
    'reimbursement.receipt',
    'project.create',
    'project.manage',
    'project.member.manage',
    'project.access.review',
    'budget.manage',
    'user.read',
    'user.manage',
    'employee_status.manage',
    'audit.read',
    'organization.manage',
    'role.manage',
  };

  /// Whether the signed-in user belongs in the management portal.
  bool get hasManagementAccess =>
      grantedPermissions.any(managementCapabilities.contains);

  /// Capability personas the navigation builds itself from — the role
  /// name is never consulted for these. A person who can move
  /// reimbursements through their lifecycle needs the payout screens
  /// even when their role is a custom one the portal has never heard
  /// of.
  bool get payoutPersona => canPayReimbursements;

  /// Reviews expenses but holds none of the project/budget building
  /// capabilities — the director shape.
  bool get reviewerOnlyPersona =>
      canApproveExpenses &&
      canReadAuditLog &&
      !can('budget.manage') &&
      !can('project.create') &&
      !can('project.manage');

  /// Records what the server says about the signed-in user.
  ///
  /// The role is derived from the roles the server reports, with the
  /// most privileged first — a person who holds both `finance` and
  /// `employee` is treated as finance. The capabilities are kept
  /// separately: they are what actually decides what the user may do.
  void setUserAccess({
    List<String> roles = const <String>[],
    List<String> permissions = const <String>[],
    bool superuser = false,
  }) {
    currentUserRoles = roles;
    grantedPermissions = permissions.toSet();
    isSuperUser = superuser;
    currentUserRole = _primaryRole(roles, grantedPermissions);
    notifyListeners();
  }

  /// The role the interface branches on, most privileged first.
  ///
  /// A custom role the portal has never heard of (created in the Access
  /// tab) is *inferred* from its capabilities instead of defaulting to
  /// `employee` — being read as an employee changes behavior beyond
  /// portal selection (it scopes myProjects and the theme key), and
  /// someone who can approve reimbursements is not an employee.
  static String _primaryRole(List<String> roles, Set<String> capabilities) {
    const precedence = <String>[
      'admin',
      'director',
      'finance',
      'hr',
      'manager',
      'employee',
    ];
    for (final role in precedence) {
      if (roles.contains(role)) return role;
    }
    if (capabilities.contains('reimbursement.transition')) return 'finance';
    if (capabilities.contains('user.manage') ||
        capabilities.contains('employee_status.manage')) {
      return 'hr';
    }
    if (capabilities.contains('expense.approve')) {
      if (capabilities.contains('budget.manage') ||
          capabilities.contains('project.create') ||
          capabilities.contains('project.manage')) {
        return 'manager';
      }
      return 'director';
    }
    if (capabilities.any(managementCapabilities.contains)) {
      return 'manager';
    }
    return 'employee';
  }

  final Map<String, bool> employeeActiveStatus = {};

  double currentMonthBudget = 0.0;

  /// Computed from the backend: approved + reimbursed spend this month.
  double currentMonthSpent = 0.0;

  List<ProjectRecord> get myProjects {
    if (currentUserRole == 'employee') {
      final myId = currentUserId.trim();
      final myEmail = currentEmployeeEmail.trim().toLowerCase();
      if (myId.isEmpty) return const <ProjectRecord>[];
      return projects
          .where(
            (p) =>
                p.isActive &&
                p.assignedEmails.any(
                  (id) =>
                      id.trim() == myId || id.trim().toLowerCase() == myEmail,
                ),
          )
          .toList();
    }
    return projects;
  }

  List<ExpenseRecord> get myExpenses {
    final myId = currentUserId.trim();
    if (myId.isEmpty) return const <ExpenseRecord>[];
    // Matched on the employee id: the API scopes expenses by it, and it
    // is the only stable key. The email is a fallback for records that
    // predate the id being present.
    return expenses.where((e) {
      if (e.employeeId.isNotEmpty) return e.employeeId == myId;
      return e.email.trim().toLowerCase() ==
          currentEmployeeEmail.trim().toLowerCase();
    }).toList();
  }

  int get myPendingCount =>
      myExpenses.where((e) => e.status == 'Pending Verification').length;
  int get myApprovedCount =>
      myExpenses.where((e) => e.status == 'Approved').length;
  int get myRejectedCount =>
      myExpenses.where((e) => e.status == 'Rejected').length;

  /// Nullable lookup — a bare `firstWhere` throws on a stale id (row
  /// refetched away), which used to red-screen the details page.
  ExpenseRecord? byIdOrNull(String id) {
    for (final e in expenses) {
      if (e.id == id) return e;
    }
    return null;
  }

  bool isLocked(String id) {
    final expense = byIdOrNull(id);
    if (expense == null) return true; // unknown/gone rows are locked
    final status = expense.status;
    return status == 'Approved' || status == 'Rejected' || status == 'Paid';
  }

  /// Single tolerant date parser. ISO dates *and* ISO datetimes
  /// ("2026-10-20T09:15:00") are handled by `parseLooseDate`; the old
  /// splitter parsed `2026-10-20T09:15:00` as day `20T09:15:00` and
  /// dropped the row.
  DateTime? _parseDate(String dateStr) => parseLooseDate(dateStr);

  /// Public single date parser — dashboards previously kept three
  /// divergent private copies ("5 Jan 2026" legacy vs ISO "2026-01-05").
  DateTime? parseBackendDate(String dateStr) => _parseDate(dateStr);

  bool _isCurrentMonth(String dateStr) {
    final d = _parseDate(dateStr);
    if (d == null) return false;
    final now = DateTime.now();
    return d.month == now.month && d.year == now.year;
  }

  Future<void> fetchBudgetFromBackend() async {
    // Real read now: GET /organizations/{id}/budgets?month=YYYY-MM
    // (computed `spent` included — approved + reimbursed expenses).
    try {
      final orgId = await _orgId();
      if (orgId == null) return;
      final response = await ApiClient.get(
        '/organizations/$orgId/budgets',
        query: {'month': _monthKey(DateTime.now()), 'limit': '100'},
      );
      if (response.statusCode == 200) {
        final items = ApiClient.pageItems(
          response,
        ).cast<Map<String, dynamic>>();
        // The month endpoint returns every budget period overlapping the
        // month (the yearly seed allocation plus any monthly rows).
        // Taking items.first displayed whichever row was created last —
        // the "always ₹7777" bug — so the totals are summed instead.
        // ``spent`` never double-counts: an expense belongs to one
        // project, which belongs to one budget.
        double budgetTotal = 0.0;
        double spentTotal = 0.0;
        for (final item in items) {
          budgetTotal += parseBackendDouble(item['amount']) ?? 0.0;
          spentTotal += parseBackendDouble(item['spent']) ?? 0.0;
        }
        currentMonthBudget = budgetTotal;
        currentMonthSpent = spentTotal;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Network error fetching budgets: $e');
    }
  }

  /// Fetches the project list. Returns `false` when the load failed — the
  /// reason is in [projectsError] for the screens to show.
  Future<bool> fetchProjectsFromBackend() async {
    try {
      final orgId = await _orgId();
      if (orgId == null) {
        projectsLoaded = true;
        notifyListeners();
        return false;
      }
      final response = await ApiClient.get(
        '/organizations/$orgId/projects',
        query: {'limit': '100'},
      );
      if (response.statusCode == 200) {
        final projectsJson = ApiClient.pageItems(response);
        projects = projectsJson
            .map((data) => ProjectRecord.fromJson(data as Map<String, dynamic>))
            .toList();
        projectsError = null;
        notifyListeners();
        return true;
      } else {
        projectsError =
            "Couldn't load projects (server ${response.statusCode}).";
        return false;
      }
    } catch (e) {
      projectsError = "Couldn't load projects. Check your connection.";
      debugPrint('Network error fetching projects: $e');
      return false;
    } finally {
      notifyListeners();
      projectsLoaded = true;
    }
  }

  Future<bool> fetchProjectRequestsFromBackend() async {
    try {
      final response = await ApiClient.get(
        '/access-requests',
        query: {'status': 'pending', 'limit': '100'},
      );
      if (response.statusCode == 200) {
        final requestsJson = ApiClient.pageItems(response);
        projectRequests = requestsJson.map((raw) {
          final r = raw as Map<String, dynamic>;
          return {
            'access_request_id': r['access_request_id']?.toString() ?? '',
            'email': r['employee_email']?.toString() ?? '',
            'name': r['employee_name']?.toString() ?? 'Unknown',
            'projectId': r['project_id']?.toString() ?? '',
            'projectName': r['project_name']?.toString() ?? '',
          };
        }).toList();
        notifyListeners();
        return true;
      }
      debugPrint('Failed to load access requests: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('Network error fetching project requests: $e');
      return false;
    }
  }

  /// Returns true when the backend confirmed the access request. The
  /// caller decides what to tell the user (false = request failed).
  Future<bool> submitProjectAccessRequest(String projectId) async {
    try {
      final response = await ApiClient.post(
        '/projects/$projectId/access-requests',
        {},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchProjectRequestsFromBackend();
        return true;
      }
      debugPrint('submitProjectAccessRequest failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error submitting project access request: $e');
    }
    return false;
  }

  /// Registers a new account via POST /auth/register (no org auto-join in
  /// §49; the role field is informational). Returns true on success.
  Future<bool> assignEmployeeCredentials({
    required String employeeId,
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();
    final cleanName = name.trim();
    try {
      final response = await ApiClient.post('/auth/register', {
        'name': cleanName,
        'email': cleanEmail,
        'password': cleanPassword,
      }, auth: false);
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchUsersFromBackend();
        return true;
      }
      debugPrint('assignEmployeeCredentials failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error assigning employee credentials: $e');
    }
    return false;
  }

  /// Real project members (GET /projects/{id}/members, §49 24a), keyed by
  /// project id. Populated on demand by the members screen.
  Map<String, List<ProjectMemberRecord>> projectMembersByProject = {};
  bool projectMembersLoading = false;

  /// Loads a project's actual member list from the backend.
  Future<void> fetchProjectMembersFromBackend(String projectId) async {
    projectMembersLoading = true;
    notifyListeners();
    try {
      final response = await ApiClient.get(
        '/projects/$projectId/members',
        query: {'limit': '100'},
      );
      if (response.statusCode == 200) {
        final items = ApiClient.pageItems(response);
        projectMembersByProject[projectId] = items.map((raw) {
          final map = raw as Map<String, dynamic>;
          return ProjectMemberRecord.fromJson(map);
        }).toList();
        notifyListeners();
      } else {
        debugPrint('fetchProjectMembers failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Network error fetching project members: $e');
    } finally {
      projectMembersLoading = false;
      notifyListeners();
    }
  }

  /// PATCH /organizations/{orgId}/budgets/{budgetId} — the project's
  /// referenced budget row. Refreshes both projects and budgets on success.
  Future<bool> updateProjectBudget(String projectId, double newBudget) async {
    if (newBudget <= 0) return false;
    String? budgetId;
    for (final p in projects) {
      if (p.id == projectId) budgetId = p.budgetId;
    }
    if (budgetId == null) {
      debugPrint('updateProjectBudget: project $projectId has no budget_id.');
      return false;
    }
    try {
      final orgId = await _orgId();
      if (orgId == null) return false;
      final response = await ApiClient.patch(
        '/organizations/$orgId/budgets/$budgetId',
        {'amount': newBudget},
      );
      if (response.statusCode == 200) {
        await Future.wait([
          fetchProjectsFromBackend(),
          fetchBudgetFromBackend(),
        ]);
        return true;
      }
      debugPrint('updateProjectBudget failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error updating project budget: $e');
    }
    return false;
  }

  /// POST /projects/{id}/members for each selected employee (§49 24b).
  /// Returns true only when every add was accepted by the backend.
  Future<bool> addMembersToProject(
    String projectId,
    List<String> newEmployeeIds,
  ) async {
    var allOk = true;
    for (final rawId in newEmployeeIds) {
      final employeeId = int.tryParse(rawId);
      if (employeeId == null) {
        debugPrint(
          'addMembersToProject: "$rawId" is not a numeric employee id.',
        );
        allOk = false;
        continue;
      }
      try {
        final response = await ApiClient.post('/projects/$projectId/members', {
          'employee_id': employeeId,
        });
        if (response.statusCode != 200 && response.statusCode != 201) {
          debugPrint(
            'addMembersToProject($employeeId) failed: ${response.statusCode}',
          );
          allOk = false;
        }
      } catch (e) {
        debugPrint('Error adding member $employeeId: $e');
        allOk = false;
      }
    }
    if (allOk) await fetchProjectsFromBackend(); // member_count refresh
    return allOk;
  }

  /// DELETE /projects/{id}/members/{employeeId} (§49 24c).
  Future<bool> removeMemberFromProject(
    String projectId,
    String employeeId,
  ) async {
    try {
      final response = await ApiClient.delete(
        '/projects/$projectId/members/$employeeId',
      );
      if (response.statusCode == 204 || response.statusCode == 200) {
        await fetchProjectsFromBackend();
        return true;
      }
      debugPrint('removeMemberFromProject failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error removing member: $e');
    }
    return false;
  }

  /// Approve or reject a project-access request (GET queue rows carry
  /// `access_request_id`). Approval inserts the employee into the
  /// request's project via project_members. Returns true on success.
  Future<bool> decideProjectAccess(
    String requestId,
    bool approve, {
    String? comment,
  }) async {
    try {
      final response = await ApiClient.post(
        '/access-requests/$requestId/${approve ? 'approve' : 'reject'}',
        {'comment': comment},
      );
      if (response.statusCode == 200) {
        await fetchProjectRequestsFromBackend();
        return true;
      }
      debugPrint('decideProjectAccess failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error deciding project access: $e');
    }
    return false;
  }

  /// PATCH /projects/{id} is_active. Returns true when the backend
  /// confirmed (list is refreshed); false leaves the UI unchanged.
  Future<bool> toggleProjectActiveStatus(
    String projectId,
    bool makeActive,
  ) async {
    try {
      final response = await ApiClient.patch('/projects/$projectId', {
        'is_active': makeActive,
      });
      if (response.statusCode == 200) {
        await fetchProjectsFromBackend();
        return true;
      }
      debugPrint('toggleProjectActiveStatus failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error updating project status: $e');
    }
    return false;
  }

  bool isEmployeeAssignedToAnyProject(String identifier) {
    final cleanId = identifier.trim().toLowerCase();
    for (var project in projects) {
      for (var assignedId in project.assignedEmails) {
        if (assignedId.trim().toLowerCase() == cleanId) {
          return true;
        }
      }
    }
    return false;
  }

  double getProjectBurnAmount(String projectName) {
    return expenses
        .where(
          (e) =>
              e.projectName == projectName &&
              (e.status == 'Approved' || e.status == 'Paid'),
        )
        .fold(0.0, (totalAmount, e) => totalAmount + e.amount);
  }

  /// Creates the project (referencing a budget for the current month)
  /// and adds the selected employees to it. Returns null on success or an
  /// error message.
  Future<String?> createProject(
    String name,
    double budget,
    List<String> employeeIds,
  ) async {
    final orgId = await _orgId();
    if (orgId == null) return 'You are not signed in to an organization.';
    try {
      // Reuse the organization's budget for this month when there is one.
      // Creating a second budget for the same month left the two rows
      // competing, and the newest one won — so creating a project
      // silently replaced the organization's monthly budget.
      final existing = await _budgetIdForMonth(DateTime.now());
      int? budgetId = existing;

      if (budgetId == null) {
        final now = DateTime.now();
        final start = DateTime(
          now.year,
          now.month,
          1,
        ).toIso8601String().split('T').first;
        final end = DateTime(
          now.year,
          now.month + 1,
          1,
        ).subtract(const Duration(days: 1)).toIso8601String().split('T').first;
        final budgetRes = await ApiClient.post(
          '/organizations/$orgId/budgets',
          {'amount': budget, 'start_date': start, 'end_date': end},
        );
        if (budgetRes.statusCode != 200 && budgetRes.statusCode != 201) {
          debugPrint('createProject budget failed: ${budgetRes.statusCode}');
          return 'Could not create the monthly budget (${budgetRes.statusCode}).';
        }
        budgetId =
            (json.decode(budgetRes.body) as Map<String, dynamic>)['budget_id']
                as int?;
      }

      final response = await ApiClient.post('/organizations/$orgId/projects', {
        'budget_id': budgetId,
        'name': name,
      });
      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('createProject project failed: ${response.statusCode}');
        return 'Could not create the project (${response.statusCode}).';
      }
      final projectId =
          (json.decode(response.body) as Map<String, dynamic>)['project_id']
              as int?;

      // The selected employees were silently dropped before, so every
      // project came out empty and nobody could work in it.
      if (projectId != null && employeeIds.isNotEmpty) {
        for (final rawId in employeeIds) {
          final employeeId = int.tryParse(rawId.trim());
          if (employeeId == null) continue;
          final added = await ApiClient.post('/projects/$projectId/members', {
            'employee_id': employeeId,
          });
          if (added.statusCode != 200 && added.statusCode != 201) {
            debugPrint(
              'createProject member $employeeId failed: ${added.statusCode}',
            );
          }
        }
      }

      await fetchProjectsFromBackend();
      return null;
    } catch (e) {
      debugPrint('Error creating project: $e');
      return 'Network error while creating the project.';
    }
  }

  /// The id of the organization's budget covering [month], if any.
  Future<int?> _budgetIdForMonth(DateTime month) async {
    try {
      final orgId = await _orgId();
      if (orgId == null) return null;
      final response = await ApiClient.get(
        '/organizations/$orgId/budgets',
        query: {'month': _monthKey(month), 'limit': '5'},
      );
      if (response.statusCode != 200) return null;
      final items = ApiClient.pageItems(response).cast<Map<String, dynamic>>();
      if (items.isEmpty) return null;
      return int.tryParse(items.first['budget_id']?.toString() ?? '');
    } catch (e) {
      debugPrint('Network error reading budget id for month: $e');
      return null;
    }
  }

  /// True when the signed-in user submitted the expense themselves.
  bool _isOwnExpense(ExpenseRecord e) {
    final String uploaderEmail = e.email.trim().toLowerCase();
    if (uploaderEmail.isEmpty) return false;
    return uploaderEmail == currentEmployeeEmail.trim().toLowerCase() ||
        uploaderEmail == currentManagerEmail.trim().toLowerCase() ||
        (currentUserId.isNotEmpty && e.employeeId == currentUserId);
  }

  /// Review queue visibility: you never review your own request. KPI
  /// counts intentionally do *not* use this filter — the dashboard used
  /// to hide the manager's own claims from the totals while "All
  /// requests" showed them, so the two screens disagreed.
  bool _isReviewable(ExpenseRecord e) => !_isOwnExpense(e);

  /// Public view of [_isOwnExpense] — the claim detail screen needs it
  /// to lock the approval buttons on your own submissions.
  bool isOwnExpense(ExpenseRecord e) => _isOwnExpense(e);

  int get pendingCount => expenses
      .where(
        (e) => e.status == 'Pending Verification' && _isCurrentMonth(e.date),
      )
      .length;
  int get approvedCount => expenses
      .where((e) => e.status == 'Approved' && _isCurrentMonth(e.date))
      .length;
  int get rejectedCount => expenses
      .where((e) => e.status == 'Rejected' && _isCurrentMonth(e.date))
      .length;

  double get currentMonthBurnAmount {
    double total = 0;
    for (var e in expenses) {
      if ((e.status == 'Approved' || e.status == 'Paid') &&
          _isCurrentMonth(e.date)) {
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

  List<Map<String, dynamic>> get urgentRequests {
    // Only approvers have a review queue, and never their own claims.
    if (!canApproveExpenses) return const <Map<String, dynamic>>[];
    final pending = expenses
        .where((e) => e.status == 'Pending Verification' && _isReviewable(e))
        .toList();

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
      urgent.add({
        'expense': stale,
        'reason': 'SLA Breach: $maxDays Days Old',
        'isSla': true,
      });
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
      urgent.add({
        'expense': high,
        'reason': 'High Value Request',
        'isSla': false,
      });
    }

    return urgent;
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
    _loadThemePreference();
    notifyListeners();
  }

  void setEmployeeName(String name) {
    currentEmployeeName = name;
    notifyListeners();
  }

  String _deriveName(String email, {required String fallback}) {
    final localPart = email.split('@').first;
    final parts = localPart.split(RegExp(r'[._]+')).where((p) => p.isNotEmpty);
    final name = parts
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
    return name.trim().isEmpty ? fallback : name;
  }

  /// PATCH /users/{id} with the new display name. Returns true only when
  /// the backend confirmed it — the callers used to show "updated"
  /// unconditionally, so a failed PATCH claimed success and then
  /// reverted on the next sign-in.
  Future<bool> updateName(String newName, bool isManager) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;
    try {
      // The backend does support this: PATCH /users/{employee_id} with a
      // name. Without the call the new name was shown as saved and then
      // reverted on the next sign-in.
      final employeeId = int.tryParse(currentUserId.trim());
      bool ok = false;
      if (employeeId != null) {
        final response = await ApiClient.patch('/users/$employeeId', {
          'name': trimmed,
        });
        if (response.statusCode != 200) {
          debugPrint('Name update rejected: ${response.statusCode}');
          return false;
        }
        final body = json.decode(response.body) as Map<String, dynamic>;
        currentUserName = body['name']?.toString() ?? trimmed;
        ok = true;
      } else {
        currentUserName = trimmed;
        ok = true;
      }
      currentManagerName = trimmed;
      currentEmployeeName = trimmed;
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint('Name update error: $e');
      return false;
    }
  }

  String getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  /// Fetches the signed-in user's expense claims. Returns `false` when the
  /// load failed — the reason is in [expensesError] for the screens to show.
  Future<bool> fetchExpensesFromBackend() async {
    try {
      final page = await _fetchPage('/expenses');
      if (page.failed) {
        expensesError =
            "Couldn't load expense claims (server error). Try again.";
        notifyListeners();
        return false;
      }
      expenses = page.items.map(ExpenseRecord.fromJson).toList();
      expensesCursor = page.nextCursor;
      expensesError = null;
      notifyListeners();
      return true;
    } catch (e) {
      expensesError = "Couldn't load expense claims. Check your connection.";
      debugPrint('Network error fetching expenses: $e');
      notifyListeners();
      return false;
    } finally {
      expensesLoaded = true;
    }
  }

  /// Loads the next page of expenses and appends it.
  ///
  /// The list used to stop at a hundred rows, so an organization with
  /// more than a hundred expenses silently lost the rest.
  Future<void> loadMoreExpenses() async {
    final cursor = expensesCursor;
    if (cursor == null || expensesLoadingMore) return;
    expensesLoadingMore = true;
    try {
      final page = await _fetchPage('/expenses', cursor: cursor);
      expenses = [
        ...expenses,
        ...page.items.map((data) => ExpenseRecord.fromJson(data)),
      ];
      expensesCursor = page.nextCursor;
      notifyListeners();
    } catch (e) {
      debugPrint('Network error loading more expenses: $e');
    } finally {
      expensesLoadingMore = false;
    }
  }

  /// Whether another page of expenses is waiting.
  bool get hasMoreExpenses => expensesCursor != null;

  /// The cursor of the next page of expenses, or null when the list is
  /// exhausted.
  String? expensesCursor;

  /// Whether a page of expenses is being fetched.
  bool expensesLoadingMore = false;

  /// One page of a cursor-paginated list.
  ///
  /// The API pages by cursor: it returns the rows and the cursor of the
  /// next page, or nothing when the list is exhausted.
  Future<_Page> _fetchPage(
    String path, {
    Map<String, String>? query,
    String? cursor,
  }) async {
    final parameters = <String, String>{...?query, 'limit': '50'};
    if (cursor != null) parameters['cursor'] = cursor;
    final response = await ApiClient.get(path, query: parameters);
    if (response.statusCode != 200) {
      debugPrint('Failed to load $path: ${response.statusCode}');
      return const _Page([], null, failed: true);
    }
    return _Page(
      ApiClient.pageItems(response).cast<Map<String, dynamic>>(),
      ApiClient.pageCursor(response),
    );
  }

  Future<void> loadCurrentUserRole(String email) async {
    // The role and the capabilities come from the server — they are set
    // by setUserAccess when the profile is read. They are not guessed
    // from a local flag any more: a manager is not the same thing as
    // the owner of an organization.
    await _loadThemePreference();
    notifyListeners();
  }

  String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Sum of the amounts of every budget period overlapping [month] —
  /// "money the organization made available that month", which is what
  /// a report should show. Deliberately distinct from
  /// [getBudgetForMonth]: the allocation screen edits the single
  /// explicit monthly row, and mixing the yearly seed allocation into
  /// that edit box invited saving a second overlapping row instead of
  /// editing one.
  ///
  /// Returns `null` when the month could not be read. The old "return
  /// 0.0 on failure" made a network error print as a month with no
  /// allocation and a negative variance — spend against a budget that
  /// was never loaded looked like overspend.
  Future<double?> getBudgetCoverageForMonth(DateTime month) async {
    try {
      final orgId = await _orgId();
      if (orgId == null) return null;
      final response = await ApiClient.get(
        '/organizations/$orgId/budgets',
        query: {'month': _monthKey(month), 'limit': '100'},
      );
      if (response.statusCode != 200) return null;
      double total = 0.0;
      for (final item in ApiClient.pageItems(
        response,
      ).cast<Map<String, dynamic>>()) {
        total += parseBackendDouble(item['amount']) ?? 0.0;
      }
      return total;
    } catch (e) {
      debugPrint('Network error reading budget coverage for month: $e');
      return null;
    }
  }

  Future<double?> getBudgetForMonth(DateTime month) async {
    // Real read. Only the *explicit monthly allocation row* for the
    // month counts here — the row this flow itself creates (first day
    // to last day). Budget periods that merely overlap the month (the
    // yearly seed allocation) are ignored: showing them in the edit box
    // invited saving a second overlapping row instead of editing one.
    try {
      final orgId = await _orgId();
      if (orgId != null) {
        final response = await ApiClient.get(
          '/organizations/$orgId/budgets',
          query: {'month': _monthKey(month), 'limit': '100'},
        );
        if (response.statusCode == 200) {
          final monthStart = DateTime(
            month.year,
            month.month,
            1,
          ).toIso8601String().split('T').first;
          final items = ApiClient.pageItems(
            response,
          ).cast<Map<String, dynamic>>();
          double total = 0.0;
          var found = false;
          for (final item in items) {
            if ((item['start_date']?.toString() ?? '') == monthStart) {
              found = true;
              total += parseBackendDouble(item['amount']) ?? 0.0;
            }
          }
          if (found) return total;
          return null; // no allocation row for that month — honest null
        }
      }
    } catch (e) {
      debugPrint('Network error reading budget for month: $e');
    }
    return null;
  }

  Future<String?> setBudgetForMonth(DateTime month, double amount) async {
    if (amount <= 0) return 'Budget must be greater than zero.';
    try {
      final orgId = await _orgId();
      if (orgId == null) return 'Not signed in to an organization.';
      final start = DateTime(
        month.year,
        month.month,
        1,
      ).toIso8601String().split('T').first;
      final end = DateTime(
        month.year,
        month.month + 1,
        1,
      ).subtract(const Duration(days: 1)).toIso8601String().split('T').first;
      // Editing an existing allocation updates that row. POSTing a new
      // one stacked a duplicate monthly row on every save, and the
      // dashboard's summed totals drifted upward each time.
      int? existingId;
      try {
        final existing = await ApiClient.get(
          '/organizations/$orgId/budgets',
          query: {'month': _monthKey(month), 'limit': '100'},
        );
        if (existing.statusCode == 200) {
          for (final item in ApiClient.pageItems(
            existing,
          ).cast<Map<String, dynamic>>()) {
            if ((item['start_date']?.toString() ?? '') == start) {
              existingId = (item['budget_id'] as num?)?.toInt();
              break;
            }
          }
        }
      } catch (_) {
        // Listing failed — fall through to the POST, worst case a row duplicates.
      }
      final response = existingId != null
          ? await ApiClient.patch('/organizations/$orgId/budgets/$existingId', {
              'amount': amount,
            })
          : await ApiClient.post('/organizations/$orgId/budgets', {
              'amount': amount,
              'start_date': start,
              'end_date': end,
            });
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchBudgetFromBackend();
        return null;
      } else {
        return 'Server error setting budget: ${response.statusCode}';
      }
    } catch (e) {
      return 'Failed to save budget: $e';
    }
  }

  Future<void> fetchEmployeeStatusFromBackend() async {
    // The canonical per-user status log is GET /users/{id}/statuses, but
    // the account state the UI shows comes from the directory listing.
    // Re-reading the directory is what keeps the toggle honest — the
    // old version was a no-op, so the list was never refreshed.
    await fetchUsersFromBackend();
  }

  /// Whether the employee is active.
  ///
  /// Read from the backend's `account_status`. The previous helper only
  /// consulted a local map that was never seeded from the API, so every
  /// employee was shown as ACTIVE however the server had them.
  bool isEmployeeActive(String email) {
    final target = email.trim().toLowerCase();
    for (final user in usersList) {
      if ((user['email'] ?? '').trim().toLowerCase() == target) {
        return (user['account_status'] ?? 'active') == 'active';
      }
    }
    return employeeActiveStatus[email] ?? true;
  }

  List<Map<String, String>> get allEmployees {
    if (usersList.isNotEmpty) {
      final sorted = List<Map<String, String>>.from(usersList);
      sorted.sort((a, b) => a['name']!.compareTo(b['name']!));
      return sorted;
    }
    final map = <String, Map<String, String>>{};
    for (final e in expenses) {
      map[e.email] = {'email': e.email, 'name': e.name, 'id': e.id};
    }
    final list = map.values.toList();
    list.sort((a, b) => a['name']!.compareTo(b['name']!));
    return list;
  }

  /// Real toggle: POST /users/{employee_id}/statuses (admin). The backend
  /// auto-closes the currently open status record and opens the new one.
  /// Optimistic local update; rolls back if the call fails. 409 (target
  /// state already open) counts as success — the UI wants that state.
  /// Returns true when the backend confirms the state, false when the
  /// optimistic value rolled back — the caller owns what it tells the user.
  Future<bool> setEmployeeActive(String email, bool isActive) async {
    final previous = employeeActiveStatus[email] ?? true;
    if (previous == isActive) return true;
    employeeActiveStatus[email] = isActive;
    notifyListeners();

    void rollback() {
      employeeActiveStatus[email] = previous;
      notifyListeners();
    }

    try {
      String? id;
      if (usersList.isEmpty) await fetchUsersFromBackend();
      for (final user in usersList) {
        if (user['email'] == email) {
          final parsed = int.tryParse(user['id'] ?? '');
          if (parsed != null) id = parsed.toString();
          break;
        }
      }
      if (id == null) {
        debugPrint('setEmployeeActive: no backend employee id for $email.');
        rollback();
        return false;
      }
      final response = await ApiClient.post('/users/$id/statuses', {
        'status': isActive ? 'active' : 'inactive',
      });
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Persisted — keep the optimistic value and mirror it into the
        // directory the UI reads its status from.
        for (final user in usersList) {
          if (user['email'] == email) {
            user['account_status'] = isActive ? 'active' : 'inactive';
          }
        }
        return true;
      } else if (response.statusCode == 409) {
        debugPrint(
          'setEmployeeActive: already in that status (409 treated as success).',
        );
        return true;
      } else {
        rollback();
        debugPrint('setEmployeeActive failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      rollback();
      debugPrint('setEmployeeActive error: $e');
      return false;
    }
  }

  Future<String?> submitExpense({
    required String type,
    required double amount,
    required String date,
    required String description,
    required DateTime rawDate,
    Uint8List? receiptBytes,
    String? projectId,
  }) async {
    // The dropdown is keyed by backend id: two projects may share a
    // display name, and a name-keyed selection both crashed the
    // DropdownButton assertion and could quietly tag the expense to the
    // wrong project before that.
    if (projectId != null && projectId.isNotEmpty) {
      final targetProject = projects.firstWhere(
        (p) => p.id == projectId,
        orElse: () => ProjectRecord(
          id: '',
          name: '',
          budget: 0,
          assignedEmails: [],
          isActive: true,
        ),
      );
      if (!targetProject.isActive) {
        return 'Cannot submit expenses to a deactivated project.';
      }
    }
    if (type.trim().isEmpty) return 'Please select an expense type.';
    if (description.trim().isEmpty) return 'Please enter a description.';
    if (amount <= 0) return 'Amount must be a positive, non-zero value.';
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(rawDate.year, rawDate.month, rawDate.day);
    if (dateOnly.isAfter(todayOnly)) return 'Date cannot be in the future.';
    if (receiptBytes != null && receiptBytes.lengthInBytes > 5 * 1024 * 1024) {
      return 'Receipt image is too large. Max 5MB.';
    }

    try {
      // Resolve backend IDs from cached lists (names are UI labels only).
      final orgId = await _orgId();
      if (orgId == null) return 'Not signed in to an organization.';
      int? resolvedProjectId;
      if (projectId != null && projectId.isNotEmpty) {
        final match = projects.where((p) => p.id == projectId).toList();
        if (match.isEmpty) {
          return 'Selected project is not synced from the backend.';
        }
        resolvedProjectId = int.tryParse(match.first.id);
        if (resolvedProjectId == null) {
          return 'Selected project has an invalid backend ID.';
        }
      } else {
        // General expenses still need a project in v1 — pick the first active one.
        final active = projects.where((p) => p.isActive).toList();
        if (active.isEmpty) {
          return 'No synced project available — ask an admin to create one.';
        }
        resolvedProjectId = int.tryParse(active.first.id);
        if (resolvedProjectId == null) {
          return 'Synced project has an invalid backend ID.';
        }
      }
      final expenseTypeId = await _resolveExpenseTypeId(orgId, type);
      if (expenseTypeId == null) {
        return 'Expense type "$type" is not synced from the backend.';
      }
      if (receiptBytes != null &&
          receiptBytes.lengthInBytes > 5 * 1024 * 1024) {
        return 'Receipt image is too large. Max 5MB.';
      }
      final expenseDate =
          '${rawDate.year.toString().padLeft(4, '0')}-${rawDate.month.toString().padLeft(2, '0')}-${rawDate.day.toString().padLeft(2, '0')}';
      final fields = {
        'project_id': resolvedProjectId.toString(),
        'expense_type_id': expenseTypeId.toString(),
        'amount': amount.toString(),
        'expense_date': expenseDate,
        // The description used to be validated and then dropped: the
        // backend had nowhere to put it.
        'description': description.trim(),
      };
      final files = <http.MultipartFile>[];
      if (receiptBytes != null) {
        files.add(
          http.MultipartFile.fromBytes(
            'files',
            receiptBytes,
            filename: 'receipt.jpg',
          ),
        );
      }
      final streamed = await ApiClient.postMultipart(
        '/expenses',
        fields: fields,
        files: files,
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchExpensesFromBackend();
        return null;
      } else {
        return _errorMessage(response, 'The expense could not be submitted.');
      }
    } on TimeoutException {
      return 'The server did not respond in time. Please try again.';
    } catch (e) {
      debugPrint('Detailed Expense Upload Error: $e');
      return 'Upload failed. Please check your connection and try again.';
    }
  }

  /// The backend's own error message, when it sent one. Falls back to
  /// [fallback] so the user never sees a raw status code or an
  /// internal exception.
  static String _errorMessage(http.Response response, String fallback) {
    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic>) {
        final error = body['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message']?.toString();
          if (message != null && message.isNotEmpty) return message;
        }
      }
    } catch (_) {
      // Not a JSON error envelope — fall through to the generic message.
    }
    return fallback;
  }

  /// Look up the backend expense-type ID by name (refreshes the cache first).
  Future<int?> _resolveExpenseTypeId(int orgId, String name) async {
    try {
      final response = await ApiClient.get(
        '/organizations/$orgId/expense-types',
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        for (final item in data) {
          final m = item as Map<String, dynamic>;
          if ((m['name']?.toString().toLowerCase() ?? '') ==
              name.trim().toLowerCase()) {
            return (m['expense_type_id'] as num?)?.toInt();
          }
        }
      }
    } catch (e) {
      debugPrint('Expense-type lookup failed: $e');
    }
    return null;
  }

  /// Optimistic approve with rollback. Returns true when the backend
  /// confirmed the approval (notification only fires on success).
  Future<bool> approve(String id) async {
    final expense = byIdOrNull(id);
    if (expense == null || isLocked(id)) return false;
    final expenseId = int.tryParse(
      expense.firestoreDocId.isNotEmpty ? expense.firestoreDocId : id,
    );
    if (expenseId == null) {
      debugPrint('approve: invalid backend expense id for $id');
      return false;
    }
    final prevStatus = expense.status;
    expense.status = 'Approved';
    notifyListeners();
    try {
      final response = await ApiClient.post('/expenses/$expenseId/approve', {});
      if (response.statusCode == 200) {
        await fetchExpensesFromBackend();
        _addNotification(
          expense.id,
          expense.name,
          'Expense request of ${expense.amountFormatted} has been approved.',
          'approved',
        );
        return true;
      }
      expense.status = prevStatus;
      notifyListeners();
      debugPrint('approve failed: ${response.statusCode}');
    } catch (e) {
      expense.status = prevStatus;
      notifyListeners();
      debugPrint('approve error: $e');
    }
    return false;
  }

  /// Optimistic reject with rollback. Returns true when the backend
  /// confirmed the rejection. Notification only fires on success.
  Future<bool> reject(String id, {required String reason}) async {
    final expense = byIdOrNull(id);
    if (expense == null || isLocked(id)) return false;
    final expenseId = int.tryParse(
      expense.firestoreDocId.isNotEmpty ? expense.firestoreDocId : id,
    );
    if (expenseId == null) {
      debugPrint('reject: invalid backend expense id for $id');
      return false;
    }
    final prevStatus = expense.status;
    expense.status = 'Rejected';
    expense.rejectionReason = reason;
    notifyListeners();
    try {
      final response = await ApiClient.post('/expenses/$expenseId/reject', {
        'comments': reason,
      });
      if (response.statusCode == 200) {
        await fetchExpensesFromBackend();
        _addNotification(
          expense.id,
          expense.name,
          'Expense request of ${expense.amountFormatted} was rejected.',
          'rejected',
        );
        return true;
      }
      expense.status = prevStatus;
      notifyListeners();
      debugPrint('reject failed: ${response.statusCode}');
    } catch (e) {
      expense.status = prevStatus;
      notifyListeners();
      debugPrint('reject error: $e');
    }
    return false;
  }

  /// POST /expenses/{id}/request-info (§49 32a) — the manager's message
  /// is persisted on the expense and shown to the employee.
  Future<bool> requestMoreInfo(String id, {required String message}) async {
    final expense = byIdOrNull(id);
    if (expense == null) return false;
    final expenseId = int.tryParse(
      expense.firestoreDocId.isNotEmpty ? expense.firestoreDocId : id,
    );
    if (expenseId == null) {
      debugPrint('requestMoreInfo: invalid backend expense id for $id');
      return false;
    }
    try {
      final response = await ApiClient.post(
        '/expenses/$expenseId/request-info',
        {'comments': message},
      );
      if (response.statusCode == 200) {
        await fetchExpensesFromBackend();
        _addNotification(
          expense.id,
          expense.name,
          'Additional details requested for ${expense.amountFormatted}.',
          'info',
        );
        return true;
      }
      debugPrint('requestMoreInfo failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error requesting more info: $e');
    }
    return false;
  }

  /// POST /expenses/{id}/resubmit (§49 32b) — an employee answers an info
  /// request and returns the expense to the pending queue.
  ///
  /// [response] carries the answer to the manager's question. The
  /// endpoint used to take no body at all, so the information the
  /// manager asked for could never actually be sent.
  Future<bool> resubmitExpense(String id, {String? response}) async {
    final expense = byIdOrNull(id);
    if (expense == null) return false;
    final expenseId = int.tryParse(
      expense.firestoreDocId.isNotEmpty ? expense.firestoreDocId : id,
    );
    if (expenseId == null) return false;
    try {
      final answer = response?.trim();
      final apiResponse = await ApiClient.post(
        '/expenses/$expenseId/resubmit',
        answer == null || answer.isEmpty
            ? <String, dynamic>{}
            : {'response': answer},
      );
      if (apiResponse.statusCode == 200) {
        await fetchExpensesFromBackend();
        return true;
      }
      debugPrint('resubmitExpense failed: ${apiResponse.statusCode}');
    } catch (e) {
      debugPrint('Error resubmitting expense: $e');
    }
    return false;
  }

  Future<String?> markPaid(
    String id,
    String transactionId, {
    Uint8List? receiptBytes,
  }) async {
    final cleanTxId = transactionId.trim();
    if (cleanTxId.isEmpty) {
      return 'Transaction ID is compulsory to mark an expense as paid.';
    }
    final expense = byIdOrNull(id);
    if (expense == null) return 'Record no longer available.';
    final expenseId = int.tryParse(
      expense.firestoreDocId.isNotEmpty ? expense.firestoreDocId : id,
    );
    if (expenseId == null) return 'Invalid backend expense id.';
    try {
      // 1. Create reimbursement (expense must be approved first).
      var create = await ApiClient.post(
        '/expenses/$expenseId/reimbursement',
        {},
      );
      if (create.statusCode != 200 && create.statusCode != 201) {
        return 'Server error creating reimbursement: ${create.statusCode}';
      }
      final reimbursementId =
          (json.decode(create.body)
              as Map<String, dynamic>)['reimbursement_id'];
      // 2. pending -> processing -> paid (paid requires payment_reference).
      var step = await ApiClient.post(
        '/reimbursements/$reimbursementId/transition',
        {'target_status': 'processing'},
      );
      if (step.statusCode != 200) return 'Server error: ${step.statusCode}';
      step = await ApiClient.post(
        '/reimbursements/$reimbursementId/transition',
        {'target_status': 'paid', 'payment_reference': cleanTxId},
      );
      if (step.statusCode != 200) return 'Server error: ${step.statusCode}';
      // 3. The payment receipt. It used to be read into memory and then
      //    dropped, while the UI claimed it had been attached.
      if (receiptBytes != null) {
        final receipt = await ApiClient.postMultipart(
          '/reimbursements/$reimbursementId/receipt',
          files: [
            http.MultipartFile.fromBytes(
              'file',
              receiptBytes,
              filename: 'payment-receipt.jpg',
            ),
          ],
        );
        if (receipt.statusCode != 200) {
          debugPrint(
            'markPaid: payment receipt upload failed (${receipt.statusCode})',
          );
        }
      }
      await fetchExpensesFromBackend();
      _addNotification(
        expense.id,
        expense.name,
        'Payment for ₹${expense.amount.toStringAsFixed(2)} has been processed.',
        'paid',
      );
      return null;
    } catch (e) {
      return 'Payment failed. Please try again.';
    }
  }

  void _addNotification(
    String expenseId,
    String title,
    String subtitle,
    String type,
  ) {
    final now = DateTime.now();
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    int hr = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final timeString =
        'Today, $hr:${now.minute.toString().padLeft(2, '0')} $ampm';

    notifications.insert(
      0,
      AppNotification(
        expenseId: expenseId,
        title: title,
        subtitle: subtitle,
        time: timeString,
        type: type,
      ),
    );
    notifyListeners();
  }
}
