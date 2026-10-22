import 'package:flutter/material.dart';
import 'package:ats_onework/shared/login_screen.dart';
import 'package:ats_onework/management/expense_store.dart';
import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/app_snack.dart';
import 'package:ats_onework/shared/change_password_dialog.dart';
import 'package:ats_onework/ui/tokens.dart';
import 'package:ats_onework/ui/widgets.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          return AlertDialog(
            title: Text(
              'Log out?',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'You will need to sign in again to access the Employee Portal.',
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
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pushAndRemoveUntil(
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
          );
        },
      ),
    );
  }

  void _showSnack(String message) => AppSnack.info(context, message);

  void _showUpdateName(bool isManager) {
    final formKey = GlobalKey<FormState>();
    final store = ExpenseStore.instance;
    final nameCtrl = TextEditingController(
      text: isManager ? store.currentManagerName : store.currentEmployeeName,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return AlertDialog(
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
          );
        },
      ),
    );
  }

  Future<void> _showChangePassword() async {
    await showChangePasswordDialog(context);
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
                  _preferenceSwitch(
                    'Email alerts',
                    store.emailAlerts,
                    (val) => store.setNotificationPreference('email', val),
                  ),
                  _preferenceSwitch(
                    'Push notifications',
                    store.pushAlerts,
                    (val) => store.setNotificationPreference('push', val),
                  ),
                  _preferenceSwitch(
                    'Status update alerts',
                    store.statusUpdateAlerts,
                    (val) => store.setNotificationPreference('status', val),
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

  void _showReimbursementDetails() {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          return AlertDialog(
            title: Text(
              'Reimbursement Details',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoBullet(
                  'Approved reimbursements are credited to your registered bank/UPI account.',
                ),
                _InfoBullet(
                  'Payouts typically process within 3–5 working days of approval.',
                ),
                _InfoBullet(
                  'Contact HR/Finance to update your bank or UPI details.',
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
          );
        },
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          return AlertDialog(
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
                const _InfoBullet('Email: support@aniruddhagps.com'),
                const _InfoBullet('Aniruddha Telemetry Systems Pvt Ltd'),
                const _InfoBullet('Web: www.Aniruddhagps.com'),
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
          );
        },
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          return AlertDialog(
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
                const _InfoBullet('Krisha Pakhare'),
                const _InfoBullet('Aayush Keny'),
                const _InfoBullet('Ritvik Maurya'),
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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final AppPalette palette = context.palette;

        return Scaffold(
          backgroundColor: palette.bg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    ProfileHeader(
                      initials: store.getInitials(store.currentEmployeeName),
                      name: store.currentEmployeeName,
                      email: store.currentEmployeeEmail,
                      tags: <Widget>[
                        AppTag(label: 'Employee', dense: true),
                        AppTag(
                          label: store.currentEmployeeId,
                          color: palette.muted,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AppGrid(
                      minItemWidth: 150,
                      children: <Widget>[
                        MetricCard(
                          label: 'Pending',
                          value: store.myPendingCount.toString(),
                          icon: Icons.hourglass_top_rounded,
                          accent: palette.warning,
                        ),
                        MetricCard(
                          label: 'Approved',
                          value: store.myApprovedCount.toString(),
                          icon: Icons.check_circle_outline_rounded,
                          accent: palette.success,
                        ),
                        MetricCard(
                          label: 'Rejected',
                          value: store.myRejectedCount.toString(),
                          icon: Icons.cancel_outlined,
                          accent: palette.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
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
                          onTap: () => _showUpdateName(false),
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
                          title: 'Reimbursement details',
                          subtitle: 'How and when you get paid',
                          leading: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: palette.gold,
                            size: 20,
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: palette.muted,
                          ),
                          onTap: _showReimbursementDetails,
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

                    const SizedBox(height: 24),
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
