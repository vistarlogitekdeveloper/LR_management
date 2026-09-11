/// Back-dating rules for an LR's own date.
///
/// Kept out of the form widget so the boundary arithmetic — which is all
/// month-end and year-end edge cases — can be unit-tested without pumping a
/// 3,000-line screen.
library;

/// Midnight of [d], discarding any time component.
DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The earliest LR date the create form offers, given "now" is [now].
///
/// One rule: **at most one calendar day back**. An LR is raised when the vehicle
/// is dispatched, so back-dating further means the paperwork stops matching the
/// movement it documents.
///
/// The day before is taken on the calendar, not on the clock, so it crosses a
/// month or year end normally: on 1 September the floor is 31 August, on
/// 1 January it is 31 December of the previous year, and on 1 March 2028 it is
/// the 29th of February. A night-shift entry made just after midnight therefore
/// still reaches the shift that has only just ended.
///
/// [existing] is the date already stored on the LR being edited, if any. A
/// stored date earlier than the floor lowers it, for two reasons:
/// `showDatePicker` asserts when `initialDate` is before `firstDate`, and an
/// operator correcting an older LR must still be able to open the field at all.
/// New LRs pass null and get the strict one-day floor.
DateTime lrDateFloor(DateTime now, {DateTime? existing}) {
  // Built from components rather than subtract(Duration(days: 1)) so the day
  // arithmetic stays calendar-correct: DateTime(y, m, 0) normalises to the last
  // day of the previous month instead of landing 23 or 25 hours away.
  var floor = DateTime(now.year, now.month, now.day - 1);

  if (existing != null) {
    final stored = _dayOf(existing);
    if (stored.isBefore(floor)) floor = stored;
  }
  return floor;
}

/// Whether [candidate] is a date the create form would accept as an LR date.
///
/// Mirrors [lrDateFloor] so the same rule can be asserted in a test or reused by
/// a validator without re-deriving the boundary. Dates in the future are not
/// this rule's concern — it only bounds how far back an LR may be dated.
bool isLrDateAllowed(DateTime candidate, DateTime now, {DateTime? existing}) =>
    !_dayOf(candidate).isBefore(lrDateFloor(now, existing: existing));
