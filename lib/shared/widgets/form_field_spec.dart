import 'package:flutter/material.dart';

enum FieldType { text, multiline, number, email, dropdown }

class FormFieldSpec {
  final String name;
  final String label;
  final FieldType type;
  final bool required;
  final String? initialValue;
  final List<String>? options;
  final int? maxLength;
  final String? hint;
  final IconData? icon;
  final bool uppercase;
  final String? Function(String?)? validator;

  const FormFieldSpec({
    required this.name,
    required this.label,
    this.type = FieldType.text,
    this.required = false,
    this.initialValue,
    this.options,
    this.maxLength,
    this.hint,
    this.icon,
    this.uppercase = false,
    this.validator,
  });
}
