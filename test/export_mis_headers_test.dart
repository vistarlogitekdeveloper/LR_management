// The Reports "Download Excel" sheet must carry the same column headings as the
// MIS workbook, so the two can be read, compared and pasted side by side.
//
// The MIS names live server-side in
// lr-management/services/misWorkbook.service.js (MIS_COLUMNS). They include
// spellings that look like typos — "Transportor name", "TransportBalance
// Payment" — which are copied verbatim on purpose. These tests pin them so a
// well-meaning cleanup on this side cannot silently break the match; if a
// heading really should change, change MIS first and then this test.
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/reports/services/export_service.dart';
import 'package:lr_management/shared/models/lr_models.dart';

LorryReceipt _lr() => LorryReceipt.fromJson({
  'id': 'lr1',
  'number': 'LR/PUN/26-27/00001',
  'lr_date': '2026-07-01',
});

List<String> _headers({
  bool canViewTransporterRate = true,
  bool canViewVistarMargin = true,
}) {
  final bytes = ExportService.buildLrsWorkbook(
    [_lr()],
    canViewTransporterRate: canViewTransporterRate,
    canViewVistarMargin: canViewVistarMargin,
  );
  expect(bytes, isNotNull);
  final excel = Excel.decodeBytes(bytes!);
  final sheet = excel.tables[excel.tables.keys.first]!;
  return sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
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
      // MIS "Total Transport Charges" is the base freight, so the grand total
      // keeps a distinct name rather than colliding with it.
      'Total',
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
          final bytes = ExportService.buildLrsWorkbook(
            [_lr()],
            canViewTransporterRate: transporter,
            canViewVistarMargin: margin,
          );
          final excel = Excel.decodeBytes(bytes!);
          final sheet = excel.tables[excel.tables.keys.first]!;
          final headerCount = sheet.rows.first.length;
          final rowCount = sheet.rows[1].length;
          expect(
            rowCount,
            headerCount,
            reason:
                'transporter=$transporter margin=$margin left the header and '
                'data rows different widths',
          );
        }
      }
    },
  );

  test('the money headings appear only when the rate permission allows', () {
    final hidden = _headers(
      canViewTransporterRate: false,
      canViewVistarMargin: false,
    );
    expect(hidden, isNot(contains('Total Transport Charges')));
    expect(hidden, isNot(contains('Transport Advance Paid')));
    expect(hidden, isNot(contains('TransportBalance Payment')));
    expect(hidden, isNot(contains('Mathadi Charges')));
    expect(hidden, isNot(contains('Vistar Margin')));
    // Non-money columns are unaffected.
    expect(hidden, contains('LR No'));
    expect(hidden, contains('Origin to Destination'));
  });
}
