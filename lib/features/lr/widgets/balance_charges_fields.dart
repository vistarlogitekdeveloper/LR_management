import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Detention / express charges sent with the balance POD (migration 222).
/// Only for users the super admin allowed (AppUser.canAddExtraCharges); the
/// server refuses them from anyone else. A blank box means "leave as it is".
///
/// [onChanged] gets the charges to send (only the boxes that hold an amount),
/// or null while a box holds something that is not an amount of 0 or more.
class BalanceChargesFields extends StatefulWidget {
  final bool enabled;
  final ValueChanged<Map<String, String>?> onChanged;

  const BalanceChargesFields({
    super.key,
    required this.onChanged,
    this.enabled = true,
  });

  /// The charges in [detention] / [express], or null if one is not an amount.
  static Map<String, String>? valuesOf(String detention, String express) {
    final out = <String, String>{};
    for (final (key, raw) in [
      ('detention_charges', detention.trim()),
      ('express_charges', express.trim()),
    ]) {
      if (raw.isEmpty) continue;
      final v = double.tryParse(raw);
      if (v == null || v < 0) return null;
      out[key] = raw;
    }
    return out;
  }

  @override
  State<BalanceChargesFields> createState() => _BalanceChargesFieldsState();
}

class _BalanceChargesFieldsState extends State<BalanceChargesFields> {
  final _detention = TextEditingController();
  final _express = TextEditingController();

  @override
  void dispose() {
    _detention.dispose();
    _express.dispose();
    super.dispose();
  }

  void _changed(String _) => widget.onChanged(
    BalanceChargesFields.valuesOf(_detention.text, _express.text),
  );

  Widget _box(String label, TextEditingController c, Key key) => Expanded(
    child: TextField(
      key: key,
      controller: c,
      enabled: widget.enabled,
      onChanged: _changed,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        isDense: true,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Extra charges (optional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.slate,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _box('Detention', _detention, const ValueKey('balance-detention')),
            const SizedBox(width: 10),
            _box('Express', _express, const ValueKey('balance-express')),
          ],
        ),
      ],
    );
  }
}
