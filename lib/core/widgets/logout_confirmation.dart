import 'package:flutter/material.dart';

import '../app_strings.dart';

Future<bool> confirmSignOut(BuildContext context, AppStrings s) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.text('تأكيد تسجيل الخروج', 'Confirm sign out')),
      content: Text(
        s.text(
          'هل أنت متأكد أنك تريد تسجيل الخروج؟',
          'Are you sure you want to sign out?',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(s.text('إلغاء', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: Text(s.text('تسجيل الخروج', 'Sign out')),
        ),
      ],
    ),
  );
  return result == true;
}
