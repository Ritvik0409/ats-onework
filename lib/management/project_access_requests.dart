import 'package:flutter/material.dart';
import 'package:ats_onework/management/expense_store.dart';

class ProjectAccessRequestsScreen extends StatefulWidget {
  const ProjectAccessRequestsScreen({super.key});

  @override
  State<ProjectAccessRequestsScreen> createState() => _ProjectAccessRequestsScreenState();
}

class _ProjectAccessRequestsScreenState extends State<ProjectAccessRequestsScreen> {
  void _handleRequest(BuildContext context, Map<String, dynamic> request, bool isApproved) {
    final store = ExpenseStore.instance;
    final email = request['email'] ?? '';

    if (!isApproved) {
      // Handle denial locally or via backend if needed
      store.projectRequests.removeWhere((r) => r['email'] == email);
      setState(() {});
      return;
    }

    String? selectedProjectId;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
            onChanged: (val) => setDialogState(() => selectedProjectId = val),
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
                  await store.approveProjectAccess(email, selectedProjectId!);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  setState(() {});
                } catch (e) {
                  debugPrint('Error assigning project: $e');
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

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final requests = store.projectRequests;

        return Scaffold(
          backgroundColor: store.bg,
          appBar: AppBar(
            backgroundColor: store.card,
            title: Text('Project Access Requests', style: TextStyle(color: store.accentGold)),
            iconTheme: IconThemeData(color: store.accentGold),
          ),
          body: requests.isEmpty
              ? Center(child: Text('No pending requests.', style: TextStyle(color: store.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final email = req['email'] ?? '';
                    final name = req['name'] ?? 'Unknown';

                    return Card(
                      color: store.card,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(name, style: TextStyle(color: store.textFrost, fontWeight: FontWeight.bold)),
                        subtitle: Text(email, style: TextStyle(color: store.textMuted)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                              onPressed: () => _handleRequest(context, req, false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                              onPressed: () => _handleRequest(context, req, true),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}