import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../shared/models/driver.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../providers/master_providers.dart';
import '../utils/transporter_kyc.dart';
import 'master_actions.dart';

/// Driver create/edit form. Drivers now carry an Aadhaar / PAN number and a
/// scan of each, and the generic MasterFormDialog has no file support — its
/// `onSave` returns a bool, so it cannot express "create the row, then attach
/// files to the id that came back". Hence a bespoke dialog, modelled on
/// TransporterFormDialog.
///
/// EVERY ONE OF THE FOUR NEW INPUTS IS OPTIONAL, on a new driver and on an old
/// one alike — unlike the transporter form, which makes its KYC mandatory when
/// adding. Only the format is checked, and only when something was typed: a
/// half-entered Aadhaar is a mistake worth catching, an absent one is not. The
/// three fields that were already required (name, mobile, licence number) are
/// unchanged.
class DriverFormDialog extends ConsumerStatefulWidget {
  final Driver? existing;

  /// Pre-fills the name on a fresh form — used when a driver picker's "Add new"
  /// entry is tapped after typing a name that wasn't in the list.
  final String? initialName;

  const DriverFormDialog({super.key, this.existing, this.initialName});

  /// Returns the saved driver (created or updated), or null if the form was
  /// dismissed — so a caller can select it straight away.
  static Future<Driver?> show(
    BuildContext context, {
    Driver? existing,
    String? initialName,
  }) {
    return showDialog<Driver>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: DriverFormDialog(existing: existing, initialName: initialName),
        ),
      ),
    );
  }

  @override
  ConsumerState<DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends ConsumerState<DriverFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _mobile;
  late final TextEditingController _licenseNo;
  late final TextEditingController _licenseExpiry;
  late final TextEditingController _aadhaar;
  late final TextEditingController _pan;
  late final TextEditingController _address;

  PlatformFile? _pickedAadhaar;
  PlatformFile? _pickedPan;
  bool _saving = false;

  /// The row this dialog has already written, set once a save gets past the
  /// create/update. It exists because the save is two-step: if the row lands
  /// and an upload then fails, the dialog stays open, and a second Save must
  /// PATCH what was just created rather than create a second driver. Not
  /// assigned through setState — nothing rebuilds on the success path (the
  /// dialog pops) and the failure path calls setState immediately after.
  Driver? _saved;

  // Deliberately no inline upload errors here, unlike the transporter form:
  // neither attachment is mandatory, so there is nothing to flag.

  Driver? get _existing => widget.existing;

  /// The driver the form is editing as things stand — the partially saved row
  /// after a failed upload, else the one passed in. Drives the attachment rows
  /// so they report what is really on the server.
  Driver? get _current => _saved ?? widget.existing;

  @override
  void initState() {
    super.initState();
    final d = _existing;
    _name = TextEditingController(text: d?.name ?? widget.initialName ?? '');
    _mobile = TextEditingController(text: d?.mobile ?? '');
    _licenseNo = TextEditingController(text: d?.licenseNo ?? '');
    _licenseExpiry = TextEditingController(text: d?.licenseExpiry ?? '');
    _aadhaar = TextEditingController(text: d?.aadhaar ?? '');
    _pan = TextEditingController(text: d?.pan ?? '');
    _address = TextEditingController(text: d?.address ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _mobile,
      _licenseNo,
      _licenseExpiry,
      _aadhaar,
      _pan,
      _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// One picker for both scans — they differ only in which slot they fill. Same
  /// accepted types as the transporter uploads, and `withData: true` so the web
  /// build has bytes to post (PlatformFile.path is unavailable there).
  Future<void> _pickKyc({required bool pan}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    if (!mounted) return;
    setState(() {
      if (pan) {
        _pickedPan = picked.files.first;
      } else {
        _pickedAadhaar = picked.files.first;
      }
    });
  }

  Future<void> _viewKyc({required bool pan}) async {
    // _current, not widget.existing: the View button appears as soon as a scan
    // is on the server, which includes one attached by a save that then failed
    // on the second upload.
    final existing = _current;
    if (existing == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(driversRepositoryProvider)
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

  Future<void> _save() async {
    final form = _formKey.currentState;
    // Only the three long-standing required fields and the two format rules can
    // stop a save; there is no presence check to run on top of the form.
    if (form == null || !form.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final expiry = _licenseExpiry.text.trim();
    try {
      final repo = ref.read(driversRepositoryProvider);
      final existing = _current;
      Driver d;
      if (existing == null) {
        d = await repo.create(
          Driver(
            // The server generates the id; a create sends none.
            id: '',
            name: _name.text.trim(),
            mobile: _mobile.text.trim(),
            licenseNo: _licenseNo.text.trim(),
            licenseExpiry: expiry.isEmpty ? null : expiry,
            address: _address.text.trim(),
            // Digits only, so the server's 12-digit check sees what the user
            // meant when they typed the spaced "1234 5678 9012" off the card.
            aadhaar: digitsOnly(_aadhaar.text),
            pan: _pan.text.trim().toUpperCase(),
          ),
        );
      } else {
        d = await repo.update(
          existing.copyWith(
            name: _name.text.trim(),
            mobile: _mobile.text.trim(),
            licenseNo: _licenseNo.text.trim(),
            licenseExpiry: expiry,
            address: _address.text.trim(),
            aadhaar: digitsOnly(_aadhaar.text),
            pan: _pan.text.trim().toUpperCase(),
          ),
        );
      }
      _saved = d;
      // Two-step by necessity: a file can only be attached to a row that
      // exists, so the save above has to land first and the uploads go against
      // the id it returned. Each response carries the refreshed `documents`
      // blob, so `d` stays current without a refetch.
      final aadhaarFile = _pickedAadhaar;
      if (aadhaarFile != null) {
        d = await repo.uploadDocument(
          d.id,
          type: 'aadhaar',
          fileName: aadhaarFile.name,
          bytes: aadhaarFile.bytes,
          // On web PlatformFile.path is unavailable and throws when read; we
          // upload via bytes (picked with withData: true), so only fall back to
          // path when bytes are absent (native).
          filePath: aadhaarFile.bytes == null ? aadhaarFile.path : null,
        );
        // Kept in step for the same reason as above: if the PAN upload now
        // fails, a retry must patch this version, not the one from before the
        // attachment bumped it.
        _saved = d;
      }
      final panFile = _pickedPan;
      if (panFile != null) {
        d = await repo.uploadDocument(
          d.id,
          type: 'pan',
          fileName: panFile.name,
          bytes: panFile.bytes,
          filePath: panFile.bytes == null ? panFile.path : null,
        );
      }
      await ref.read(driversProvider.notifier).refresh();
      if (!mounted) return;
      // Success feedback via the app-level messenger so it survives the dialog
      // closing. The refresh above already updated the list in place, so no
      // page reload is needed.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            // What the user opened, not what this attempt did — a retry after
            // a failed upload still added the driver from their point of view.
            _existing == null
                ? 'Driver "${d.name}" added successfully'
                : 'Driver "${d.name}" updated successfully',
          ),
          backgroundColor: AppColors.ok,
        ),
      );
      navigator.pop(d);
    } catch (e) {
      // The row itself may already be saved — only an upload failed. Refresh so
      // the list shows it instead of hiding a driver that really was written.
      // refresh() swallows its own errors, so it cannot throw out of a catch.
      if (_saved != null) await ref.read(driversProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The title says what the user opened, the attachment rows say what is on
    // the server right now — those differ only after a partial save.
    final current = _current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          title: _existing == null ? 'New Driver' : 'Edit Driver',
          onClose: () => Navigator.pop(context),
        ),
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
                        child: _LabeledTextField(
                          controller: _name,
                          label: 'Driver Name',
                          required: true,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _LabeledTextField(
                          controller: _mobile,
                          label: 'Mobile',
                          required: true,
                          number: true,
                          maxLength: 12,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _LabeledTextField(
                          controller: _licenseNo,
                          label: 'License Number',
                          required: true,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _LabeledTextField(
                          controller: _licenseExpiry,
                          label: 'License Expiry (YYYY-MM-DD)',
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _LabeledTextField(
                          controller: _aadhaar,
                          label: 'Aadhaar Number',
                          number: true,
                          maxLength: 14, // 12 digits + two typed spaces
                          hint: '12 digits (optional)',
                          validator: validateAadhaar,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _LabeledTextField(
                          controller: _pan,
                          label: 'PAN',
                          upper: true,
                          maxLength: 10,
                          hint: 'AAAPA1234A (optional)',
                          validator: validatePan,
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: _LabeledTextField(
                          controller: _address,
                          label: 'Address',
                          multiline: true,
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: _DocumentField(
                          label: 'Aadhaar Attachment',
                          picked: _pickedAadhaar,
                          storedName: current?.aadhaarFileName ?? '',
                          hasExisting: current?.hasAadhaarDocument ?? false,
                          enabled: !_saving,
                          onPick: () => _pickKyc(pan: false),
                          onView: () => _viewKyc(pan: false),
                          onClear: () => setState(() => _pickedAadhaar = null),
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: _DocumentField(
                          label: 'PAN Attachment',
                          picked: _pickedPan,
                          storedName: current?.panFileName ?? '',
                          hasExisting: current?.hasPanDocument ?? false,
                          enabled: !_saving,
                          onPick: () => _pickKyc(pan: true),
                          onView: () => _viewKyc(pan: true),
                          onClear: () => setState(() => _pickedPan = null),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        _Footer(
          saving: _saving,
          onCancel: () => Navigator.pop(context),
          onSave: _save,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: AppColors.slate),
        ),
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(label: 'Cancel', kind: BtnKind.ghost, onPressed: onCancel),
        const SizedBox(width: 10),
        AppButton(
          label: saving ? 'Saving…' : 'Save',
          icon: Icons.save_outlined,
          // Disabled while in flight, so a double tap cannot start a second
          // create.
          onPressed: saving ? null : onSave,
        ),
      ],
    ),
  );
}

/// A labelled text field. [required] drives both the asterisk and the only
/// presence check in this form — the KYC fields leave it off, so they can never
/// report "Required", while [validator] still runs on whatever was typed.
class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.controller,
    required this.label,
    this.required = false,
    this.maxLength,
    this.upper = false,
    this.number = false,
    this.multiline = false,
    this.hint,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final int? maxLength;
  final bool upper;
  final bool number;
  final bool multiline;
  final String? hint;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      required: required,
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        maxLines: multiline ? 3 : 1,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : multiline
            ? TextInputType.multiline
            : TextInputType.text,
        textCapitalization: upper
            ? TextCapitalization.characters
            : TextCapitalization.none,
        // textCapitalization only hints the soft keyboard, so it does nothing
        // on web or desktop; the formatter is what actually keeps the PAN
        // upper-case as it is typed, on every platform.
        inputFormatters: upper ? _upperCaseOnly : null,
        decoration: InputDecoration(counterText: '', hintText: hint),
        validator: (v) {
          final s = v?.trim() ?? '';
          if (required && s.isEmpty) return 'Required';
          return validator?.call(v);
        },
      ),
    );
  }
}

/// The pick / view / replace / remove row for one optional scan. Identical in
/// behaviour to the transporter dialog's KYC rows, minus the inline "Required"
/// slot — nothing here is mandatory.
class _DocumentField extends StatelessWidget {
  const _DocumentField({
    required this.label,
    required this.picked,
    required this.storedName,
    required this.hasExisting,
    required this.enabled,
    required this.onPick,
    required this.onView,
    required this.onClear,
  });

  final String label;

  /// The file chosen in this session and not yet uploaded, if any.
  final PlatformFile? picked;

  /// Name of the file already on the server, '' when there is none.
  final String storedName;
  final bool hasExisting;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onView;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final file = picked;
    return LabeledField(
      label: label,
      child: Row(
        children: [
          AppButton(
            label: file == null && !hasExisting
                ? 'Upload file'
                : 'Replace file',
            kind: BtnKind.ghost,
            icon: Icons.upload_file_outlined,
            onPressed: enabled ? onPick : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file != null
                  ? file.name
                  : hasExisting
                  ? (storedName.isEmpty ? 'Document on file' : storedName)
                  : 'JPG, PNG, WEBP or PDF',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
          ),
          if (file == null && hasExisting)
            TextButton.icon(
              onPressed: enabled ? onView : null,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View'),
            ),
          if (file != null)
            IconButton(
              tooltip: 'Remove selection',
              onPressed: enabled ? onClear : null,
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
}

/// Upper-cases what is typed without moving the caret — the length never
/// changes, so the incoming selection stays valid. Built once at the top level
/// rather than per rebuild.
final _upperCaseOnly = <TextInputFormatter>[
  TextInputFormatter.withFunction(
    (_, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
  ),
];

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
