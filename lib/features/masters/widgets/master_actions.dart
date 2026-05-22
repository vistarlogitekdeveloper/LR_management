import 'package:flutter/material.dart';

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
      message: 'This will remove $label from the master. Linked LRs are not affected.',
      confirmLabel: 'Delete',
    );
  }
}
