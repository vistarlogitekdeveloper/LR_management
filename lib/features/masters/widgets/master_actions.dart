import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/confirm_dialog.dart';

class MasterActions {
  MasterActions._();

  static Future<bool> confirmDelete({
    required BuildContext context,
    required String label,
  }) {
    return showConfirmDialog(
      context: context,
      title: 'Delete $label?',
      message:
          'This will remove $label from the master. Linked LRs are not affected.',
      confirmLabel: 'Delete',
    );
  }

  /// Extracts a human-readable message from any error (ApiException-aware).
  static String messageFor(Object error) {
    if (error is DioException && error.error is ApiException) {
      return (error.error as ApiException).message;
    }
    if (error is ApiException) return error.message;
    return error.toString();
  }

  static void showError(BuildContext context, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(messageFor(error)),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}
