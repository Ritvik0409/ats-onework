import 'package:flutter/material.dart';

import '../ui/tokens.dart';

/// One vocabulary for statuses across backend (`pending`,
/// `info_requested`, `reimbursed`) and the client's display strings
/// (`Pending Verification`, `Info Requested`, `Paid`).
enum StatusTone {
  pending,
  info,
  approved,
  rejected,
  paid,
  processing,
  failed,
  neutral,
}

StatusTone statusTone(String status) {
  switch (status.trim().toLowerCase().replaceAll(' ', '_')) {
    case 'pending':
    case 'pending_verification':
    case 'pending_review':
      return StatusTone.pending;
    case 'info_requested':
    case 'info':
      return StatusTone.info;
    case 'approved':
      return StatusTone.approved;
    case 'rejected':
      return StatusTone.rejected;
    case 'paid':
    case 'reimbursed':
      return StatusTone.paid;
    case 'processing':
      return StatusTone.processing;
    case 'failed':
      return StatusTone.failed;
    default:
      return StatusTone.neutral;
  }
}

String statusLabel(String status) {
  switch (statusTone(status)) {
    case StatusTone.pending:
      return 'Pending Verification';
    case StatusTone.info:
      return 'Info Requested';
    case StatusTone.approved:
      return 'Approved';
    case StatusTone.rejected:
      return 'Rejected';
    case StatusTone.paid:
      return 'Paid';
    case StatusTone.processing:
      return 'Processing';
    case StatusTone.failed:
      return 'Failed';
    case StatusTone.neutral:
      return status;
  }
}

Color statusColor(String status, AppPalette palette) {
  switch (statusTone(status)) {
    case StatusTone.pending:
      return palette.warning;
    case StatusTone.info:
      return palette.info;
    case StatusTone.approved:
      return palette.success;
    case StatusTone.rejected:
    case StatusTone.failed:
      return palette.danger;
    case StatusTone.paid:
      return palette.success;
    case StatusTone.processing:
      return palette.info;
    case StatusTone.neutral:
      return palette.muted;
  }
}

IconData statusIcon(String status) {
  switch (statusTone(status)) {
    case StatusTone.pending:
      return Icons.hourglass_top_rounded;
    case StatusTone.info:
      return Icons.help_outline_rounded;
    case StatusTone.approved:
      return Icons.check_circle_outline_rounded;
    case StatusTone.rejected:
      return Icons.cancel_outlined;
    case StatusTone.paid:
      return Icons.verified_rounded;
    case StatusTone.processing:
      return Icons.autorenew_rounded;
    case StatusTone.failed:
      return Icons.error_outline_rounded;
    case StatusTone.neutral:
      return Icons.info_outline_rounded;
  }
}
