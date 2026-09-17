import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ats_onework/management/expense_store.dart';

class ProjectAccessRequestsScreen extends StatelessWidget {
  const ProjectAccessRequestsScreen({super.key});

  void _handleRequest(BuildContext context, String docId, String employeeEmail, bool isApproved) {
    final store = ExpenseStore.instance;

    if (!isApproved) {
      FirebaseFirestore.instance.collection('project_requests').doc(docId).update({'status': 'denied'});
      return;
    }

    String? selectedProjectId;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: store.card,
          title: Text('Assign to Project', style: TextStyle(color: store.accentGold)),
          content: DropdownButtonFormField<String>(
            value: selectedProjectId,
            dropdownColor: store.card,
            style: TextStyle(color: store.textFrost),
            decoration: InputDecoration(
              labelText: 'Select Project',
              labelStyle: TextStyle(color: store.textMuted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.textMuted)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: store.accentGold)),
            ),
            items: store.projects.map((p) {
              return DropdownMenuItem<String>(
                value: p.id,
                enabled: p.isActive,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      p.name, 
                      style: TextStyle(
                        color: p.isActive ? store.textFrost : store.textMuted.withValues(alpha: 0.5),
                      ),
                    ),
                    if (!p.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Deactivated', 
                          style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) => setState(() => selectedProjectId = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: store.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: store.accentGold),
              onPressed: () async {
                if (selectedProjectId == null) return;
                try {
                  await store.approveProjectAccess(employeeEmail, selectedProjectId!);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  print('Error assigning project: $e');
                }
              },
              child: Text('Confirm Assignment', style: TextStyle(color: store.bg, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseStore.instance;
    return Scaffold(
      backgroundColor: store.bg,
      appBar: AppBar(
        backgroundColor: store.card,
        title: Text('Project Access Requests', style: TextStyle(color: store.accentGold)),
        iconTheme: IconThemeData(color: store.accentGold),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('project_requests')
            .where('status', isEqualTo: 'Pending Assignment')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final requests = snapshot.data!.docs;
          if (requests.isEmpty) return Center(child: Text('No pending requests.', style: TextStyle(color: store.textMuted)));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index].data() as Map<String, dynamic>;
              final docId = requests[index].id;
              final email = req['email'] ?? docId;

              return Card(
                color: store.card,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text('${req['name']}', style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                  subtitle: Text(email, style: TextStyle(color: store.textMuted)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                        onPressed: () => _handleRequest(context, docId, email, false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                        onPressed: () => _handleRequest(context, docId, email, true),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}