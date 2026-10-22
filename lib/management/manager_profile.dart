import 'package:flutter/material.dart';
import 'package:ats_onework/shared/login_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/management/budget_allocation_screen.dart';
import 'package:ats_onework/management/employee_management_screen.dart';
import 'package:ats_onework/management/pending_approvals_screen.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/app_snack.dart';
import 'package:ats_onework/shared/change_password_dialog.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

class ManagerProfileScreen extends StatefulWidget {
  const ManagerProfileScreen({super.key});

  @override
  State<ManagerProfileScreen> createState() => _ManagerProfileScreenState();
}

class _ManagerProfileScreenState extends State<ManagerProfileScreen> {
  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Log out?',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'You will need to sign in again to access the Management Portal.',
          style: TextStyle(color: context.palette.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // Revokes the refresh token server-side and clears the
              // local JWT store (api_client.dart).
              await ApiClient.signOut();
              // Drop the previous user's data from the shared store.
              ExpenseStore.instance.resetForSignOut();

              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const UniversalLoginScreen(),
                  ),
                  (Route<dynamic> route) => false,
                );
              }
            },
            child: Text(
              'Log Out',
              style: TextStyle(
                color: context.palette.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) => AppSnack.info(context, message);

  void _showUpdateName(bool isManager) {
    final formKey = GlobalKey<FormState>();
    final store = ExpenseStore.instance;
    final nameCtrl = TextEditingController(
      text: isManager ? store.currentUserName : store.currentEmployeeName,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Update Full Name',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                style: TextStyle(color: context.palette.text, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Legal Full Name',
                  labelStyle: TextStyle(
                    color: context.palette.muted,
                    fontSize: 13,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name cannot be empty.';
                  }
                  final regex = RegExp(r'^[a-zA-Z]+\s+[a-zA-Z\s]+$');
                  if (!regex.hasMatch(value.trim())) {
                    return 'Enter a valid first and last name (letters only).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final bool ok = await store.updateName(
                  nameCtrl.text.trim(),
                  isManager,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ok
                    ? _showSnack('Name updated successfully')
                    : AppSnack.error(
                        context,
                        "Couldn't update your name. Try again.",
                      );
              }
            },
            child: Text(
              'Save',
              style: TextStyle(
                color: context.palette.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePassword() async {
    await showChangePasswordDialog(context);
  }

  void _showNotificationPreferences() {
    final ExpenseStore store = ExpenseStore.instance;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            return AlertDialog(
              title: Text(
                'Notification Preferences',
                style: TextStyle(
                  color: context.palette.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _preferenceSwitch('Email alerts', store.emailAlerts, (val) {
                    store.setNotificationPreference('email', val);
                  }),
                  _preferenceSwitch('Push notifications', store.pushAlerts, (
                    val,
                  ) {
                    store.setNotificationPreference('push', val);
                  }),
                  _preferenceSwitch(
                    'SLA breach warnings',
                    store.statusUpdateAlerts,
                    (val) {
                      store.setNotificationPreference('status', val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      color: context.palette.gold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _preferenceSwitch(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.palette.text, fontSize: 14),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: context.palette.gold,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showSecurityInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Security & Encryption',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoBullet('Receipts are encrypted (AES-256) before upload.'),
            _InfoBullet(
              'Only verified management accounts can decrypt receipts.',
            ),
            _InfoBullet(
              'Only @company.com accounts can sign in to this portal.',
            ),
            _InfoBullet(
              'Approved/Rejected decisions are permanent and cannot be reversed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Got it',
              style: TextStyle(
                color: context.palette.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Help & Support',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help using ATS OneWork?',
              style: TextStyle(
                color: context.palette.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _InfoBullet('Email: support@aniruddhagps.com'),
            _InfoBullet('Aniruddha Telemetry Systems Pvt Ltd'),
            _InfoBullet('Web: www.Aniruddhagps.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Close',
              style: TextStyle(
                color: context.palette.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'About ATS OneWork',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: TextStyle(
                color: context.palette.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A mobile expense submission and approval system for employees and managers.',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Text(
              'Developed by:',
              style: TextStyle(
                color: context.palette.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            _InfoBullet('Krisha Pakhare'),
            _InfoBullet('Aayush Keny '),
            _InfoBullet('Ritvik Maurya'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Close',
              style: TextStyle(
                color: context.palette.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseTypeDialog(ExpenseStore store) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Add Expense Type',
          style: TextStyle(
            color: context.palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              _submitExpenseType(controller, store, dialogContext),
          decoration: const InputDecoration(labelText: 'Expense Type Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          FilledButton(
            onPressed: () =>
                _submitExpenseType(controller, store, dialogContext),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Validates, submits and closes the add-expense-type dialog in one
  /// step — the enter key and the Add button now do the same thing.
  Future<void> _submitExpenseType(
    TextEditingController controller,
    ExpenseStore store,
    BuildContext dialogContext,
  ) async {
    if (controller.text.trim().isEmpty) return;
    await store.addNewExpenseType(controller.text.trim());
    if (dialogContext.mounted) Navigator.pop(dialogContext);
    _showSnack('Expense type added successfully!');
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final AppPalette palette = context.palette;
        final bool isFinance = store.currentUserRole == 'finance';

        return Scaffold(
          backgroundColor: palette.bg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    ProfileHeader(
                      initials: store.getInitials(store.currentUserName),
                      name: store.currentUserName,
                      email: store.currentUserEmail,
                      tags: <Widget>[
                        AppTag(label: store.currentUserRole, dense: true),
                        AppTag(
                          label: store.currentUserId,
                          color: palette.muted,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if (!isFinance) ...[
                      AppGrid(
                        minItemWidth: 150,
                        children: <Widget>[
                          MetricCard(
                            label: 'Pending',
                            value: store.pendingCount.toString(),
                            icon: Icons.hourglass_top_rounded,
                            accent: palette.warning,
                          ),
                          MetricCard(
                            label: 'Approved',
                            value: store.approvedCount.toString(),
                            icon: Icons.check_circle_outline_rounded,
                            accent: palette.success,
                          ),
                          MetricCard(
                            label: 'Rejected',
                            value: store.rejectedCount.toString(),
                            icon: Icons.cancel_outlined,
                            accent: palette.danger,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                    ],

                    const SectionHeader(title: 'Account'),
                    SettingsGroup(
                      children: <Widget>[
                        AppListTile(
                          title: 'Update full name',
                          subtitle: 'Edit your professional display name',
                          leading: Icon(
                            Icons.badge_outlined,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: () => _showUpdateName(true),
                        ),
                        AppListTile(
                          title: 'Change password',
                          subtitle: 'Update your login credentials',
                          leading: Icon(
                            Icons.lock_reset_rounded,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: _showChangePassword,
                        ),
                        AppListTile(
                          title: 'Notification preferences',
                          subtitle: 'Choose what alerts you receive',
                          leading: Icon(
                            Icons.notifications_active_rounded,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: _showNotificationPreferences,
                        ),
                        AppListTile(
                          title: 'Security & encryption',
                          subtitle: 'Manage receipt decryption access',
                          leading: Icon(
                            Icons.shield_outlined,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: _showSecurityInfo,
                        ),
                        if (!isFinance)
                          AppListTile(
                            title: 'Manage people',
                            subtitle: 'Activate or deactivate employee access',
                            leading: Icon(
                              Icons.people_alt_rounded,
                              color: palette.gold,
                              size: 20,
                            ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: palette.muted,
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    const EmployeeManagementScreen(),
                              ),
                            ),
                          ),
                        AppListTile(
                          title: 'Dark mode',
                          subtitle: 'Toggle the application appearance',
                          leading: Icon(
                            Icons.contrast_rounded,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Switch(
                            value: store.isDarkMode,
                            activeThumbColor: palette.gold,
                            onChanged: (bool _) => store.toggleTheme(),
                          ),
                        ),
                      ],
                    ),

                    if (!isFinance) ...[
                      if (store.isHR) ...[
                        const SizedBox(height: 26),
                        const SectionHeader(title: 'HR tools'),
                        SettingsGroup(
                          children: <Widget>[
                            AppListTile(
                              title: 'Budget allocation',
                              subtitle: 'Set the monthly budget for the team',
                              leading: Icon(
                                Icons.account_balance_wallet_rounded,
                                color: palette.gold,
                                size: 20,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      const BudgetAllocationScreen(),
                                ),
                              ),
                            ),
                            AppListTile(
                              title: 'Project access requests',
                              subtitle: 'Review and assign people to projects',
                              leading: Icon(
                                Icons.mark_email_unread_rounded,
                                color: palette.gold,
                                size: 20,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      const PendingApprovalsScreen(),
                                ),
                              ),
                            ),
                            AppListTile(
                              title: 'Manage expense types',
                              subtitle: 'Add categories for the organization',
                              leading: Icon(
                                Icons.category_rounded,
                                color: palette.gold,
                                size: 20,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                              ),
                              onTap: () => _showAddExpenseTypeDialog(store),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 26),
                        const SectionHeader(title: 'Tools'),
                        SettingsGroup(
                          children: <Widget>[
                            AppListTile(
                              title: 'Project access requests',
                              subtitle: 'Review and assign people to projects',
                              leading: Icon(
                                Icons.mark_email_unread_rounded,
                                color: palette.gold,
                                size: 20,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      const PendingApprovalsScreen(),
                                ),
                              ),
                            ),
                            AppListTile(
                              title: 'Manage expense types',
                              subtitle: 'Add categories for the organization',
                              leading: Icon(
                                Icons.category_rounded,
                                color: palette.gold,
                                size: 20,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: palette.muted,
                              ),
                              onTap: () => _showAddExpenseTypeDialog(store),
                            ),
                          ],
                        ),
                      ],
                    ],

                    const SizedBox(height: 26),
                    const SectionHeader(title: 'Support'),
                    SettingsGroup(
                      children: <Widget>[
                        AppListTile(
                          title: 'Help & support',
                          subtitle: 'Contact the ATS support team',
                          leading: Icon(
                            Icons.help_outline_rounded,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: _showHelpSupport,
                        ),
                        AppListTile(
                          title: 'About ATS OneWork',
                          subtitle: 'Version 1.0.0',
                          leading: Icon(
                            Icons.info_outline_rounded,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: _showAbout,
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmLogout(context),
                        icon: Icon(
                          Icons.logout_rounded,
                          color: palette.danger,
                          size: 18,
                        ),
                        label: const Text('Log out'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.danger,
                          side: BorderSide(
                            color: palette.danger.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusMd,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoBullet extends StatelessWidget {
  final String text;
  const _InfoBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: TextStyle(
              color: context.palette.gold,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
