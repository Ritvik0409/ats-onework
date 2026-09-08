import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ats_onework/employee/employee_login.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  bool _emailAlerts = true;
  bool _pushAlerts = true;
  bool _statusUpdateAlerts = true;

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          final store = ExpenseStore.instance;
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Log out?', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Text('You will need to sign in again to access the Employee Portal.', style: TextStyle(color: store.textMuted, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop(); 
                  await FirebaseAuth.instance.signOut(); 
                  
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const UniversalLoginScreen()),
                      (Route<dynamic> route) => false,
                    );
                  }
                },
                child: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: ExpenseStore.instance.accentGold,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showUpdateName(bool isManager) {
    final formKey = GlobalKey<FormState>();
    final store = ExpenseStore.instance;
    final nameCtrl = TextEditingController(text: isManager ? store.currentManagerName : store.currentEmployeeName);

    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Update Full Name', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    style: TextStyle(color: store.textFrost, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Legal Full Name',
                      labelStyle: TextStyle(color: store.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: store.isDarkMode ? store.bg : Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.accentGold, width: 1.5)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Name cannot be empty.';
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
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              TextButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                   await store.updateName(nameCtrl.text.trim(), isManager);
                   if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                    _showSnack('Name updated successfully');
                  }
                },
                child: Text('Save', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _passwordField(TextEditingController controller, String label, ExpenseStore store, {TextEditingController? confirmAgainst}) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      style: TextStyle(color: store.textFrost, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: store.textMuted, fontSize: 13),
        filled: true,
        fillColor: store.isDarkMode ? store.bg : Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: store.accentGold, width: 1.5)),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'This field is required';
        if (value.length < 6) return 'Must be at least 6 characters';
        if (confirmAgainst != null && value != confirmAgainst.text) return 'Passwords do not match';
        return null;
      },
    );
  }

  void _showChangePassword() {
    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          final store = ExpenseStore.instance;
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Change Password', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _passwordField(currentCtrl, 'Current Password', store),
                    const SizedBox(height: 12),
                    _passwordField(newCtrl, 'New Password', store),
                    const SizedBox(height: 12),
                    _passwordField(confirmCtrl, 'Confirm New Password', store, confirmAgainst: newCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: TextStyle(color: store.textMuted))),
              TextButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    try {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null && user.email != null) {
                        // 1. Verify current credentials
                        final credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: currentCtrl.text,
                        );
                        await user.reauthenticateWithCredential(credential);

                        // 2. Lock in new password
                        await user.updatePassword(newCtrl.text);

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _showSnack('Password securely updated!');
                      }
                    } on FirebaseAuthException catch (e) {
                      String errorMessage = 'Failed to update password.';
                      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                        errorMessage = 'The current password you entered is incorrect.';
                      } else if (e.code == 'weak-password') {
                        errorMessage = 'The new password is too weak.';
                      } else {
                        errorMessage = e.message ?? errorMessage;
                      }
                      
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage, style: const TextStyle(fontWeight: FontWeight.bold)), 
                          backgroundColor: Colors.redAccent
                        ),
                      );
                    }
                  }
                },
                child: Text('Update', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _preferenceSwitch(String label, bool value, ExpenseStore store, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: store.textFrost, fontSize: 14))),
        Switch(value: value, activeThumbColor: store.accentGold, onChanged: onChanged),
      ],
    );
  }

  void _showNotificationPreferences() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AnimatedBuilder(
              animation: ExpenseStore.instance,
              builder: (context, _) {
                final store = ExpenseStore.instance;
                return AlertDialog(
                  backgroundColor: store.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
                  title: Text('Notification Preferences', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _preferenceSwitch('Email alerts', _emailAlerts, store, (val) => setDialogState(() => _emailAlerts = val)),
                      _preferenceSwitch('Push notifications', _pushAlerts, store, (val) => setDialogState(() => _pushAlerts = val)),
                      _preferenceSwitch('Status update alerts', _statusUpdateAlerts, store, (val) => setDialogState(() => _statusUpdateAlerts = val)),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        setState(() {});
                        _showSnack('Notification preferences updated');
                      },
                      child: Text('Done', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              }
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
          final store = ExpenseStore.instance;
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Reimbursement Details', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoBullet('Approved reimbursements are credited to your registered bank/UPI account.'),
                _InfoBullet('Payouts typically process within 3–5 working days of approval.'),
                _InfoBullet('Contact HR/Finance to update your bank or UPI details.'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Got it', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold))),
            ],
          );
        }
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          final store = ExpenseStore.instance;
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('Help & Support', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need help using ATS OneWork?', style: TextStyle(color: store.textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                const _InfoBullet('Email: support@aniruddhagps.com'),
                const _InfoBullet('Aniruddha Telemetry Systems Pvt Ltd'),
                const _InfoBullet('Web: www.Aniruddhagps.com'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Close', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold))),
            ],
          );
        }
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ExpenseStore.instance,
        builder: (context, _) {
          final store = ExpenseStore.instance;
          return AlertDialog(
            backgroundColor: store.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: store.accentGold.withValues(alpha: 0.2))),
            title: Text('About ATS OneWork', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version 1.0.0', style: TextStyle(color: store.textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text('A mobile expense submission and approval system for employees and managers.', style: TextStyle(color: store.textMuted, fontSize: 13)),
                const SizedBox(height: 14),
                Text('Developed by:', style: TextStyle(color: store.textFrost, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const _InfoBullet('Krisha Pakhare'),
                const _InfoBullet('Aayush Keny'),
                const _InfoBullet('Ritvik Maurya'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Close', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold))),
            ],
          );
        }
      ),
    );
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

        return Scaffold(
          backgroundColor: obsidianBlack,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(color: darkCharcoal, shape: BoxShape.circle, border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.5), boxShadow: cardShadows),
                          alignment: Alignment.center,
                          child: Text(
                            store.getInitials(store.currentEmployeeName),
                            style: TextStyle(color: champagneGold, fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(store.currentEmployeeName, style: TextStyle(color: textFrost, fontSize: 19, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(store.currentEmployeeEmail, style: TextStyle(color: textMuted, fontSize: 13)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(color: champagneGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                    child: const Text('EMPLOYEE', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(color: store.isDarkMode ? const Color(0xFF262633) : Colors.grey.shade300, borderRadius: BorderRadius.circular(6)),
                                    child: Text(store.currentEmployeeId, style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(child: _statCard('Pending', store.myPendingCount.toString(), champagneGold, store, cardShadows)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard('Approved', store.myApprovedCount.toString(), Colors.greenAccent.shade400, store, cardShadows)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard('Rejected', store.myRejectedCount.toString(), Colors.redAccent.shade400, store, cardShadows)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text('Account', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    
                    Container(
                      decoration: BoxDecoration(color: darkCharcoal, borderRadius: BorderRadius.circular(16), border: Border.all(color: store.isDarkMode ? champagneGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
                      child: Column(
                        children: [
                          _buildListTile(Icons.badge_rounded, 'Update Full Name', 'Edit your professional display name', () => _showUpdateName(false), store),
                          _buildDivider(store),
                          _buildListTile(Icons.lock_reset_rounded, 'Change Password', 'Update your login credentials', _showChangePassword, store),
                          _buildDivider(store),
                          _buildListTile(Icons.notifications_active_rounded, 'Notification Preferences', 'Choose what alerts you receive', _showNotificationPreferences, store),
                          _buildDivider(store),
                          _buildListTile(Icons.account_balance_wallet_rounded, 'Reimbursement Details', 'How and when you get paid', _showReimbursementDetails, store),
                          _buildDivider(store),
                          ListTile(
                            leading: Icon(Icons.contrast_rounded, color: champagneGold, size: 20),
                            title: Text('Dark Mode', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: Text('Toggle application appearance', style: TextStyle(color: textMuted, fontSize: 12)),
                            trailing: Switch(
                              value: store.isDarkMode,
                              activeThumbColor: champagneGold,
                              onChanged: (val) => store.toggleTheme(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text('Support', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _settingsGroup([
                      _SettingsItemData(Icons.help_outline_rounded, 'Help & Support', 'Contact ATS support team', _showHelpSupport),
                      _SettingsItemData(Icons.info_outline_rounded, 'About ATS OneWork', 'Version 1.0.0', _showAbout),
                    ], store, cardShadows),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmLogout(context),
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                        label: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: darkCharcoal,
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _buildListTile(IconData icon, String title, String subtitle, VoidCallback onTap, ExpenseStore store) {
    return ListTile(
      leading: Icon(icon, color: store.accentGold, size: 20),
      title: Text(title, style: TextStyle(color: store.textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: store.textMuted, fontSize: 12)),
      trailing: Icon(Icons.chevron_right_rounded, color: store.textMuted, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildDivider(ExpenseStore store) {
    return Divider(color: store.isDarkMode ? const Color(0xFF262633) : Colors.grey.shade200, height: 1, thickness: 1);
  }

  Widget _statCard(String label, String value, Color color, ExpenseStore store, List<BoxShadow> cardShadows) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(color: store.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: store.isDarkMode ? store.accentGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: store.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _settingsGroup(List<_SettingsItemData> items, ExpenseStore store, List<BoxShadow> cardShadows) {
    return Container(
      decoration: BoxDecoration(color: store.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: store.isDarkMode ? store.accentGold.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)), boxShadow: cardShadows),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return Container(
            decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: store.isDarkMode ? const Color(0xFF262633) : Colors.grey.shade200, width: 1))),
            child: ListTile(
              leading: Icon(item.icon, color: store.accentGold, size: 20),
              title: Text(item.title, style: TextStyle(color: store.textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(item.subtitle, style: TextStyle(color: store.textMuted, fontSize: 12)),
              trailing: Icon(Icons.chevron_right_rounded, color: store.textMuted, size: 20),
              onTap: item.onTap,
            ),
          );
        }),
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  final String text;
  const _InfoBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ExpenseStore.instance,
      builder: (context, _) {
        final store = ExpenseStore.instance;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
              Expanded(child: Text(text, style: TextStyle(color: store.textMuted, fontSize: 13))),
            ],
          ),
        );
      }
    );
  }
}

class _SettingsItemData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  _SettingsItemData(this.icon, this.title, this.subtitle, this.onTap);
}