import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'app_button.dart';
import 'form_field_spec.dart';
import 'labeled_field.dart';

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

class _MasterFormDialogState extends State<MasterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ctrls;
  late final Map<String, String?> _dropdownValues;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {};
    _dropdownValues = {};
    for (final f in widget.fields) {
      final initial =
          widget.initial[f.name] ?? f.initialValue ?? '';
      if (f.type == FieldType.dropdown) {
        _dropdownValues[f.name] =
            initial.isNotEmpty ? initial : f.options?.firstOrNull;
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
    if (!_formKey.currentState!.validate()) return;
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
                            color: AppColors.slate, fontSize: 12.5),
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
        child: DropdownButtonFormField<String>(
          initialValue: _dropdownValues[f.name],
          isExpanded: true,
          items: [
            for (final opt in f.options ?? const <String>[])
              DropdownMenuItem(value: opt, child: Text(opt)),
          ],
          onChanged: (v) =>
              setState(() => _dropdownValues[f.name] = v),
          validator: f.required
              ? (v) => (v == null || v.isEmpty) ? 'Required' : null
              : null,
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
