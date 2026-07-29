import 'package:intl/intl.dart';

final _inrFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String inr(num? value) => _inrFormatter.format(value ?? 0);

/// A percentage without noise digits: 90 -> "90", 87.5 -> "87.5".
/// Used wherever an advance share is shown or seeded into a text field, so a
/// whole percentage never renders as "90.0" or "90.00".
String pctText(num? value) {
  final v = (value ?? 0).toDouble();
  // Two decimals is the column's scale (NUMERIC(5,2)); trim what it doesn't need.
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

String formatDateTime(DateTime d) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(d);

/// 24-hour clock time only (e.g. 15:15). Used where date and time are shown in
/// separate columns (the Excel export).
String formatTime24(DateTime d) => DateFormat('HH:mm').format(d);

int ageingDays(DateTime from, {DateTime? to}) {
  final end = to ?? DateTime.now();
  final diff = end.difference(from).inDays;
  return diff < 0 ? 0 : diff;
}
