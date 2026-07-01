// Client-side mirror of the backend LR-number formatter
// (vistar_CRM `utils/lrNumbering.js`). Used only for the live "Next LR will
// be:" preview on the numbering screen — the backend remains the source of
// truth for the actual issued number.

/// Indian financial year (Apr 1 – Mar 31) as a "YY-YY" label, e.g. 26-27.
/// A date on/after April 1 belongs to the year it starts; Jan–Mar belong to the
/// previous April's year.
String indianFinancialYear(DateTime date) {
  final startYear = date.month >= 4 ? date.year : date.year - 1;
  final endYear = startYear + 1;
  final s = (startYear % 100).toString().padLeft(2, '0');
  final e = (endYear % 100).toString().padLeft(2, '0');
  return '$s-$e';
}

/// Renders an LR number from [template] using the same tokens as the backend:
/// `{prefix}`, `{REGION}` (region short code), `{FY}` (Indian FY), the date
/// tokens `{YYYY}` `{YY}` `{MM}` `{DD}`, and the sequence `{seq}` / `{seq:0Nd}`
/// (e.g. `{seq:05d}` → 00001). [at] defaults to now.
String formatLrNumber(
  String template, {
  required String prefix,
  required String region,
  required int seq,
  DateTime? at,
}) {
  final now = at ?? DateTime.now();
  final withText = template
      .replaceAll('{prefix}', prefix)
      .replaceAll('{REGION}', region)
      .replaceAll('{FY}', indianFinancialYear(now))
      .replaceAll('{YYYY}', now.year.toString())
      .replaceAll('{YY}', (now.year % 100).toString().padLeft(2, '0'))
      .replaceAll('{MM}', now.month.toString().padLeft(2, '0'))
      .replaceAll('{DD}', now.day.toString().padLeft(2, '0'));
  // {seq} or {seq:0Nd}
  return withText.replaceAllMapped(
    RegExp(r'\{seq(?::0(\d+)d)?\}'),
    (m) => seq
        .toString()
        .padLeft(m.group(1) == null ? 0 : int.parse(m.group(1)!), '0'),
  );
}
