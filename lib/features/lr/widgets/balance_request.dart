import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mime_types.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../reports/services/export_service.dart';
import '../providers/lr_providers.dart';
import 'pod_picker.dart';

export '../utils/pod_photo.dart' show podExtensions, podMaxBytes, podFileError;

/// "Request for balance payment": once the transporter advance is paid, the
/// operator uploads the POD and asks Accounts for the balance. Accounts sees
/// the LR under "Balance Requested" with the POD. The server
/// (POST /lrs/:id/request-balance) holds the rule; [LorryReceipt.canRequestBalance]
/// mirrors it so the button only shows when the request can succeed.

/// The row action on the Lorry Receipts list / LR detail: "Request balance
/// payment" while the balance can be requested, then "Balance requested" (to
/// view or replace the POD) once it has been. Nothing otherwise.
class BalanceRequestIconButton extends ConsumerWidget {
  final LorryReceipt lr;
  final bool compact;
  const BalanceRequestIconButton({
    super.key,
    required this.lr,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!lr.canRequestBalance) return const SizedBox.shrink();
    final requested = lr.isBalanceRequested;
    return IconButton(
      tooltip: requested
          ? 'Balance requested on ${formatDate(lr.balanceRequestedAt!)} — view or replace POD'
          : 'Request balance payment (upload POD)',
      visualDensity: compact ? VisualDensity.compact : null,
      icon: Icon(
        requested ? Icons.task_alt_rounded : Icons.request_quote_outlined,
        color: requested ? AppColors.ok : AppColors.orange,
        size: 18,
      ),
      onPressed: () => showBalanceRequestDialog(context, ref, lr),
    );
  }
}

/// Opens the request dialog. Returns true when a request was sent.
Future<bool> showBalanceRequestDialog(
  BuildContext context,
  WidgetRef ref,
  LorryReceipt lr,
) async {
  // The dialog pops with the LR as the server now has it, null if cancelled.
  final after = await showDialog<LorryReceipt>(
    context: context,
    builder: (_) => _BalanceRequestDialog(lr: lr),
  );
  final sent = after != null;
  if (sent && context.mounted) {
    // The POD may have marked the LR Delivered — reload the open detail page.
    ref.invalidate(lrDetailProvider(lr.id));
    final delivered =
        lr.status != LrStatus.delivered && after.status == LrStatus.delivered;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lr.isBalanceRequested
              ? 'POD replaced for ${lr.number}. Accounts has been told.'
              : 'Balance requested for ${lr.number}. Accounts has been told.'
                    '${delivered ? ' LR marked Delivered.' : ''}',
        ),
      ),
    );
  }
  return sent;
}

class _BalanceRequestDialog extends ConsumerStatefulWidget {
  final LorryReceipt lr;
  const _BalanceRequestDialog({required this.lr});

  @override
  ConsumerState<_BalanceRequestDialog> createState() =>
      _BalanceRequestDialogState();
}

class _BalanceRequestDialogState extends ConsumerState<_BalanceRequestDialog> {
  PodFile? _file;
  String? _error;
  bool _sending = false;

  LorryReceipt get lr => widget.lr;

  Future<void> _send() async {
    final f = _file;
    if (f == null) {
      setState(() => _error = 'Upload the POD to request the balance.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final after = await ref
          .read(lrListProvider.notifier)
          .requestBalance(
            lr.id,
            lr.version,
            fileName: f.name,
            bytes: f.bytes,
            filePath: f.bytes == null ? f.path : null,
          );
      if (mounted) Navigator.of(context).pop(after);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requested = lr.isBalanceRequested;
    final f = _file;
    return AlertDialog(
      title: Text(
        requested ? 'Replace POD — ${lr.number}' : 'Request balance payment',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!requested)
              Text(
                'LR ${lr.number}. Take a photo of the POD (proof of '
                'delivery) or upload a photo / PDF. Accounts will see it under '
                '"Balance Requested" and pay the transporter balance.',
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              )
            else ...[
              Text(
                'Balance requested on ${formatDate(lr.balanceRequestedAt!)}. '
                'Uploading a new POD replaces the current one; Accounts is '
                'told again.',
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              PodButtons(lr: lr, small: true),
            ],
            const SizedBox(height: 14),
            const Text(
              'POD (required)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.slate,
              ),
            ),
            const SizedBox(height: 6),
            PodPicker(
              lrNumber: lr.number,
              file: f,
              enabled: !_sending,
              onPicked: (p) => setState(() => _file = p),
              onError: (e) => setState(() => _error = e),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          kind: BtnKind.ghost,
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: requested ? 'Replace POD' : 'Request balance',
          icon: Icons.send_rounded,
          loading: _sending,
          // Disabled until a POD is chosen: it is mandatory.
          onPressed: _sending || f == null ? null : _send,
        ),
      ],
    );
  }
}

/// "View POD" / "Download POD" for an LR whose balance was requested. Used on
/// the Accounts card, the LR detail page and the request dialog. Renders
/// nothing when the LR has no POD on its request.
class PodButtons extends ConsumerWidget {
  final LorryReceipt lr;
  final bool small;
  const PodButtons({super.key, required this.lr, this.small = false});

  Future<({List<int> bytes, String fileName, String mimeType})> _fetch(
    WidgetRef ref,
  ) {
    return ref
        .read(lrRepositoryProvider)
        .downloadAttachment(
          lr.id,
          lr.balanceRequestPodId!,
          fallbackName: 'POD-${lr.number.replaceAll('/', '-')}',
        );
  }

  Future<void> _view(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = await _fetch(ref);
      final mime = f.mimeType.isEmpty ? mimeForName(f.fileName) : f.mimeType;
      openFileInBrowser(f.bytes, mime, f.fileName);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not open the POD: ${friendlyErrorMessage(e)}'),
        ),
      );
    }
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = await _fetch(ref);
      await ExportService.shareBytes(f.bytes, f.fileName);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not download the POD: ${friendlyErrorMessage(e)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((lr.balanceRequestPodId ?? '').isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        TextButton.icon(
          onPressed: () => _view(context, ref),
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: Text('View POD', style: TextStyle(fontSize: small ? 12 : 13)),
        ),
        TextButton.icon(
          onPressed: () => _download(context, ref),
          icon: const Icon(Icons.download_rounded, size: 16),
          label: Text(
            'Download POD',
            style: TextStyle(fontSize: small ? 12 : 13),
          ),
        ),
      ],
    );
  }
}
