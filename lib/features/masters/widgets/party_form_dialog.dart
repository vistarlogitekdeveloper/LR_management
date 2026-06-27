import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/party.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../providers/master_providers.dart';
import 'master_actions.dart';

/// Party create/edit form. Unlike the other text-only masters it carries a
/// multi-select Roles group (Consignor / Consignee / Customer, at least one
/// required) that drives which LR field the party appears in — so it has its
/// own dialog instead of the generic MasterFormDialog. Returns the saved
/// [Party] (so an inline LR flow can select it), or null if cancelled.
class PartyFormDialog extends ConsumerStatefulWidget {
  final Party? existing;
  final bool defaultCustomer;
  const PartyFormDialog({super.key, this.existing, this.defaultCustomer = false});

  static Future<Party?> show(
    BuildContext context, {
    Party? existing,
    bool defaultCustomer = false,
  }) {
    return showDialog<Party>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: PartyFormDialog(
            existing: existing,
            defaultCustomer: defaultCustomer,
          ),
        ),
      ),
    );
  }

  @override
  ConsumerState<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<PartyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _gst;
  late final TextEditingController _city;
  late final TextEditingController _address;
  late final TextEditingController _contact;
  late final TextEditingController _mobile;
  late final TextEditingController _email;

  late bool _isConsignor;
  late bool _isConsignee;
  late bool _isCustomer;
  bool _roleError = false;
  bool _saving = false;

  Party? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final p = _existing;
    _name = TextEditingController(text: p?.name ?? '');
    _gst = TextEditingController(text: p?.gst ?? '');
    _city = TextEditingController(text: p?.city ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _contact = TextEditingController(text: p?.contact ?? '');
    _mobile = TextEditingController(text: p?.mobile ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _isConsignor = p?.isConsignor ?? false;
    _isConsignee = p?.isConsignee ?? false;
    _isCustomer = p?.isCustomer ?? (p == null && widget.defaultCustomer);
  }

  @override
  void dispose() {
    for (final c in [_name, _gst, _city, _address, _contact, _mobile, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasRole => _isConsignor || _isConsignee || _isCustomer;

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    if (!_hasRole) setState(() => _roleError = true);
    if (!formOk || !_hasRole) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = ref.read(partiesProvider.notifier);
      final base = Party(
        id: _existing?.id ?? '',
        name: _name.text.trim(),
        gst: _gst.text.trim(),
        city: _city.text.trim(),
        address: _address.text.trim(),
        contact: _contact.text.trim(),
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
        isConsignor: _isConsignor,
        isConsignee: _isConsignee,
        isCustomer: _isCustomer,
        version: _existing?.version ?? 0,
      );
      final saved = _existing == null ? await n.add(base) : await n.update(base);
      if (!mounted) return;
      navigator.pop(saved);
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
                        child: _text(_name, 'Party Name', required: true),
                      ),
                      SizedBox(
                        width: w,
                        child: _text(_gst, 'GST Number', maxLength: 15, upper: true),
                      ),
                      SizedBox(width: w, child: _text(_city, 'City')),
                      SizedBox(width: w, child: _text(_contact, 'Contact Person')),
                      SizedBox(
                        width: w,
                        child: _text(_mobile, 'Mobile', maxLength: 12),
                      ),
                      SizedBox(width: w, child: _text(_email, 'Email')),
                      SizedBox(
                        width: c.maxWidth,
                        child: _text(_address, 'Address', maxLines: 2),
                      ),
                      SizedBox(width: c.maxWidth, child: _rolesField()),
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
            _existing == null ? 'New Party' : 'Edit Party',
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
    int maxLines = 1,
    bool upper = false,
  }) {
    return LabeledField(
      label: label,
      required: required,
      child: TextFormField(
        controller: c,
        maxLength: maxLength,
        maxLines: maxLines,
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

  Widget _rolesField() {
    return LabeledField(
      label: 'Roles',
      required: true,
      errorText: _roleError && !_hasRole
          ? 'Select at least one role — Consignor, Consignee or Customer.'
          : null,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _roleChip('Consignor', _isConsignor, (v) => _isConsignor = v),
          _roleChip('Consignee', _isConsignee, (v) => _isConsignee = v),
          _roleChip('Customer', _isCustomer, (v) => _isCustomer = v),
        ],
      ),
    );
  }

  Widget _roleChip(String label, bool selected, ValueChanged<bool> set) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: _saving
          ? null
          : (v) => setState(() {
              set(v);
              if (_hasRole) _roleError = false;
            }),
      selectedColor: AppColors.plum.withValues(alpha: 0.14),
      checkmarkColor: AppColors.plum,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? AppColors.plum : AppColors.slate,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? AppColors.plum : AppColors.line,
        ),
      ),
      backgroundColor: Colors.white,
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
