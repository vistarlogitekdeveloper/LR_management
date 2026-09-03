import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'app_button.dart';
import 'form_field_spec.dart';
import 'labeled_field.dart';
import './searchable_field.dart';

class MasterFormDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<FormFieldSpec> fields;
  final Map<String, String> initial;
  final Future<bool> Function(Map<String, String> values) onSave;

  const MasterFormDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.fields,
    this.initial = const {},
    required this.onSave,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    String? subtitle,
    required List<FormFieldSpec> fields,
    Map<String, String> initial = const {},
    required Future<bool> Function(Map<String, String> values) onSave,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: MasterFormDialog(
            title: title,
            subtitle: subtitle,
            fields: fields,
            initial: initial,
            onSave: onSave,
          ),
        ),
      ),
    );
  }

  @override
  State<MasterFormDialog> createState() => _MasterFormDialogState();
}

/// Forces typed text to uppercase (e.g. vehicle registration numbers).
class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _MasterFormDialogState extends State<MasterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ctrls;
  late final Map<String, String?> _dropdownValues;

  /// Names of required dropdowns left empty on the last save attempt.
  final _dropdownErrors = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {};
    _dropdownValues = {};
    for (final f in widget.fields) {
      final initial = widget.initial[f.name] ?? f.initialValue ?? '';
      if (f.type == FieldType.dropdown) {
        // Only preselect a value we were actually handed. Falling back to the
        // first option silently substitutes an arbitrary value for a field the
        // caller left empty — and saving the form then persists that guess.
        _dropdownValues[f.name] = initial.isNotEmpty ? initial : null;
      } else {
        _ctrls[f.name] = TextEditingController(text: initial);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    // SearchableField is not a FormField, so Form.validate() never sees the
    // dropdowns — a required one has to be checked by hand or it submits empty.
    final missing = widget.fields
        .where(
          (f) =>
              f.type == FieldType.dropdown &&
              f.required &&
              (_dropdownValues[f.name] ?? '').isEmpty,
        )
        .map((f) => f.name)
        .toSet();
    final textOk = _formKey.currentState!.validate();
    if (missing.isNotEmpty) {
      setState(
        () => _dropdownErrors
          ..clear()
          ..addAll(missing),
      );
      return;
    }
    setState(() => _dropdownErrors.clear());
    if (!textOk) return;
    setState(() => _saving = true);
    final values = <String, String>{};
    for (final f in widget.fields) {
      values[f.name] = f.type == FieldType.dropdown
          ? (_dropdownValues[f.name] ?? '')
          : _ctrls[f.name]!.text.trim();
    }
    final ok = await widget.onSave(values);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.slate),
              ),
            ],
          ),
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
                  return Wrap(
                    spacing: spacing,
                    runSpacing: 14,
                    children: [
                      for (final f in widget.fields)
                        SizedBox(
                          width: f.type == FieldType.multiline
                              ? c.maxWidth
                              : (c.maxWidth - spacing * (cols - 1)) / cols,
                          child: _buildField(f),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Container(
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
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildField(FormFieldSpec f) {
    if (f.type == FieldType.dropdown) {
      return LabeledField(
        label: f.label,
        required: f.required,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SearchableField<String>(
              value: _dropdownValues[f.name],
              options: f.options ?? const <String>[],
              labelOf: (o) => o,
              hintText: f.hint ?? 'Select ${f.label}',
              dialogTitle: 'Select ${f.label}',
              clearable: !f.required,
              onChanged: (v) => setState(() {
                _dropdownValues[f.name] = v;
                _dropdownErrors.remove(f.name);
              }),
            ),
            if (_dropdownErrors.contains(f.name))
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Required',
                  style: TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }

    return LabeledField(
      label: f.label,
      required: f.required,
      child: TextFormField(
        controller: _ctrls[f.name],
        keyboardType: switch (f.type) {
          FieldType.number => TextInputType.number,
          FieldType.email => TextInputType.emailAddress,
          FieldType.multiline => TextInputType.multiline,
          _ => TextInputType.text,
        },
        textCapitalization: f.uppercase
            ? TextCapitalization.characters
            : TextCapitalization.none,
        inputFormatters: f.uppercase ? const [_UpperCaseTextFormatter()] : null,
        maxLines: f.type == FieldType.multiline ? 3 : 1,
        maxLength: f.maxLength,
        decoration: InputDecoration(
          hintText: f.hint,
          counterText: '',
          prefixIcon: f.icon == null ? null : Icon(f.icon, size: 18),
        ),
        validator: (value) {
          final v = value?.trim() ?? '';
          if (f.required && v.isEmpty) return 'Required';
          if (f.validator != null) return f.validator!(v);
          return null;
        },
      ),
    );
  }
}
