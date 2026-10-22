// The single portal shell — the app has one navigation scaffold whose
// tabs are built from what the server says the signed-in user may do.
//
// There is no "management portal" and "employee portal" any more; the
// person who can approve expenses gets the review queue, the person
// who can move reimbursements gets the payout screens, and a plain
// employee gets exactly the tabs they need. The one thing the role
// name still decides is which dashboard the first tab renders — a
// convenience, not an authority.
//
// Navigation adapts to the window: a bottom bar with at most four
// destinations plus a "More" sheet on phones, and a rail on wide
// screens. Both are built from the same capability-gated entry list, so
// a grant that appears or disappears mid-session cannot strand the user
// on a tab that no longer exists.
import 'package:flutter/material.dart';

import 'package:ats_onework/employee/add_expense_screen.dart';
import 'package:ats_onework/employee/employee_dashboard.dart';
import 'package:ats_onework/employee/employee_profile_screen.dart';
import 'package:ats_onework/employee/employee_projects.dart';
import 'package:ats_onework/employee/employee_wait_screen.dart';
import 'package:ats_onework/employee/my_requests_screen.dart';
import 'package:ats_onework/management/access_management_screen.dart';
import 'package:ats_onework/management/audit_log_screen.dart';
import 'package:ats_onework/management/budget_allocation_screen.dart';
import 'package:ats_onework/management/director_dashboard.dart';
import 'package:ats_onework/management/employee_management_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/finance_dashboard.dart';
import 'package:ats_onework/management/finance_hub_screens.dart';
import 'package:ats_onework/management/management_projects_screen.dart';
import 'package:ats_onework/management/manager_dashboard.dart';
import 'package:ats_onework/management/manager_profile.dart';
import 'package:ats_onework/management/manager_requests_screen.dart';
import 'package:ats_onework/management/notifications_hub.dart';
import 'package:ats_onework/shared/ats_logo.dart';
import 'package:ats_onework/ui/tokens.dart';

/// The tabs the shell can show. The visible set is capability-gated per
/// user, so navigation happens by tab identity, never by index.
enum PortalTab {
  dashboard,
  requests,
  myRequests,
  upload,
  projects,
  toPay,
  paid,
  access,
  audit,
  profile,
}

/// A user whose management duties are the payout lifecycle: they hold
/// `reimbursement.transition` but neither access administration nor any
/// project/budget building capability — the finance shape, whether or
/// not their role is named "finance". Without the negations the
/// organization admin (who holds the transition capability *and* everything
/// else) would be read as finance and lose the manager dashboard.
bool payoutPurePersona(ExpenseStore store) =>
    store.canPayReimbursements &&
    !store.canManageAccess &&
    !store.can('project.create') &&
    !store.can('project.manage') &&
    !store.can('budget.manage');

class _PortalEntry {
  const _PortalEntry({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final PortalTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class PortalShell extends StatefulWidget {
  const PortalShell({super.key});

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  static const PortalTab _home = PortalTab.dashboard;
  PortalTab _selectedTab = _home;

  ExpenseStore get _store => ExpenseStore.instance;

  void _select(PortalTab tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsHubScreen()),
    );
  }

  Future<void> _openAdmin(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Employee dashboard callbacks are tab identities, not legacy indexes,
  /// so a custom tab set can never land the person on the wrong page.
  Widget _dashboardFor(ExpenseStore store) {
    final bool managementUser = store.hasManagementAccess || store.isSuperUser;
    final bool canUseOrgAnalytics =
        store.canReadAllExpenses || store.isSuperUser;
    if (!managementUser || !canUseOrgAnalytics) {
      // A custom management role may hold project or people capabilities
      // without `expense.read_all`. The organization dashboard would 403,
      // so show the personal view (which the API does allow) instead.
      return EmployeeDashboardScreen(
        onAddExpense: () => _select(PortalTab.upload),
        onViewRequests: () => _select(PortalTab.myRequests),
        onViewProjects: () => _select(PortalTab.projects),
      );
    }
    if (payoutPurePersona(store)) {
      return const FinanceDashboard();
    }
    if (store.reviewerOnlyPersona) {
      return DirectorDashboard(
        onReviewRequests: () => _select(PortalTab.requests),
      );
    }
    return ManagerDashboardScreen(
      onReviewRequests: () => _select(PortalTab.requests),
      onAddExpense: () => _select(PortalTab.upload),
    );
  }

  List<_PortalEntry> _entries(ExpenseStore store) {
    final bool managementUser = store.hasManagementAccess || store.isSuperUser;
    final bool canBuildProjects =
        store.can('project.create') ||
        store.can('project.manage') ||
        store.can('project.member.manage');

    final List<_PortalEntry> entries = <_PortalEntry>[
      _PortalEntry(
        tab: PortalTab.dashboard,
        label: 'Home',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
        screen: _dashboardFor(store),
      ),
    ];

    if (store.canApproveExpenses) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.requests,
          label: 'Review',
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check_rounded,
          screen: ManagerRequestsScreen(),
        ),
      );
    }
    // Every submitter gets their own requests — previously the management
    // portal had no such tab and a manager could not see their own
    // submissions anywhere.
    if (store.can('expense.read_own')) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.myRequests,
          label: 'My claims',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          screen: MyRequestsScreen(),
        ),
      );
    }
    if (store.can('expense.create')) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.upload,
          label: 'Add',
          icon: Icons.add_circle_outline_rounded,
          selectedIcon: Icons.add_circle_rounded,
          screen: AddExpenseScreen(),
        ),
      );
    }
    if (store.can('project.read')) {
      entries.add(
        _PortalEntry(
          tab: PortalTab.projects,
          label: 'Projects',
          icon: Icons.workspaces_outline,
          selectedIcon: Icons.workspaces_rounded,
          screen: canBuildProjects
              ? const ManagementProjectsScreen()
              : const EmployeeProjectsScreen(),
        ),
      );
    }
    if (payoutPurePersona(store)) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.toPay,
          label: 'To pay',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet_rounded,
          screen: FinanceToPayScreen(),
        ),
      );
    }
    if (store.can('reimbursement.read_all') ||
        store.can('reimbursement.read_own')) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.paid,
          label: 'Paid',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments_rounded,
          screen: PaidReimbursementsScreen(),
        ),
      );
    }
    if (store.canManageAccess) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.access,
          label: 'Access',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
          screen: AccessManagementScreen(),
        ),
      );
    }
    // The audit trail is admin-only on the server; the capability
    // decides whether the tab is there at all.
    if (store.canReadAuditLog) {
      entries.add(
        const _PortalEntry(
          tab: PortalTab.audit,
          label: 'Audit',
          icon: Icons.history_rounded,
          selectedIcon: Icons.history_toggle_off_rounded,
          screen: AuditLogScreen(),
        ),
      );
    }
    entries.add(
      _PortalEntry(
        tab: PortalTab.profile,
        label: 'Profile',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        screen: managementUser
            ? const ManagerProfileScreen()
            : const EmployeeProfileScreen(),
      ),
    );
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return AnimatedBuilder(
      animation: _store,
      builder: (BuildContext context, Widget? _) {
        // --- The plain-employee gatekeeper -----------------------------
        // Wait screen only while the project fetch has not completed;
        // the project-access request flow takes over after an empty
        // result — an unassigned employee is never stranded here.
        if (!_store.hasManagementAccess && !_store.isSuperUser) {
          if (!_store.projectsLoaded && _store.myProjects.isEmpty) {
            return Scaffold(
              backgroundColor: palette.bg,
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (_store.myProjects.isEmpty) {
            return const EmployeeWaitScreen();
          }
        }

        final List<_PortalEntry> entries = _entries(_store);
        final double width = MediaQuery.sizeOf(context).width;
        final bool wide = width >= 900;
        final int maxPrimary = wide ? 5 : 4;

        // A capability can disappear mid-session (role changed on the
        // server, org switched); never sit on a tab that is gone.
        if (!entries.any((_PortalEntry e) => e.tab == _selectedTab)) {
          _selectedTab = _home;
        }

        final List<_PortalEntry> primary = entries
            .take(maxPrimary)
            .toList(growable: false);
        final List<_PortalEntry> overflow = entries
            .skip(maxPrimary)
            .toList(growable: false);
        final int stackIndex = entries.indexWhere(
          (_PortalEntry e) => e.tab == _selectedTab,
        );
        final bool selectedIsOverflow = !primary.any(
          (_PortalEntry e) => e.tab == _selectedTab,
        );

        final Widget stack = IndexedStack(
          index: stackIndex < 0 ? 0 : stackIndex,
          children: entries.map((_PortalEntry e) => e.screen).toList(),
        );

        if (wide) {
          return Scaffold(
            backgroundColor: palette.bg,
            body: Row(
              children: <Widget>[
                _buildRail(
                  context: context,
                  palette: palette,
                  entries: primary,
                  overflow: overflow,
                  selectedTab: _selectedTab,
                  selectedIsOverflow: selectedIsOverflow,
                  extended: width >= 1180,
                ),
                VerticalDivider(width: 1, color: palette.border),
                Expanded(child: stack),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: palette.bg,
          body: stack,
          floatingActionButton: _BellButton(
            count: _store.unreadNotificationCount,
            onTap: _openNotifications,
          ),
          bottomNavigationBar: _buildBottomBar(
            context: context,
            palette: palette,
            primary: primary,
            selectedTab: _selectedTab,
            selectedIsOverflow: selectedIsOverflow,
            onOpenMore: () =>
                _showMoreSheet(context, entries: entries, primary: primary),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- phone

  Widget _buildBottomBar({
    required BuildContext context,
    required AppPalette palette,
    required List<_PortalEntry> primary,
    required PortalTab selectedTab,
    required bool selectedIsOverflow,
    required VoidCallback onOpenMore,
  }) {
    final List<NavigationDestination> destinations = primary.map((
      _PortalEntry entry,
    ) {
      return NavigationDestination(
        icon: Icon(entry.icon),
        selectedIcon: Icon(entry.selectedIcon),
        label: entry.label,
        tooltip: entry.label,
      );
    }).toList();

    destinations.add(
      NavigationDestination(
        icon: Badge(
          isLabelVisible: selectedIsOverflow,
          smallSize: 7,
          child: const Icon(Icons.more_horiz_rounded),
        ),
        selectedIcon: const Icon(Icons.more_horiz_rounded),
        label: 'More',
      ),
    );

    int index = primary.indexWhere((_PortalEntry e) => e.tab == selectedTab);
    if (index < 0) index = destinations.length - 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (int tapped) {
          if (tapped == destinations.length - 1) {
            onOpenMore();
            return;
          }
          if (tapped < primary.length) _select(primary[tapped].tab);
        },
        destinations: destinations,
      ),
    );
  }

  void _showMoreSheet(
    BuildContext context, {
    required List<_PortalEntry> entries,
    required List<_PortalEntry> primary,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final AppPalette palette = sheetContext.palette;
        final List<_PortalEntry> overflow = entries
            .where(
              (_PortalEntry e) =>
                  !primary.any((_PortalEntry p) => p.tab == e.tab),
            )
            .toList(growable: false);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: ATSLogo(size: 36, showText: true),
                ),
                if (overflow.isNotEmpty) ...<Widget>[
                  _sheetLabel(palette, 'Go to'),
                  ...overflow.map(
                    (_PortalEntry entry) => ListTile(
                      leading: Icon(
                        entry.tab == _selectedTab
                            ? entry.selectedIcon
                            : entry.icon,
                        color: entry.tab == _selectedTab
                            ? palette.gold
                            : palette.muted,
                      ),
                      title: Text(
                        entry.label,
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: entry.tab == _selectedTab
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      trailing: entry.tab == _selectedTab
                          ? Icon(Icons.check_rounded, color: palette.gold)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _select(entry.tab);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _sheetLabel(palette, 'Account'),
                ListTile(
                  leading: Badge(
                    isLabelVisible: _store.unreadNotificationCount > 0,
                    label: Text('${_store.unreadNotificationCount}'),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: palette.muted,
                    ),
                  ),
                  title: Text(
                    'Notifications',
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openNotifications();
                  },
                ),
                SwitchListTile(
                  secondary: Icon(
                    _store.isDarkMode
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: palette.gold,
                  ),
                  title: Text(
                    'Dark theme',
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: _store.isDarkMode,
                  onChanged: (_) => _store.toggleTheme(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                if (_store.can('budget.manage') || _store.canManagePeople) ...[
                  const SizedBox(height: 8),
                  _sheetLabel(palette, 'Admin tools'),
                  if (_store.can('budget.manage'))
                    ListTile(
                      leading: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: palette.muted,
                      ),
                      title: Text(
                        'Budget allocation',
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openAdmin(const BudgetAllocationScreen());
                      },
                    ),
                  if (_store.canManagePeople)
                    ListTile(
                      leading: Icon(
                        Icons.manage_accounts_rounded,
                        color: palette.muted,
                      ),
                      title: Text(
                        'Employee management',
                        style: TextStyle(
                          color: palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openAdmin(const EmployeeManagementScreen());
                      },
                    ),
                ],
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Signed in as ${_store.currentUserEmail.isEmpty ? _store.currentUserName : _store.currentUserEmail}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetLabel(AppPalette palette, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: palette.gold,
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.3,
      ),
    ),
  );

  // ----------------------------------------------------------------- wide

  Widget _buildRail({
    required BuildContext context,
    required AppPalette palette,
    required List<_PortalEntry> entries,
    required List<_PortalEntry> overflow,
    required PortalTab selectedTab,
    required bool selectedIsOverflow,
    required bool extended,
  }) {
    int index = entries.indexWhere((_PortalEntry e) => e.tab == selectedTab);
    if (index < 0) index = 0;

    final bool compact = MediaQuery.sizeOf(context).height < 720;
    return NavigationRail(
      extended: extended,
      labelType: extended || compact
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      minExtendedWidth: 216,
      backgroundColor: palette.surface,
      selectedIndex: index,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: extended
            ? const ATSLogo(size: 40, showText: true)
            : const ATSLogo(size: 40, showText: false),
      ),
      onDestinationSelected: (int tapped) {
        if (tapped < entries.length) _select(entries[tapped].tab);
      },
      destinations: entries
          .map(
            (_PortalEntry entry) => NavigationRailDestination(
              icon: Icon(entry.icon),
              selectedIcon: Icon(entry.selectedIcon, color: palette.gold),
              label: Text(entry.label),
            ),
          )
          .toList(),
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            IconButton(
              tooltip: 'Notifications',
              onPressed: _openNotifications,
              icon: Badge(
                isLabelVisible: _store.unreadNotificationCount > 0,
                label: Text('${_store.unreadNotificationCount}'),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: palette.muted,
                ),
              ),
            ),
            IconButton(
              tooltip: _store.isDarkMode ? 'Switch to light' : 'Switch to dark',
              onPressed: _store.toggleTheme,
              icon: Icon(
                _store.isDarkMode
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: palette.muted,
              ),
            ),
            if (overflow.isNotEmpty ||
                _store.can('budget.manage') ||
                _store.canManagePeople)
              IconButton(
                tooltip: 'More',
                onPressed: () => _showMoreSheet(
                  context,
                  entries: <_PortalEntry>[...entries, ...overflow],
                  primary: entries,
                ),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: selectedIsOverflow ? palette.gold : palette.muted,
                ),
              ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// Circular bell kept above the bottom bar so the notification feed is
/// reachable from every tab without adding a sixth destination.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return FloatingActionButton.small(
      heroTag: 'portal_notifications',
      tooltip: 'Notifications',
      backgroundColor: palette.surface,
      foregroundColor: palette.muted,
      elevation: 2,
      onPressed: onTap,
      child: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}
