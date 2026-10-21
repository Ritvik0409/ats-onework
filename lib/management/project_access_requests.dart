import 'package:flutter/material.dart';

import 'pending_approvals_screen.dart';

/// The manager queue for project-access requests.
///
/// This screen used to carry a second, slightly different copy of the
/// same list — two queues for one endpoint, each with its own empty
/// state, its own dialogs and its own bugs. The implementation now
/// lives in [PendingApprovalsScreen]; this class only keeps the old name
/// working for anything that still refers to it.
class ProjectAccessRequestsScreen extends StatelessWidget {
  const ProjectAccessRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PendingApprovalsScreen();
}
