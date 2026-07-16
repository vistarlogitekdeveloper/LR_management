import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/confirm_dialog.dart';

class MasterActions {
  MasterActions._();

  static Future<bool> confirmDelete({
    required BuildContext context,
    required String label,
  }) {
    return showConfirmDialog(
      context: context,
      title: 'Delete $label?',
      message:
          'This will remove $label from the master. Linked LRs are not affected.',
      confirmLabel: 'Delete',
    );
  }

  /// Extracts a human-readable message from any error (ApiException-aware). For a
  /// backend VALIDATION_ERROR it unpacks Joi's field-level details so the user
  /// sees exactly which field is wrong (e.g. "Pay Type is required") instead of
  /// a generic "Validation error".
  static String messageFor(Object error) {
    final api = _asApi(error);
    if (api == null) return error.toString();
    return _validationSummary(api) ?? api.message;
  }

  static ApiException? _asApi(Object error) {
    if (error is DioException && error.error is ApiException) {
      return error.error as ApiException;
    }
    if (error is ApiException) return error;
    return null;
  }

  // Maps backend field keys to the labels the user sees on the form, so a Joi
  // error names the field rather than the raw column. Unknown keys are
  // humanised (e.g. pay_type_id → Pay Type) as a fallback.
  static const Map<String, String> _fieldLabels = {
    'lr_date': 'LR Date',
    'customer_name': 'Customer Name',
    'consignor_id': 'Consignor',
    'consignee_id': 'Consignee',
    'vehicle_id': 'Vehicle',
    'transporter_id': 'Transporter',
    'driver_id': 'Driver',
    'route_id': 'Route',
    'pay_type_id': 'Pay Type',
    'delivery_type_id': 'Delivery Type',
    'capacity_id': 'Vehicle Capacity',
    'freight': 'Freight',
    'from_city': 'From',
    'to_city': 'To',
    'distance_km': 'Distance',
    'base_rate': 'Transporter Rate',
    'customer_rate': 'Customer Rate',
    'role_id': 'Role',
    'region_id': 'Region',
    'account_no': 'Account No',
  };

  /// Turns a VALIDATION_ERROR's Joi details (`[{path, message}]`) into a
  /// readable, field-named message. Returns null when there's nothing to unpack
  /// (so the caller falls back to the plain message).
  static String? _validationSummary(ApiException api) {
    if (api.code != 'VALIDATION_ERROR') return null;
    final body = api.details;
    final raw = body is Map ? body['details'] : body;
    if (raw is! List || raw.isEmpty) return null;
    final lines = <String>[];
    for (final d in raw) {
      if (d is! Map) continue;
      final path = (d['path'] ?? '').toString();
      final key = path.contains('.') ? path.split('.').last : path;
      final label = _fieldLabels[path] ?? _fieldLabels[key] ?? _humanize(key);
      var msg = (d['message'] ?? '').toString();
      if (msg.isEmpty) {
        msg = '$label is invalid';
      } else {
        // Joi wraps the field in double quotes: "pay_type_id" is required.
        msg = msg
            .replaceAll('"$path"', label)
            .replaceAll('"$key"', label)
            .replaceAll('"', '');
      }
      lines.add(msg);
    }
    if (lines.isEmpty) return null;
    final shown = lines.take(5).map((m) => '• $m').toList();
    if (lines.length > 5) shown.add('• …and ${lines.length - 5} more');
    return shown.join('\n');
  }

  static String _humanize(String s) {
    final base = s.endsWith('_id') ? s.substring(0, s.length - 3) : s;
    return base
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static void showError(BuildContext context, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(messageFor(error)),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
  }
}
