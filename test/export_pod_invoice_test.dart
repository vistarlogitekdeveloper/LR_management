// Reports "Download Excel" built in the app (users without the MIS download):
// POD Upload, POD Upload Date, POD Payment Status, Invoice Status and Invoice
// No, with the MIS sheet's headings (2026-11-02, asked by Pune transport).
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/reports/services/export_service.dart';
import 'package:lr_management/shared/models/lr_models.dart';

LorryReceipt _lr(Map<String, dynamic> extra) => LorryReceipt.fromJson({
  'id': 'lr1',
  'number': 'LR/PUN/26-27/00042',
  'lr_date': '2026-11-01',
  'freight': 20000,
  'advance': 18000,
  ...extra,
});

Map<String, String> _row(LorryReceipt lr, {bool canCust = true}) {
  final bytes = ExportService.buildLrsWorkbook([
    lr,
  ], canViewCustomerRate: canCust)!;
  final sheet = Excel.decodeBytes(bytes).tables.values.first;
  final head = sheet.rows.first.map((c) => c?.value.toString() ?? '').toList();
  final vals = sheet.rows[1].map((c) => c?.value.toString() ?? '').toList();
  return {for (var i = 0; i < head.length; i++) head[i]: vals[i]};
}

void main() {
  test('done: POD uploaded, balance paid, invoice raised', () {
    final r = _row(
      _lr({
        'pod_uploaded_at': '2026-11-02T05:00:00Z',
        'balance_paid_at': '2026-11-02',
        'invoice_raised': true,
        'invoice_no': 'VLL/PUN/26-27/0042',
      }),
    );
    expect(r['POD Upload'], 'Done');
    expect(r['POD Upload Date'], isNotEmpty);
    expect(r['POD Payment Status'], 'Done');
    expect(r['Invoice Status'], 'Raised');
    expect(r['Invoice No'], 'VLL/PUN/26-27/0042');
  });

  test('pending, and the invoice number only for customer-rate viewers', () {
    final r = _row(
      _lr({
        'pod_uploaded_at': null,
        'invoice_raised': false,
        'invoice_no': null,
      }),
      canCust: false,
    );
    expect(r['POD Upload'], 'Pending');
    expect(r['POD Upload Date'], '');
    expect(r['POD Payment Status'], 'Pending');
    expect(r['Invoice Status'], 'Pending');
    expect(r.containsKey('Invoice No'), isFalse);
  });

  test('an older server: blank, never a false "Pending"', () {
    final r = _row(_lr({}));
    expect(r['POD Upload'], '');
    expect(r['Invoice Status'], '');
  });
}
