import 'package:intl/intl.dart';

final _inrFormatter = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

String inr(num? value) => _inrFormatter.format(value ?? 0);

String formatDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

String formatDateTime(DateTime d) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(d);

int ageingDays(DateTime from, {DateTime? to}) {
  final end = to ?? DateTime.now();
  final diff = end.difference(from).inDays;
  return diff < 0 ? 0 : diff;
}
