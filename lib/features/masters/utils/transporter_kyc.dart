/// Aadhaar / contact-number rules for the transporter master.
///
/// Kept out of the form widget so they can be unit-tested directly, and because
/// they have to stay in step with the server: `LrmTransporter`'s
/// `isAadhaarNumber` and `isContactNumber` validators are the authority, and
/// this file mirrors them exactly. A form that accepts something the server
/// rejects loses the user's work at the very end of the save.
library;

final _nonDigits = RegExp(r'[^0-9]');
final _allSameDigits = RegExp(r'^(\d)\1{11}$');
final _leadingCountryOrTrunk = RegExp(r'^(?:91|0)');
final _pan = RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$');

/// Every digit in [value], dropping the spaces people type when copying the
/// number off the card ("1234 5678 9012").
String digitsOnly(String? value) => (value ?? '').replaceAll(_nonDigits, '');

/// Null when [value] is an acceptable Aadhaar, else the message to show.
///
/// BLANK IS ACCEPTED HERE. Presence is a separate question, answered by the
/// form's `required` flag — which is on when adding a transporter and off when
/// editing one that predates these fields, so a legacy row can still be saved.
String? validateAadhaar(String? value) {
  // Blankness is decided on the RAW text, not on the digits. Checking the
  // stripped value instead would read "abcdefghijkl" as empty and wave it
  // through as "not provided" — and the field's own required check cannot catch
  // it either, because the box is not empty.
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return null;
  final digits = digitsOnly(raw);
  if (digits.length != 12) return 'Aadhaar must be 12 digits';
  // 111111111111 and friends are what gets typed to get past a required field,
  // and no real Aadhaar looks like that.
  if (_allSameDigits.hasMatch(digits)) return 'Not a valid Aadhaar';
  return null;
}

/// Null when [value] is an acceptable PAN, else the message to show.
///
/// Shared with the DRIVER master — `LrmDriver`'s `isPanNumber` validator is the
/// authority and this mirrors it exactly, including the wording, so the two
/// never disagree about the same value. (`LrmTransporter` leaves `pan`
/// unvalidated, so the transporter form does not use this rule today.)
///
/// BLANK IS ACCEPTED, for the same reason as [validateAadhaar]: presence is the
/// form's `required` flag to decide, and on drivers a PAN is optional outright.
String? validatePan(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return null;
  // Five letters, four digits, one letter (AAAPA1234A). Either case is taken —
  // the form upper-cases as you type, but a value pasted in from elsewhere may
  // arrive lower-case and is not worth refusing over.
  if (!_pan.hasMatch(raw)) return 'PAN must be 10 characters, e.g. AAAPA1234A';
  return null;
}

/// Null when [value] is an acceptable contact number, else the message.
///
/// Ten digits after an optional +91 or a leading 0, because that is how numbers
/// get pasted. Blank is accepted for the same reason as [validateAadhaar].
String? validateContactNumber(String? value) {
  // Same reasoning as validateAadhaar: emptiness is judged on the raw text so
  // a value made entirely of letters is refused rather than read as absent.
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return null;
  final digits = digitsOnly(raw);
  final local = digits.replaceFirst(_leadingCountryOrTrunk, '');
  if (local.length != 10) return 'Enter a 10-digit mobile number';
  return null;
}
