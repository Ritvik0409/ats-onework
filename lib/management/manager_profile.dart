import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class ManagerProfileScreen extends StatefulWidget {
  const ManagerProfileScreen({super.key});

  @override
  State<ManagerProfileScreen> createState() => _ManagerProfileScreenState();
}

class _ManagerProfileScreenState extends State<ManagerProfileScreen> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  bool _emailAlerts = true;
  bool _pushAlerts = true;
  bool _slaBreachAlerts = true;

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
        ),
        title: const Text('Log out?', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
        content: const Text(
          'You will need to sign in again to access the Management Portal.',
          style: TextStyle(color: textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: champagneGold,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showChangePassword() {
    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
        ),
        title: const Text('Change Password', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _passwordField(currentCtrl, 'Current Password'),
                const SizedBox(height: 12),
                _passwordField(newCtrl, 'New Password'),
                const SizedBox(height: 12),
                _passwordField(confirmCtrl, 'Confirm New Password', confirmAgainst: newCtrl),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext);
                _showSnack('Password updated');
              }
            },
            child: const Text('Update', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(TextEditingController controller, String label, {TextEditingController? confirmAgainst}) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(color: textFrost, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: textMuted, fontSize: 13),
        filled: true,
        fillColor: obsidianBlack,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: champagneGold, width: 1.5),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'This field is required';
        if (value.length < 6) return 'Must be at least 6 characters';
        if (confirmAgainst != null && value != confirmAgainst.text) return 'Passwords do not match';
        return null;
      },
    );
  }

  void _showNotificationPreferences() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: darkCharcoal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
              ),
              title: const Text('Notification Preferences', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _preferenceSwitch('Email alerts', _emailAlerts, (val) {
                    setDialogState(() => _emailAlerts = val);
                  }),
                  _preferenceSwitch('Push notifications', _pushAlerts, (val) {
                    setDialogState(() => _pushAlerts = val);
                  }),
                  _preferenceSwitch('SLA breach warnings', _slaBreachAlerts, (val) {
                    setDialogState(() => _slaBreachAlerts = val);
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    setState(() {});
                    _showSnack('Notification preferences updated');
                  },
                  child: const Text('Done', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _preferenceSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: textFrost, fontSize: 14))),
        Switch(
          value: value,
          activeColor: champagneGold,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showSecurityInfo() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
        ),
        title: const Text('Security & Encryption', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoBullet('Receipts are encrypted (AES-256) before upload.'),
            _InfoBullet('Only verified management accounts can decrypt receipts.'),
            _InfoBullet('Only @company.com accounts can sign in to this portal.'),
            _InfoBullet('Approved/Rejected decisions are permanent and cannot be reversed.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showHelpSupport() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
        ),
        title: const Text('Help & Support', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need help using ATS OneWork?', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            _InfoBullet('Email: support@aniruddhagps.com'),
            _InfoBullet('Aniruddha Telemetry Systems Pvt Ltd'),
            _InfoBullet('Web: www.Aniruddhagps.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: darkCharcoal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: champagneGold.withValues(alpha: 0.2)),
        ),
        title: const Text('About ATS OneWork', style: TextStyle(color: textFrost, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0', style: TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            Text(
              'A mobile expense submission and approval system for employees and managers.',
              style: TextStyle(color: textMuted, fontSize: 13),
            ),
            SizedBox(height: 14),
            Text('Developed by:', style: TextStyle(color: textFrost, fontSize: 13, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            _InfoBullet('Krisha Pakhare'),
            _InfoBullet('Aayush Keny '),
            _InfoBullet('Ritvik Maurya'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(color: champagneGold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
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
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            shape: BoxShape.circle,
                            border: Border.all(color: champagneGold.withValues(alpha: 0.3), width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            store.currentManagerName.isNotEmpty ? store.currentManagerName[0].toUpperCase() : 'M',
                            style: const TextStyle(color: champagneGold, fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.currentManagerName,
                                style: const TextStyle(color: textFrost, fontSize: 19, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                store.currentManagerEmail,
                                style: const TextStyle(color: textMuted, fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: champagneGold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'MANAGER',
                                  style: TextStyle(color: champagneGold, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(child: _statCard('Pending', store.pendingCount.toString(), champagneGold)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard('Approved', store.approvedCount.toString(), Colors.greenAccent.shade400)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard('Rejected', store.rejectedCount.toString(), Colors.redAccent.shade400)),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('Account', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _settingsGroup([
                      _SettingsItemData(Icons.lock_reset_rounded, 'Change Password', 'Update your login credentials', _showChangePassword),
                      _SettingsItemData(Icons.notifications_active_rounded, 'Notification Preferences', 'Choose what alerts you receive', _showNotificationPreferences),
                      _SettingsItemData(Icons.shield_rounded, 'Security & Encryption', 'Manage receipt decryption access', _showSecurityInfo),
                    ]),
                    const SizedBox(height: 24),
                    const Text('Support', style: TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _settingsGroup([
                      _SettingsItemData(Icons.help_outline_rounded, 'Help & Support', 'Contact ATS support team', _showHelpSupport),
                      _SettingsItemData(Icons.info_outline_rounded, 'About ATS OneWork', 'Version 1.0.0', _showAbout),
                    ]),
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

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: darkCharcoal,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _settingsGroup(List<_SettingsItemData> items) {
    return Container(
      decoration: BoxDecoration(
        color: darkCharcoal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: champagneGold.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return Container(
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFF262633), width: 1)),
            ),
            child: ListTile(
              leading: Icon(item.icon, color: champagneGold, size: 20),
              title: Text(item.title, style: const TextStyle(color: textFrost, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(item.subtitle, style: const TextStyle(color: textMuted, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: Color(0xFFE2B93B), fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
          ),
        ],
      ),
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