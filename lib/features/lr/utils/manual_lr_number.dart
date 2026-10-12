/// Manual LR numbers — the client half of the server's
/// utils/manualLrNumber.js. Create LR may take a number of the operator's own
/// instead of the region counter's; it must start with [manualLrPrefix] and be
/// unique (the server checks that: GET /lrs/number-check, and again on save).
library;

const manualLrPrefix = 'LR/Manual/';

/// lrs.number is VARCHAR(40); the part after the prefix gets the rest.
const manualLrMaxLength = 40;
const manualLrRestMaxLength = manualLrMaxLength - manualLrPrefix.length;

final _restRe = RegExp(r'^[A-Z0-9][A-Z0-9/_.-]*$');

bool isManualLrNumber(String number) =>
    number.toLowerCase().startsWith(manualLrPrefix.toLowerCase());

/// What the operator typed after the prefix, upper-cased; a pasted full
/// number ("LR/Manual/PUN/1") gives its rest ("PUN/1").
String manualLrRest(String typed) {
  final t = typed.trim();
  final rest = isManualLrNumber(t) ? t.substring(manualLrPrefix.length) : t;
  return rest.toUpperCase();
}

/// Why [rest] (the part after the prefix) cannot be used, or null when the
/// format is right. Uniqueness is the server's to say.
String? manualLrRestError(String rest) {
  final r = rest.trim();
  if (r.isEmpty) {
    return 'Type the number after $manualLrPrefix — for example PUN/0001.';
  }
  if (r.length > manualLrRestMaxLength) {
    return 'Too long — at most $manualLrRestMaxLength characters after '
        '$manualLrPrefix.';
  }
  if (!_restRe.hasMatch(r) || r.contains('//') || r.endsWith('/')) {
    return 'Use only letters, digits and / - _ . — start with a letter or '
        'digit, no "//", not ending in "/".';
  }
  return null;
}

final _regionCodeRe = RegExp(r'^[A-Za-z]{2,6}$');

/// The region short code embedded in an automatic LR number
/// ({prefix}/{REGION}/{FY}/{seq}), or null. A manual number carries none —
/// "Manual" would otherwise read as a region called MANUAL.
String? regionCodeFromLrNumber(String number) {
  if (isManualLrNumber(number)) return null;
  final parts = number.split('/');
  if (parts.length > 1 && _regionCodeRe.hasMatch(parts[1])) {
    return parts[1].toUpperCase();
  }
  return null;
}
