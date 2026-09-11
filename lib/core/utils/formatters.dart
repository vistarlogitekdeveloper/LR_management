import 'package:intl/intl.dart';

// Formatters and patterns are hoisted to top-level finals so they are built
// once, not on every call. Constructing a DateFormat / NumberFormat / RegExp
// is comparatively expensive, and these run per row across hundreds of LR cards.
final _inrFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
// Same locale and symbol, two decimals — see inrPaise().
final _inrPaiseFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);
final _dateFormat = DateFormat('dd MMM yyyy');
final _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
final _time24Format = DateFormat('HH:mm');
final _trailingZeros = RegExp(r'\.?0+$');

String inr(num? value) => _inrFormatter.format(value ?? 0);

/// Rupees WITH paise — for documents where the figures must foot exactly.
///
/// [inr] rounds to whole rupees, which is right for dashboards and LR cards but
/// wrong on a tax invoice: dropping paise makes the displayed sub total plus the
/// displayed tax stop equalling the displayed total, and the printed PDF (which
/// always carries two decimals) then disagrees with the screen.
String inrPaise(num? value) => _inrPaiseFormatter.format(value ?? 0);

/// A percentage without noise digits: 90 -> "90", 87.5 -> "87.5".
/// Used wherever an advance share is shown or seeded into a text field, so a
/// whole percentage never renders as "90.0" or "90.00".
String pctText(num? value) {
  final v = (value ?? 0).toDouble();
  // Two decimals is the column's scale (NUMERIC(5,2)); trim what it doesn't need.
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(_trailingZeros, '');
}

String formatDate(DateTime d) => _dateFormat.format(d);

String formatDateTime(DateTime d) => _dateTimeFormat.format(d);

/// 24-hour clock time only (e.g. 15:15). Used where date and time are shown in
/// separate columns (the Excel export).
String formatTime24(DateTime d) => _time24Format.format(d);

int ageingDays(DateTime from, {DateTime? to}) {
  final end = to ?? DateTime.now();
  final diff = end.difference(from).inDays;
  return diff < 0 ? 0 : diff;
}
