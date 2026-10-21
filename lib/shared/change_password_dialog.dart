/// Changing your own password.
///
/// The current password is required and the account's other sessions end
/// when the password changes — so this is also how someone recovers
/// from a compromise.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show Response;

import 'package:ats_onework/shared/api_client.dart';
import 'package:ats_onework/shared/app_snack.dart';

/// Shows the change-password dialog and applies the change.
///
/// Returns true when the password was changed.
Future<bool> showChangePasswordDialog(BuildContext context) async {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();

  final submitted = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Change password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: currentController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          TextField(
            controller: newController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'At least 8 characters',
            ),
          ),
          TextField(
            controller: confirmController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Change'),
        ),
      ],
    ),
  );

  final current = currentController.text;
  final next = newController.text;
  final confirmation = confirmController.text;
  currentController.dispose();
  newController.dispose();
  confirmController.dispose();

  if (submitted != true) return false;
  if (!context.mounted) return false;

  if (next != confirmation) {
    AppSnack.error(context, 'The new passwords do not match.');
    return false;
  }
  if (next.length < 8) {
    AppSnack.error(context, 'The new password must be at least 8 characters.');
    return false;
  }

  try {
    final response = await ApiClient.post('/auth/change-password', {
      'current_password': current,
      'new_password': next,
    });
    if (!context.mounted) return false;
    if (response.statusCode == 204) {
      AppSnack.success(
        context,
        'Password changed. Your other sessions have ended.',
      );
      return true;
    }
    AppSnack.error(context, _passwordError(response));
  } catch (e) {
    if (!context.mounted) return false;
    AppSnack.error(context, 'Could not change the password.');
  }
  return false;
}

/// The backend's own error message, when it sent one.
String _passwordError(Response response) {
  try {
    final body = json.decode(response.body);
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    }
  } catch (_) {
    // Not a JSON error envelope — fall through to the generic message.
  }
  return 'Could not change the password.';
}
