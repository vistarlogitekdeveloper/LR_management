import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/mime_types.dart';
import '../../masters/providers/master_providers.dart';
import '../../masters/widgets/master_actions.dart';
import '../data/ledger_row.dart';
import 'ledger_table.dart' show kEmptyCell;

/// The "Upload Document" cell: one chip per document on file (PAN, Aadhaar,
/// Cheque, TDS). A chip the caller may open is a button that opens the file
/// through the same endpoints the master forms use; one they may not open is
/// shown greyed, so the column still answers "is it on file?".
class LedgerDocumentChips extends ConsumerWidget {
  final List<LedgerDocument> documents;
  const LedgerDocumentChips({super.key, required this.documents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (documents.isEmpty) {
      return const Text(
        kEmptyCell,
        style: TextStyle(fontSize: 12.5, color: AppColors.slate),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final doc in documents) _DocChip(doc: doc)],
    );
  }
}

class _DocChip extends ConsumerWidget {
  final LedgerDocument doc;
  const _DocChip({required this.doc});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = doc.ownerType == 'driver'
          ? await ref
                .read(driversRepositoryProvider)
                .downloadDocument(doc.ownerId, type: doc.type)
          : await ref
                .read(transportersRepositoryProvider)
                .downloadDocument(doc.ownerId, type: doc.type);
      final name = doc.fileName.isEmpty ? doc.type : doc.fileName;
      openFileInBrowser(bytes, mimeForName(name), name);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = doc.viewable ? AppColors.plum : AppColors.slate;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            doc.viewable
                ? Icons.visibility_outlined
                : Icons.check_circle_outline_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            doc.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (!doc.viewable) {
      return Tooltip(
        message:
            '${doc.label} is on file. '
            'You need document access to open it.',
        child: chip,
      );
    }
    return Tooltip(
      message:
          'Open ${doc.label}'
          '${doc.fileName.isEmpty ? '' : ' (${doc.fileName})'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _open(context, ref),
        child: chip,
      ),
    );
  }
}
