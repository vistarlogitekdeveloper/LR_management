import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../providers/master_providers.dart';
import '../utils/transporter_kyc.dart';
import 'master_actions.dart';

/// Transporter create/edit form. Unlike the other masters this needs bank
/// details plus a blank-cheque / passbook upload, so it has its own dialog
/// instead of the generic MasterFormDialog.
class TransporterFormDialog extends ConsumerStatefulWidget {
  final Transporter? existing;

  /// Pre-fills the name on a fresh form — used when the transporter picker's
  /// "Add new" entry is tapped after typing a name that wasn't in the list.
  final String? initialName;

  const TransporterFormDialog({super.key, this.existing, this.initialName});

  /// Returns the saved transporter (created or updated), or null if the form
  /// was dismissed — so a caller can select it straight away.
  static Future<Transporter?> show(
    BuildContext context, {
    Transporter? existing,
    String? initialName,
  }) {
    return showDialog<Transporter>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: TransporterFormDialog(
            existing: existing,
            initialName: initialName,
          ),
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
  late final TextEditingController _aadhaar;
  late final TextEditingController _mobile;
  late final TextEditingController _bank;
  late final TextEditingController _holder;
  late final TextEditingController _accNo;
  late final TextEditingController _ifsc;
  late final TextEditingController _advancePct;
  late String _tds;

  PlatformFile? _picked;
  PlatformFile? _pickedTds;
  PlatformFile? _pickedPan;
  PlatformFile? _pickedAadhaar;
  bool _saving = false;

  // Inline "Required" messages for the mandatory uploads — they aren't form
  // fields, so they can't be covered by _formKey.validate().
  String? _chequeError;
  String? _panDocError;
  String? _aadhaarDocError;

  /// KYC (Aadhaar number, contact number, PAN photo, Aadhaar photo) is required
  /// when ADDING a transporter, and optional when editing one that predates
  /// those fields. Blocking a legacy edit would mean an urgent bank correction
  /// waits on someone finding an Aadhaar card — the backend keeps both columns
  /// nullable for the same reason (migration 127).
  bool get _kycRequired => _existing == null;

  Transporter? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final t = _existing;
    _name = TextEditingController(text: t?.name ?? widget.initialName ?? '');
    _pan = TextEditingController(text: t?.pan ?? '');
    _aadhaar = TextEditingController(text: t?.aadhaar ?? '');
    _mobile = TextEditingController(text: t?.mobile ?? '');
    _bank = TextEditingController(text: t?.bankName ?? '');
    _holder = TextEditingController(text: t?.accountHolder ?? '');
    _accNo = TextEditingController(text: t?.accountNo ?? '');
    _ifsc = TextEditingController(text: t?.ifsc ?? '');
    // Whole percentages show as "90", not "90.0".
    _advancePct = TextEditingController(
      text: pctText(t?.advancePercent ?? kDefaultAdvancePercent),
    );
    _tds = t?.tds ?? 'Yes';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _pan,
      _aadhaar,
      _mobile,
      _bank,
      _holder,
      _accNo,
      _ifsc,
      _advancePct,
    ]) {
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
    setState(() {
      _picked = picked.files.first;
      _chequeError = null;
    });
  }

  /// One picker for both KYC photos — the accepted types and the "clear the
  /// inline error on pick" behaviour are identical to the cheque's.
  Future<void> _pickKyc({required bool pan}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() {
      if (pan) {
        _pickedPan = picked.files.first;
        _panDocError = null;
      } else {
        _pickedAadhaar = picked.files.first;
        _aadhaarDocError = null;
      }
    });
  }

  Future<void> _viewKyc({required bool pan}) async {
    final existing = _existing;
    if (existing == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(transportersRepositoryProvider)
          .downloadDocument(existing.id, type: pan ? 'pan' : 'aadhaar');
      final name = pan ? existing.panFileName : existing.aadhaarFileName;
      final fallback = pan ? 'pan' : 'aadhaar';
      openFileInBrowser(
        bytes,
        _mimeForName(name),
        name.isEmpty ? fallback : name,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
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

  Future<void> _pickTds() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() {
      _pickedTds = picked.files.first;
    });
  }

  Future<void> _viewTds() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(transportersRepositoryProvider)
          .downloadDocument(_existing!.id, type: 'tds');
      final name = _existing!.tdsFileName;
      openFileInBrowser(bytes, _mimeForName(name), name.isEmpty ? 'tds' : name);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState!.validate();
    // Blank cheque / passbook is mandatory; the TDS attachment is optional.
    final chequeMissing = _picked == null && !(_existing?.hasDocument ?? false);
    // The two KYC photos are mandatory on a NEW transporter only — see
    // _kycRequired. On a legacy edit they stay optional so the save is not
    // blocked, but an already-uploaded one still counts as present.
    final panMissing =
        _kycRequired &&
        _pickedPan == null &&
        !(_existing?.hasPanDocument ?? false);
    final aadhaarDocMissing =
        _kycRequired &&
        _pickedAadhaar == null &&
        !(_existing?.hasAadhaarDocument ?? false);
    if (!formValid || chequeMissing || panMissing || aadhaarDocMissing) {
      setState(() {
        _chequeError = chequeMissing ? 'Required' : null;
        _panDocError = panMissing ? 'Required' : null;
        _aadhaarDocError = aadhaarDocMissing ? 'Required' : null;
      });
      return;
    }
    setState(() {
      _chequeError = null;
      _panDocError = null;
      _aadhaarDocError = null;
      _saving = true;
    });
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
            // Digits only, so the server's 12-digit check sees what the user
            // meant when they typed the spaced "1234 5678 9012" off the card.
            aadhaar: digitsOnly(_aadhaar.text),
            mobile: _mobile.text.trim(),
            tds: _tds,
            advancePercent: _advancePercentValue,
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
            // Digits only, so the server's 12-digit check sees what the user
            // meant when they typed the spaced "1234 5678 9012" off the card.
            aadhaar: digitsOnly(_aadhaar.text),
            mobile: _mobile.text.trim(),
            tds: _tds,
            advancePercent: _advancePercentValue,
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
          // On web PlatformFile.path is unavailable and throws when read; we
          // upload via bytes (picked with withData: true), so only fall back to
          // path when bytes are absent (native).
          filePath: _picked!.bytes == null ? _picked!.path : null,
        );
      }
      if (_pickedTds != null) {
        t = await repo.uploadDocument(
          t.id,
          fileName: _pickedTds!.name,
          bytes: _pickedTds!.bytes,
          filePath: _pickedTds!.bytes == null ? _pickedTds!.path : null,
          type: 'tds',
        );
      }
      // Same endpoint as the cheque, different ?type — the backend stores each
      // under its own keys in the bank_account JSONB (transporterDocKeys).
      if (_pickedPan != null) {
        t = await repo.uploadDocument(
          t.id,
          fileName: _pickedPan!.name,
          bytes: _pickedPan!.bytes,
          filePath: _pickedPan!.bytes == null ? _pickedPan!.path : null,
          type: 'pan',
        );
      }
      if (_pickedAadhaar != null) {
        t = await repo.uploadDocument(
          t.id,
          fileName: _pickedAadhaar!.name,
          bytes: _pickedAadhaar!.bytes,
          filePath: _pickedAadhaar!.bytes == null ? _pickedAadhaar!.path : null,
          type: 'aadhaar',
        );
      }
      await ref.read(transportersProvider.notifier).refresh();
      if (!mounted) return;
      // Success feedback via the app-level messenger so it survives the dialog
      // closing. The refresh above already updated the list in place, so no
      // page reload is needed.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _existing == null
                ? 'Transporter "${t.name}" added successfully'
                : 'Transporter "${t.name}" updated successfully',
          ),
          backgroundColor: AppColors.ok,
        ),
      );
      navigator.pop(t);
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
                      SizedBox(
                        width: w,
                        child: _text(
                          _aadhaar,
                          'Aadhaar Number',
                          required: _kycRequired,
                          number: true,
                          maxLength: 14, // 12 digits + two typed spaces
                          hint: '12 digits',
                          validator: validateAadhaar,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(
                          _mobile,
                          'Contact Number',
                          required: _kycRequired,
                          number: true,
                          maxLength: 15,
                          hint: '10-digit mobile',
                          validator: validateContactNumber,
                        ),
                      ),
                      SizedBox(width: w, child: _tdsField()),
                      SizedBox(
                        width: w,
                        child: _text(
                          _advancePct,
                          'Advance %',
                          number: true,
                          hint: 'Default ${pctText(kDefaultAdvancePercent)}',
                          validator: _validateAdvancePercent,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(_bank, 'Bank Name', required: true),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(
                          _holder,
                          'Account Holder Name',
                          required: true,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(_accNo, 'Account No', required: true),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(
                          _ifsc,
                          'IFSC Code',
                          upper: true,
                          required: true,
                        ),
                      ),
                      SizedBox(width: c.maxWidth, child: _chequeField()),
                      SizedBox(
                        width: c.maxWidth,
                        child: _kycDocField(pan: true),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: _kycDocField(pan: false),
                      ),
                      SizedBox(width: c.maxWidth, child: _tdsAttachmentField()),
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
    bool number = false,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return LabeledField(
      label: label,
      required: required,
      child: TextFormField(
        controller: c,
        maxLength: maxLength,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textCapitalization: upper
            ? TextCapitalization.characters
            : TextCapitalization.none,
        decoration: InputDecoration(counterText: '', hintText: hint),
        validator: (v) {
          final s = v?.trim() ?? '';
          if (required && s.isEmpty) return 'Required';
          return validator?.call(v);
        },
      ),
    );
  }

  /// Validates the advance share. Blank is allowed and means "use the standard
  /// ${kDefaultAdvancePercent}%". Rejecting an unparseable value matters here:
  /// the save path coerces with `double.tryParse(...) ?? default`, so "90%" or
  /// "ninety" would otherwise be silently stored as 90 — a 200 OK that quietly
  /// ignored what the user typed. The 0-100 bound mirrors the backend CHECK
  /// constraint so the server can never reject what the form accepted.
  /// The advance share to save. Blank falls back to the standard default; the
  /// value is already known-parseable and in range because _validateAdvancePercent
  /// gated the save.
  double get _advancePercentValue =>
      double.tryParse(_advancePct.text.trim()) ?? kDefaultAdvancePercent;

  String? _validateAdvancePercent(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // optional — falls back to the default
    final n = double.tryParse(s);
    if (n == null) return 'Enter a plain number, e.g. 90';
    if (n < 0 || n > 100) return 'Must be between 0 and 100';
    return null;
  }

  Widget _tdsField() => LabeledField(
    label: 'TDS Applicable',
    required: true,
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
      required: true,
      errorText: _chequeError,
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

  /// The PAN-card / Aadhaar-card photo row. One widget for both because they
  /// differ only in label, which slot they read and which ?type they upload to.
  Widget _kycDocField({required bool pan}) {
    final picked = pan ? _pickedPan : _pickedAadhaar;
    final existing = _existing;
    final hasExisting = pan
        ? (existing?.hasPanDocument ?? false)
        : (existing?.hasAadhaarDocument ?? false);
    final storedName = existing == null
        ? ''
        : (pan ? existing.panFileName : existing.aadhaarFileName);
    return LabeledField(
      label: pan ? 'PAN Card Photo' : 'Aadhaar Card Photo',
      required: _kycRequired,
      errorText: pan ? _panDocError : _aadhaarDocError,
      child: Row(
        children: [
          AppButton(
            label: picked == null && !hasExisting
                ? 'Upload file'
                : 'Replace file',
            kind: BtnKind.ghost,
            icon: Icons.upload_file_outlined,
            onPressed: _saving ? null : () => _pickKyc(pan: pan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              picked != null
                  ? picked.name
                  : hasExisting
                  ? (storedName.isEmpty ? 'Document on file' : storedName)
                  : 'JPG, PNG, WEBP or PDF',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
          ),
          if (picked == null && hasExisting)
            TextButton.icon(
              onPressed: _saving ? null : () => _viewKyc(pan: pan),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View'),
            ),
          if (picked != null)
            IconButton(
              tooltip: 'Remove selection',
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      if (pan) {
                        _pickedPan = null;
                      } else {
                        _pickedAadhaar = null;
                      }
                    }),
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.slate,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  Widget _tdsAttachmentField() {
    final picked = _pickedTds;
    final hasExisting = _existing?.hasTdsDocument ?? false;
    return LabeledField(
      label: 'TDS Attachment',
      child: Row(
        children: [
          AppButton(
            label: picked == null && !hasExisting
                ? 'Upload file'
                : 'Replace file',
            kind: BtnKind.ghost,
            icon: Icons.upload_file_outlined,
            onPressed: _saving ? null : _pickTds,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              picked != null
                  ? picked.name
                  : hasExisting
                  ? (_existing!.tdsFileName.isEmpty
                        ? 'Document on file'
                        : _existing!.tdsFileName)
                  : 'JPG, PNG, WEBP or PDF',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
          ),
          if (picked == null && hasExisting)
            TextButton.icon(
              onPressed: _saving ? null : _viewTds,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View'),
            ),
          if (picked != null)
            IconButton(
              tooltip: 'Remove selection',
              onPressed: _saving
                  ? null
                  : () => setState(() => _pickedTds = null),
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.slate,
                size: 18,
              ),
            ),
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
