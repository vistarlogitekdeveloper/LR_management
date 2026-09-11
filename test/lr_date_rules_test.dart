// Back-dating rules for the LR date field: one calendar day, no more.
//
// The interesting cases are all calendar boundaries — the 1st of a month, the
// 1st of January (where the year rolls too), and the end of February in a leap
// year versus a common one. The rule is enforced in the create form's date
// picker, so these tests are the only place the arithmetic is actually checked.
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/lr/utils/lr_date_rules.dart';

void main() {
  group('lrDateFloor', () {
    test('mid-month, the floor is yesterday', () {
      // A working Tuesday: one day back is allowed, two is not.
      expect(lrDateFloor(DateTime(2026, 9, 15)), DateTime(2026, 9, 14));
    });

    test('on the 2nd, the floor is the 1st', () {
      expect(lrDateFloor(DateTime(2026, 9, 2)), DateTime(2026, 9, 1));
    });

    test("on the 1st, the floor is last month's last day", () {
      // One day back is one day back, month end or not: raising an LR on
      // 1 September must still offer 31 August.
      expect(lrDateFloor(DateTime(2026, 9, 1)), DateTime(2026, 8, 31));
      expect(
        isLrDateAllowed(DateTime(2026, 8, 31), DateTime(2026, 9, 1)),
        isTrue,
      );
      // But only the one day — the 30th is two days back.
      expect(
        isLrDateAllowed(DateTime(2026, 8, 30), DateTime(2026, 9, 1)),
        isFalse,
      );
    });

    test('a 30-day month end is reached correctly', () {
      // 1 July follows a 30-day June; the floor must be the 30th, not a 31st
      // that does not exist.
      expect(lrDateFloor(DateTime(2026, 7, 1)), DateTime(2026, 6, 30));
    });

    test('the 1st of January reaches back into last year', () {
      expect(lrDateFloor(DateTime(2026, 1, 1)), DateTime(2025, 12, 31));
      expect(
        isLrDateAllowed(DateTime(2025, 12, 31), DateTime(2026, 1, 1)),
        isTrue,
      );
      expect(
        isLrDateAllowed(DateTime(2025, 12, 30), DateTime(2026, 1, 1)),
        isFalse,
      );
    });

    test('the 1st of March lands on the real end of February', () {
      // 2026 is not a leap year, so the floor is the 28th.
      expect(lrDateFloor(DateTime(2026, 3, 1)), DateTime(2026, 2, 28));
      // 2028 is, so the floor is the 29th — never a non-existent 30 February.
      expect(lrDateFloor(DateTime(2028, 3, 1)), DateTime(2028, 2, 29));
      expect(
        isLrDateAllowed(DateTime(2028, 2, 29), DateTime(2028, 3, 1)),
        isTrue,
      );
      expect(
        isLrDateAllowed(DateTime(2028, 2, 28), DateTime(2028, 3, 1)),
        isFalse,
      );
    });

    test('two days back is refused on an ordinary day', () {
      final now = DateTime(2026, 9, 15);
      expect(isLrDateAllowed(DateTime(2026, 9, 14), now), isTrue);
      expect(isLrDateAllowed(DateTime(2026, 9, 13), now), isFalse);
    });

    test('the time of day never moves the floor', () {
      // Just before midnight and just after must agree, or the field would
      // silently change what it accepts during a night shift.
      expect(
        lrDateFloor(DateTime(2026, 9, 15, 23, 59, 59)),
        DateTime(2026, 9, 14),
      );
      expect(
        lrDateFloor(DateTime(2026, 9, 15, 0, 0, 1)),
        DateTime(2026, 9, 14),
      );
      // A candidate carrying a time is judged on its calendar day.
      expect(
        isLrDateAllowed(DateTime(2026, 9, 14, 23, 30), DateTime(2026, 9, 15)),
        isTrue,
      );
    });

    test('today is always selectable', () {
      for (final now in [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 30),
        DateTime(2026, 1, 1),
      ]) {
        expect(isLrDateAllowed(now, now), isTrue, reason: '$now');
      }
    });
  });

  group('lrDateFloor with an LR already dated earlier (edit mode)', () {
    test('an older stored date lowers the floor to itself', () {
      // showDatePicker asserts when initialDate < firstDate, so editing last
      // month's LR would crash the field if the floor ignored the stored date.
      final now = DateTime(2026, 9, 15);
      final stored = DateTime(2026, 7, 4);
      expect(lrDateFloor(now, existing: stored), stored);
      expect(isLrDateAllowed(stored, now, existing: stored), isTrue);
    });

    test('it lowers the floor no further than the stored date', () {
      final now = DateTime(2026, 9, 15);
      final stored = DateTime(2026, 7, 4);
      expect(
        isLrDateAllowed(DateTime(2026, 7, 3), now, existing: stored),
        isFalse,
      );
    });

    test('a stored date inside the window leaves the floor alone', () {
      final now = DateTime(2026, 9, 15);
      expect(
        lrDateFloor(now, existing: DateTime(2026, 9, 15)),
        DateTime(2026, 9, 14),
      );
      expect(
        lrDateFloor(now, existing: DateTime(2026, 9, 14)),
        DateTime(2026, 9, 14),
      );
    });

    test('the stored time of day is ignored, only its calendar day counts', () {
      final now = DateTime(2026, 9, 15);
      expect(
        lrDateFloor(now, existing: DateTime(2026, 7, 4, 18, 45)),
        DateTime(2026, 7, 4),
      );
    });

    test('a null existing date gives the strict floor', () {
      expect(
        lrDateFloor(DateTime(2026, 9, 1), existing: null),
        DateTime(2026, 8, 31),
      );
    });
  });
}
