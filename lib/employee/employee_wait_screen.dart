import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ats_onework/employee/employee_login.dart';
import 'package:ats_onework/management/expense_store.dart';

class EmployeeWaitScreen extends StatelessWidget {
  const EmployeeWaitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;

    return Scaffold(
      backgroundColor: store.bg,
      appBar: AppBar(
        backgroundColor: store.card,
        elevation: 0,
        title: Text('Account Setup', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: store.border, height: 1),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              color: store.card,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: store.accentGold.withValues(alpha: 0.3), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: store.accentGold.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: store.accentGold, width: 1.5),
                      ),
                      child: Icon(Icons.hourglass_top_rounded, color: store.accentGold, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Awaiting Assignment',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: store.textFrost),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your account is successfully verified, but you have not been assigned to a project yet.',
                      style: TextStyle(color: store.textMuted, fontSize: 13, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // --- Green note successfully removed from here ---
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: store.accentGold.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await store.submitProjectAccessRequest();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Access request sent successfully!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              backgroundColor: store.accentGold,
                            ),
                          );
                        },
                        icon: Icon(Icons.mail_outline_rounded, color: store.accentGold, size: 18),
                        label: Text('Request Project Access', style: TextStyle(color: store.accentGold, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          if (!context.mounted) return;
                          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const UniversalLoginScreen()),
                            (Route<dynamic> route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                        label: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
  }
}