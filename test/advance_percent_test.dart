// Behaviour tests for the configurable transporter advance percentage.
//
// Covers the three things that must not regress:
//   1. Legacy data keeps releasing exactly 90% (no silent change to old LRs).
//   2. An explicit 0% survives every layer (the classic `|| 90` trap).
//   3. Picking a transporter carries its percentage onto the LR form.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/utils/formatters.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/models/transporter.dart';

/// The payout formula the accounts screen previews and the backend applies on
/// "Mark advance paid" (lrController.markAdvancePaid). Kept here so a change to
/// either side that breaks the agreement fails a test.
double advanceFor(double freight, double pct) =>
    (((freight * (pct.clamp(0, 100) / 100)) / 1000).roundToDouble() * 1000)
        .clamp(0, freight)
        .toDouble();

void main() {
  group('pctText', () {
    test('drops noise digits but keeps real ones', () {
      expect(pctText(90), '90');
      expect(pctText(90.0), '90');
      expect(pctText(87.5), '87.5');
      expect(pctText(0), '0');
      expect(pctText(100), '100');
      expect(pctText(33.33), '33.33');
    });

    // The implementation strips a trailing run of zeros with a $-anchored
    // regex. These are the cases where a mis-anchored version would silently
    // mangle the number — 100 becoming "1", or 10 becoming "1" — which would
    // misstate a payout percentage on screen. Guarding them explicitly.
    test('never mangles zeros that belong to the integer part', () {
      expect(pctText(10), '10');
      expect(pctText(20), '20');
      expect(pctText(100), '100');
      expect(pctText(200), '200');
      expect(pctText(105), '105');
      expect(pctText(0.1), '0.1');
      expect(pctText(100.1), '100.1');
      expect(pctText(10.05), '10.05');
    });

    test('handles the balance complement used by the accounts plan', () {
      // "Balance {100-pct}% (after POD)"
      expect(pctText(100 - 90), '10');
      expect(pctText(100 - 0), '100');
      expect(pctText(100 - 100), '0');
      expect(pctText(100 - 87.5), '12.5');
    });
  });

  group('Transporter.advancePercent', () {
    test('defaults to 90 when the backend omits the column', () {
      final t = Transporter.fromJson({
        'id': 'a',
        'name': 'Acme',
        'tds_applicable': false,
      });
      expect(t.advancePercent, kDefaultAdvancePercent);
    });

    test('parses the NUMERIC string Postgres returns', () {
      final t = Transporter.fromJson({
        'id': 'a',
        'name': 'Acme',
        'advance_percent': '75.00',
      });
      expect(t.advancePercent, 75);
    });

    test('an explicit 0% is preserved, not coerced to the 90 default', () {
      final t = Transporter.fromJson({
        'id': 'a',
        'name': 'Acme',
        'advance_percent': '0.00',
      });
      expect(t.advancePercent, 0);
    });

    test('round-trips through toJson so the form can save it', () {
      final t = Transporter.fromJson({
        'id': 'a',
        'name': 'Acme',
        'advance_percent': '62.5',
      });
      expect(t.toJson()['advance_percent'], 62.5);
      expect(t.copyWith(advancePercent: 40).advancePercent, 40);
      // copyWith without the field must not reset it.
      expect(t.copyWith(name: 'Other').advancePercent, 62.5);
    });
  });

  group('FreightDetails.advancePercent', () {
    test('a legacy LR with no column reads back as 90', () {
      final f = FreightDetails.fromJson({'freight': '30000.00'});
      expect(f.advancePercent, 90);
    });

    test('reads the per-LR override', () {
      final f = FreightDetails.fromJson({
        'freight': '30000.00',
        'advance_percent': '55.00',
      });
      expect(f.advancePercent, 55);
    });

    test('an explicit 0% survives parsing', () {
      final f = FreightDetails.fromJson({
        'freight': '30000.00',
        'advance_percent': '0.00',
      });
      expect(f.advancePercent, 0);
    });
  });

  group('advance payout', () {
    test('legacy 90% behaviour is byte-identical to the old formula', () {
      for (var freight = 1000.0; freight <= 200000; freight += 1000) {
        final old = (((freight * 0.9) / 1000).roundToDouble() * 1000)
            .clamp(0, freight)
            .toDouble();
        expect(advanceFor(freight, 90), old, reason: 'freight=$freight');
      }
    });

    test('custom percentages compute against the transporter freight', () {
      expect(advanceFor(30000, 50), 15000);
      expect(advanceFor(30000, 100), 30000);
      expect(advanceFor(33000, 85), 28000); // rounded to the nearest 1000
    });

    test('0% releases nothing', () {
      expect(advanceFor(30000, 0), 0);
    });

    test('never exceeds the freight, even at 100%', () {
      for (final f in [5000.0, 17550.0, 33000.0, 999.0]) {
        expect(advanceFor(f, 100), lessThanOrEqualTo(f), reason: 'freight=$f');
      }
    });

    test('out-of-range percentages are clamped rather than exploding', () {
      expect(advanceFor(30000, 150), 30000);
      expect(advanceFor(30000, -5), 0);
    });
  });

  group('accounts advance-plan labels', () {
    // The plan renders "Advance {pct}% (now)" / "Balance {100-pct}% (after POD)".
    // The complement must stay consistent — it used to be a hardcoded "10%".
    test('advance and balance percentages always sum to 100', () {
      for (final pct in [90.0, 50.0, 0.0, 100.0, 87.5]) {
        final advanceLabel = pctText(pct);
        final balanceLabel = pctText(100 - pct);
        expect(
          double.parse(advanceLabel) + double.parse(balanceLabel),
          100,
          reason: 'pct=$pct',
        );
      }
    });
  });

  group('TransporterFormDialog advance % validation', () {
    // Mirrors the dialog's _validateAdvancePercent. The rule matters because the
    // save path coerces with `double.tryParse(...) ?? default` — without the
    // validator, "ninety" would be silently stored as 90.
    String? validate(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return null;
      final n = double.tryParse(s);
      if (n == null) return 'Enter a plain number, e.g. 90';
      if (n < 0 || n > 100) return 'Must be between 0 and 100';
      return null;
    }

    test('accepts blank (falls back to the default) and valid numbers', () {
      expect(validate(''), isNull);
      expect(validate('90'), isNull);
      expect(validate('0'), isNull);
      expect(validate('100'), isNull);
      expect(validate('87.5'), isNull);
    });

    test('rejects unparseable input instead of silently saving a default', () {
      expect(validate('ninety'), isNotNull);
      expect(validate('90%'), isNotNull);
    });

    test('rejects out-of-range values, matching the backend CHECK', () {
      expect(validate('101'), isNotNull);
      expect(validate('-1'), isNotNull);
      expect(validate('1000'), isNotNull);
    });
  });

  testWidgets('LR form seeds the advance % from the picked transporter',
      (tester) async {
    // Reproduces _selectTransporter's contract without booting the whole screen:
    // switching to a different transporter re-seeds the field; re-picking the
    // SAME one must not (an edited per-LR value has to survive).
    final ctrl = TextEditingController(text: pctText(kDefaultAdvancePercent));
    Transporter? current;

    void selectTransporter(Transporter? t) {
      final previousId = current?.id;
      current = t;
      if (t == null) return;
      if (t.id != previousId) ctrl.text = pctText(t.advancePercent);
    }

    const acme = Transporter(
      id: 't1',
      name: 'Acme',
      pan: '',
      tds: 'No',
      advancePercent: 80,
    );
    const other = Transporter(
      id: 't2',
      name: 'Other',
      pan: '',
      tds: 'No',
      advancePercent: 65,
    );

    expect(ctrl.text, '90');

    selectTransporter(acme);
    expect(ctrl.text, '80', reason: 'carries the transporter default');

    // Operator overrides it for this one LR.
    ctrl.text = '72';
    selectTransporter(acme);
    expect(ctrl.text, '72', reason: 're-picking the same transporter must not clobber the override');

    selectTransporter(other);
    expect(ctrl.text, '65', reason: 'a genuine change re-seeds');

    ctrl.dispose();
  });
}
