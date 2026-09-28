import 'package:excel/excel.dart';

import 'ledger_row.dart';

/// The sheet's columns, in the agreed order. Kept in lockstep with
/// `widgets/ledger_table.dart`'s `ledgerColumns` — a column added to one must be
/// added to the other, which the workbook test asserts.
const List<String> ledgerWorkbookHeaders = [
  'Sr.no.',
  'Source',
  'Driver/Owner Name',
  'Contact Number',
  'Transporter',
  'Transporter Contact Number',
  'Route',
  'Pan Card number',
  'Adhar Card number',
  'Bank Name',
  'Branch Name',
  'Bank AC No',
  'IFSC Code',
];

/// Builds the Vehicle Bank ledger as a real .xlsx workbook.
///
/// Built CLIENT-SIDE, from the rows already on screen, and that is the point:
/// the sheet is then the screen by construction and the two cannot drift. It
/// also means the export inherits the server's PII decision for free — the rows
/// in hand are already masked (or blank) for a caller without
/// VEHICLE_BANK_PII_VIEW, so there is no second place where that gate has to be
/// remembered, and no way for the download to carry more than was displayed.
///
/// Returns null when [rows] is empty: an empty workbook is a worse answer than
/// telling the user there was nothing to export.
List<int>? buildLedgerWorkbook(List<LedgerRow> rows) {
  if (rows.isEmpty) return null;

  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

  sheet.appendRow(
    ledgerWorkbookHeaders.map<CellValue>(TextCellValue.new).toList(),
  );

  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    sheet.appendRow(<CellValue>[
      // Sr. no. is the row's POSITION in the current ordering, not an id — the
      // same number the screen shows, because the screen and this sheet are
      // given the same list in the same order.
      IntCellValue(i + 1),
      TextCellValue(r.sourceCity),
      TextCellValue(r.personName),
      // Every identifier goes out as TEXT, never a number. A mobile number,
      // account number or Aadhaar written as a numeric cell loses its leading
      // zeros and, past fifteen digits, its low-order digits to floating point —
      // Excel would silently turn a 16-digit account number into a wrong one.
      TextCellValue(r.personMobile),
      TextCellValue(r.transporterName),
      TextCellValue(r.transporterMobile),
      TextCellValue(r.routeLabel),
      TextCellValue(r.personPan),
      TextCellValue(r.personAadhaar),
      TextCellValue(r.bankName),
      TextCellValue(r.bankBranch),
      TextCellValue(r.bankAccountNo),
      TextCellValue(r.bankIfsc),
    ]);
  }

  return excel.encode();
}
