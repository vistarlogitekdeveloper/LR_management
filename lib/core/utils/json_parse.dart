/// Tolerant JSON number parsing. PostgreSQL `NUMERIC`/`DECIMAL` and `BIGINT`
/// columns are serialized as JSON **strings** (e.g. "12000.00"), while
/// `INTEGER` comes back as a number. These helpers accept either form so model
/// parsing never throws a String-is-not-a-num error.
double asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  final s = v.toString();
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? 0;
}
