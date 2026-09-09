// The Reports "Download Excel" sheet must carry the same column headings as the
// MIS workbook, so the two can be read, compared and pasted side by side.
//
// The MIS names live server-side in
// lr-management/services/misWorkbook.service.js (MIS_COLUMNS). They include
// spellings that look like typos — "Transportor name", "TransportBalance
// Payment" — which are copied verbatim on purpose. These tests pin them so a
// well-meaning cleanup on this side cannot silently break the match; if a
// heading really should change, change MIS first and then this test.
//
// The money cells are pinned here too: this sheet is the fallback for users who
// cannot reach GET /reports/mis.xlsx, so its arithmetic must agree with misRow.
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/reports/services/export_service.dart';
import 'package:lr_management/shared/models/lr_models.dart';

// The real row that exposed the bug: freight 19500, advance 18000, margin 3281.
// freight - advance = 1500 (correct); total - advance = 4781 (the old, wrong
// answer) — the two cannot be confused.
const double _kFreight = 19500;
const double _kAdvance = 18000;
const double _kVistarMargin = 3281;

// Every ancillary head is non-zero on purpose. With them all at zero, `total`
// collapses to freight + margin and the balance assertion below cannot tell
// `freight - advance` apart from `freight + ancillaries - advance` — it would
// pass against a still-wrong implementation. Their sum is 3050, so the model's
// total is 25831 and the OLD wrong balance would be 7831, far from 1500.
const double _kAncillaries = 3050;

LorryReceipt _lr() => LorryReceipt.fromJson({
  'id': 'lr1',
  'number': 'LR/PUN/26-27/00001',
  'lr_date': '2026-07-01',
  // Freight fields are read off the same map by FreightDetails.fromJson. `total`
  // and `balance` are left out so the model computes them exactly as the
  // backend generated columns do.
  'freight': _kFreight,
  'advance': _kAdvance,
  'vistar_margin': _kVistarMargin,
  'door_delivery': 500,
  'handling': 300,
  'insurance': 200,
  'gst': 100,
  'mathadi': 400,
  'collection': 250,
  'additional_freight': 700,
  'halting_charge': 600,
});

Sheet _sheet({
  bool canViewTransporterRate = true,
  bool canViewVistarMargin = true,
  bool canViewCustomerRate = true,
}) {
  final bytes = ExportService.buildLrsWorkbook(
    [_lr()],
    canViewTransporterRate: canViewTransporterRate,
    canViewVistarMargin: canViewVistarMargin,
    canViewCustomerRate: canViewCustomerRate,
  );
  if (bytes == null) fail('buildLrsWorkbook produced no bytes');
  final excel = Excel.decodeBytes(bytes);
  return excel.tables[excel.tables.keys.first]!;
}

List<String> _headers({
  bool canViewTransporterRate = true,
  bool canViewVistarMargin = true,
  bool canViewCustomerRate = true,
}) => _sheet(
  canViewTransporterRate: canViewTransporterRate,
  canViewVistarMargin: canViewVistarMargin,
  canViewCustomerRate: canViewCustomerRate,
).rows.first.map((c) => c?.value?.toString() ?? '').toList();

/// Value of the single data row under [heading].
double _money(String heading) {
  final sheet = _sheet();
  final headers = sheet.rows.first
      .map((c) => c?.value?.toString() ?? '')
      .toList();
  final index = headers.indexOf(heading);
  expect(index, greaterThanOrEqualTo(0), reason: '"$heading" is missing');
  // A whole amount round-trips through the .xlsx as an IntCellValue even though
  // the sheet writes DoubleCellValue, so accept either numeric form.
  final value = switch (sheet.rows[1][index]?.value) {
    IntCellValue(:final value) => value.toDouble(),
    DoubleCellValue(:final value) => value,
    _ => null,
  };
  if (value == null) fail('"$heading" does not hold a number');
  return value;
}

void main() {
  test('shared columns use the MIS workbook spelling', () {
    final headers = _headers();
    for (final name in const [
      'LR No',
      'LR Date',
      'Customer Name (Billing From Vistar)',
      'Transportor name',
      'Vehicle No.',
      'Vehicle Type',
      'Vehicle Capacity',
      'Origin to Destination',
      'Total Transport Charges',
      'Mathadi Charges',
      'Transport Advance Paid',
      'TransportBalance Payment',
      'Vistar Billing Amount',
      'Vistar Margin',
    ]) {
      expect(headers, contains(name), reason: 'MIS heading "$name" is missing');
    }
  });

  test('the pre-MIS headings are gone', () {
    final headers = _headers();
    for (final old in const [
      'Date',
      'Customer Name',
      'Transporter Name',
      'Vehicle',
      'Capacity',
      'Route',
      'Freight',
      'Mathadi',
      'Advance',
      'Balance',
      // The grand-total column was replaced by MIS's Vistar Billing Amount;
      // `total` includes vistar_margin and has no MIS counterpart.
      'Total',
    ]) {
      expect(
        headers,
        isNot(contains(old)),
        reason: '"$old" should now use the MIS heading',
      );
    }
  });

  test('columns with no MIS counterpart keep their own names', () {
    final headers = _headers();
    for (final name in const [
      'Consignor',
      'Consignee',
      'In Date',
      'In Time',
      'Out Date',
      'Out Time',
      'Door Delivery',
      'Handling',
      'Insurance',
      'Pay Type',
      'Status',
      'EWB',
    ]) {
      expect(headers, contains(name), reason: '"$name" should be unchanged');
    }
  });

  test('every heading is unique, so a lookup by name is unambiguous', () {
    final headers = _headers();
    expect(headers.toSet().length, headers.length);
  });

  test(
    'header count still matches the row width under each rate permission',
    () {
      for (final transporter in [true, false]) {
        for (final margin in [true, false]) {
          for (final customer in [true, false]) {
            final sheet = _sheet(
              canViewTransporterRate: transporter,
              canViewVistarMargin: margin,
              canViewCustomerRate: customer,
            );
            final headerCount = sheet.rows.first.length;
            final rowCount = sheet.rows[1].length;
            expect(
              rowCount,
              headerCount,
              reason:
                  'transporter=$transporter margin=$margin '
                  'customer=$customer left the header and data rows different '
                  'widths',
            );
          }
        }
      }
    },
  );

  test('the money headings appear only when the rate permission allows', () {
    final hidden = _headers(
      canViewTransporterRate: false,
      canViewVistarMargin: false,
      canViewCustomerRate: false,
    );
    expect(hidden, isNot(contains('Total Transport Charges')));
    expect(hidden, isNot(contains('Transport Advance Paid')));
    expect(hidden, isNot(contains('TransportBalance Payment')));
    expect(hidden, isNot(contains('Mathadi Charges')));
    expect(hidden, isNot(contains('Vistar Billing Amount')));
    expect(hidden, isNot(contains('Vistar Margin')));
    // Non-money columns are unaffected.
    expect(hidden, contains('LR No'));
    expect(hidden, contains('Origin to Destination'));
  });

  test('TransportBalance Payment is freight - advance, as misRow computes', () {
    expect(_money('TransportBalance Payment'), _kFreight - _kAdvance); // 1500
    // Regression guard: the column used to print lr.freight.balance — the
    // `balance` generated column, total - advance — which folds Vistar's margin
    // AND every ancillary head into what is owed to the transporter.
    final wrongBalance =
        _kFreight + _kAncillaries + _kVistarMargin - _kAdvance; // 7831
    expect(_money('TransportBalance Payment'), isNot(wrongBalance));
    // The shape of the original report too, margin folded in but no ancillaries.
    expect(
      _money('TransportBalance Payment'),
      isNot(_kFreight + _kVistarMargin - _kAdvance), // 4781
    );
    // The fixture must actually exercise the difference, or this test is vacuous.
    expect(_kAncillaries, greaterThan(0));
  });

  test('the transporter-side columns carry the raw freight and advance', () {
    // Pinned so a future edit cannot quietly point these at `total` either.
    expect(_money('Total Transport Charges'), _kFreight);
    expect(_money('Transport Advance Paid'), _kAdvance);
  });

  test('Vistar Billing Amount is freight + vistar margin', () {
    expect(_money('Vistar Billing Amount'), _kFreight + _kVistarMargin);
  });

  test('Vistar Billing Amount needs all three rate permissions', () {
    expect(_headers(), contains('Vistar Billing Amount'));
    for (final missing in const ['transporter', 'margin', 'customer']) {
      final headers = _headers(
        canViewTransporterRate: missing != 'transporter',
        canViewVistarMargin: missing != 'margin',
        canViewCustomerRate: missing != 'customer',
      );
      expect(
        headers,
        isNot(contains('Vistar Billing Amount')),
        reason:
            'billing amount leaked without $missing rate permission; any two '
            'of billing amount, freight and margin give the third',
      );
    }
  });
}
