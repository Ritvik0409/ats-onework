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
  final formKey = GlobalKey<FormState>();

  bool currentVisible = false;
  bool nextVisible = false;
  bool confirmVisible = false;

  final submitted = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setDialogState) {
          return AlertDialog(
            title: const Text('Change password'),
            content: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    controller: currentController,
                    obscureText: !currentVisible,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      suffixIcon: IconButton(
                        tooltip: currentVisible
                            ? 'Hide password'
                            : 'Show password',
                        icon: Icon(
                          currentVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setDialogState(
                          () => currentVisible = !currentVisible,
                        ),
                      ),
                    ),
                    validator: (String? value) =>
                        (value == null || value.isEmpty)
                        ? 'Enter your current password.'
                        : null,
                  ),
                  TextFormField(
                    controller: newController,
                    obscureText: !nextVisible,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      helperText: 'At least 8 characters',
                      suffixIcon: IconButton(
                        tooltip: nextVisible ? 'Hide password' : 'Show password',
                        icon: Icon(
                          nextVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setDialogState(() => nextVisible = !nextVisible),
                      ),
                    ),
                    validator: (String? value) {
                      if (value == null || value.length < 8) {
                        return 'Use at least 8 characters.';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: confirmController,
                    obscureText: !confirmVisible,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      errorMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: confirmVisible
                            ? 'Hide password'
                            : 'Show password',
                        icon: Icon(
                          confirmVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setDialogState(
                          () => confirmVisible = !confirmVisible,
                        ),
                      ),
                    ),
                    validator: (String? value) =>
                        (value != newController.text)
                        ? 'The passwords do not match.'
                        : null,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Change'),
              ),
            ],
          );
        },
      );
    },
  );

  final current = currentController.text;
  final next = newController.text;
  currentController.dispose();
  newController.dispose();
  confirmController.dispose();

  if (submitted != true) return false;
  if (!context.mounted) return false;

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
