import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../providers/master_providers.dart';
import 'master_actions.dart';

/// Transporter create/edit form. Unlike the other masters this needs bank
/// details plus a blank-cheque / passbook upload, so it has its own dialog
/// instead of the generic MasterFormDialog.
class TransporterFormDialog extends ConsumerStatefulWidget {
  final Transporter? existing;
  const TransporterFormDialog({super.key, this.existing});

  static Future<bool?> show(BuildContext context, {Transporter? existing}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: TransporterFormDialog(existing: existing),
        ),
      ),
    );
  }

  @override
  ConsumerState<TransporterFormDialog> createState() =>
      _TransporterFormDialogState();
}

class _TransporterFormDialogState extends ConsumerState<TransporterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _pan;
  late final TextEditingController _bank;
  late final TextEditingController _holder;
  late final TextEditingController _accNo;
  late final TextEditingController _ifsc;
  late String _tds;

  PlatformFile? _picked;
  bool _saving = false;

  Transporter? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final t = _existing;
    _name = TextEditingController(text: t?.name ?? '');
    _pan = TextEditingController(text: t?.pan ?? '');
    _bank = TextEditingController(text: t?.bankName ?? '');
    _holder = TextEditingController(text: t?.accountHolder ?? '');
    _accNo = TextEditingController(text: t?.accountNo ?? '');
    _ifsc = TextEditingController(text: t?.ifsc ?? '');
    _tds = t?.tds ?? 'Yes';
  }

  @override
  void dispose() {
    for (final c in [_name, _pan, _bank, _holder, _accNo, _ifsc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() => _picked = picked.files.first);
  }

  Future<void> _viewExisting() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(transportersRepositoryProvider)
          .downloadDocument(_existing!.id);
      final name = _existing!.chequeFileName;
      openFileInBrowser(
        bytes,
        _mimeForName(name),
        name.isEmpty ? 'document' : name,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo = ref.read(transportersRepositoryProvider);
      Transporter t;
      if (_existing == null) {
        t = await repo.create(
          Transporter(
            id: '',
            name: _name.text.trim(),
            pan: _pan.text.trim(),
            tds: _tds,
            bankName: _bank.text.trim(),
            accountHolder: _holder.text.trim(),
            accountNo: _accNo.text.trim(),
            ifsc: _ifsc.text.trim(),
          ),
        );
      } else {
        t = await repo.update(
          _existing!.copyWith(
            name: _name.text.trim(),
            pan: _pan.text.trim(),
            tds: _tds,
            bankName: _bank.text.trim(),
            accountHolder: _holder.text.trim(),
            accountNo: _accNo.text.trim(),
            ifsc: _ifsc.text.trim(),
          ),
        );
      }
      if (_picked != null) {
        t = await repo.uploadDocument(
          t.id,
          fileName: _picked!.name,
          bytes: _picked!.bytes,
          filePath: _picked!.path,
        );
      }
      await ref.read(transportersProvider.notifier).refresh();
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 560 ? 2 : 1;
                  const spacing = 14.0;
                  final w = (c.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: w,
                        child: _text(_name, 'Transporter Name', required: true),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(
                          _pan,
                          'PAN',
                          required: true,
                          maxLength: 10,
                          upper: true,
                        ),
                      ),
                      SizedBox(width: w, child: _tdsField()),
                      SizedBox(width: w, child: _text(_bank, 'Bank Name')),
                      SizedBox(
                        width: w,
                        child: _text(_holder, 'Account Holder Name'),
                      ),
                      SizedBox(width: w, child: _text(_accNo, 'Account No')),
                      SizedBox(
                        width: w,
                        child: _text(_ifsc, 'IFSC Code', upper: true),
                      ),
                      SizedBox(width: c.maxWidth, child: _chequeField()),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _existing == null ? 'New Transporter' : 'Edit Transporter',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.slate),
        ),
      ],
    ),
  );

  Widget _text(
    TextEditingController c,
    String label, {
    bool required = false,
    int? maxLength,
    bool upper = false,
  }) {
    return LabeledField(
      label: label,
      required: required,
      child: TextFormField(
        controller: c,
        maxLength: maxLength,
        textCapitalization: upper
            ? TextCapitalization.characters
            : TextCapitalization.none,
        decoration: const InputDecoration(counterText: ''),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  Widget _tdsField() => LabeledField(
    label: 'TDS Applicable',
    child: SearchableField<String>(
      value: _tds,
      options: const ['Yes', 'No'],
      labelOf: (o) => o,
      hintText: 'Select',
      onChanged: (v) => setState(() => _tds = v ?? 'Yes'),
    ),
  );

  Widget _chequeField() {
    final picked = _picked;
    final hasExisting = _existing?.hasDocument ?? false;
    return LabeledField(
      label: 'Blank Cheque / Passbook Photo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppButton(
                label: picked == null && !hasExisting
                    ? 'Upload file'
                    : 'Replace file',
                kind: BtnKind.ghost,
                icon: Icons.upload_file_outlined,
                onPressed: _saving ? null : _pickFile,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  picked != null
                      ? picked.name
                      : hasExisting
                      ? _existing!.chequeFileName.isEmpty
                            ? 'Document on file'
                            : _existing!.chequeFileName
                      : 'JPG, PNG, WEBP or PDF',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (picked == null && hasExisting)
                TextButton.icon(
                  onPressed: _saving ? null : _viewExisting,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
              if (picked != null)
                IconButton(
                  tooltip: 'Remove selection',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _picked = null),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.slate,
                    size: 18,
                  ),
                ),
            ],
          ),
          _ocrCheck(),
        ],
      ),
    );
  }

  /// Live cross-check of the entered IFSC / account against the OCR readout of
  /// the uploaded cheque. Updates as the user edits the fields. Only shown once
  /// the background OCR has run on a saved transporter's cheque.
  Widget _ocrCheck() {
    final t = _existing;
    if (t == null || !t.ocrDone) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_ifsc, _accNo]),
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.plum.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.plum.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 15,
                    color: AppColors.plum,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Cheque OCR check',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _ocrLine('IFSC', t.ocrIfsc, t.ifscMatchesOcr(_ifsc.text)),
              _ocrLine(
                'Account No',
                t.ocrAccountNo,
                t.accountMatchesOcr(_accNo.text),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ocrLine(String label, String ocrValue, bool? match) {
    if (ocrValue.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '$label not detected on the cheque image',
          style: const TextStyle(color: AppColors.slate, fontSize: 11.5),
        ),
      );
    }
    final color = match == true
        ? AppColors.ok
        : match == false
        ? AppColors.orange
        : AppColors.slate;
    final icon = match == true
        ? Icons.check_circle_outline
        : match == false
        ? Icons.warning_amber_rounded
        : Icons.remove_circle_outline;
    final msg = match == true
        ? '$label matches the cheque'
        : match == false
        ? '$label differs — cheque shows $ocrValue'
        : '$label on cheque: $ocrValue';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(msg, style: TextStyle(color: color, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _footer() => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          label: 'Cancel',
          kind: BtnKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 10),
        AppButton(
          label: _saving ? 'Saving…' : 'Save',
          icon: Icons.save_outlined,
          onPressed: _saving ? null : _save,
        ),
      ],
    ),
  );
}

String _mimeForName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    default:
      return 'application/octet-stream';
  }
}
