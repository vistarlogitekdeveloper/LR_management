import 'package:excel/excel.dart';

import 'ledger_row.dart';

/// The office's "Vehicle Directory" sheet header, as two rows: the groups
/// (Route, KYC Documents, Bank Details) merged across their columns in row 1
/// with the column names in row 2, and every ungrouped header merged down both
/// rows. Each entry is (row-1 title, row-2 leaves); no leaves = one cell tall.
const List<(String, List<String>)> ledgerWorkbookHeaderGroups = [
  ('Sr.no.', []),
  ('Driver/Owner Name', []),
  ('Contact Number', []),
  ('Mail Id', []),
  ('Vehicle Type', []),
  ('Route', ['From', 'To']),
  ('KYC Documents', ['Pan Card', 'Adhar Card']),
  ('Bank Details', ['Bank Name', 'Branch Name', 'Bank AC No', 'IFSC Code']),
  ('Upload Document', []),
];

/// The sheet's fourteen columns, by their lowest header cell — the same labels,
/// in the same order, as `widgets/ledger_table.dart`'s `ledgerColumns`, which
/// the workbook test asserts.
final List<String> ledgerWorkbookHeaders = [
  for (final (title, leaves) in ledgerWorkbookHeaderGroups)
    if (leaves.isEmpty) title else ...leaves,
];

// Column widths, in characters, tuned to the longest realistic value.
const List<double> _widths = [
  7,
  26,
  15,
  26,
  18,
  16,
  16,
  13,
  16,
  20,
  18,
  20,
  13,
  22,
];

const _headerRows = 2;

Border _thin() => Border(borderStyle: BorderStyle.Thin);

final _headerStyle = CellStyle(
  bold: true,
  fontSize: 10,
  backgroundColorHex: ExcelColor.fromHexString('#BDD7EE'),
  horizontalAlign: HorizontalAlign.Center,
  verticalAlign: VerticalAlign.Center,
  textWrapping: TextWrapping.WrapText,
  leftBorder: _thin(),
  rightBorder: _thin(),
  topBorder: _thin(),
  bottomBorder: _thin(),
);

final _bodyStyle = CellStyle(
  verticalAlign: VerticalAlign.Center,
  textWrapping: TextWrapping.WrapText,
  leftBorder: _thin(),
  rightBorder: _thin(),
  topBorder: _thin(),
  bottomBorder: _thin(),
);

final _serialStyle = _bodyStyle.copyWith(
  horizontalAlignVal: HorizontalAlign.Center,
);

CellIndex _at(int col, int row) =>
    CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

/// The values of one sheet row, in column order. Exposed so the test can check
/// a row without decoding a workbook.
List<CellValue> ledgerWorkbookRow(LedgerRow r, int serial) => <CellValue>[
  // Sr.no. is the row's POSITION in the current ordering, not an id — the same
  // number the screen shows, because both are given the same list in order.
  IntCellValue(serial),
  TextCellValue(r.personName),
  // Every identifier goes out as TEXT, never a number. A mobile number, account
  // number or Aadhaar written as a numeric cell loses its leading zeros and,
  // past fifteen digits, its low-order digits to floating point — Excel would
  // silently turn a 16-digit account number into a wrong one.
  TextCellValue(r.personMobile),
  TextCellValue(r.personEmail),
  TextCellValue(r.vehicleType),
  TextCellValue(r.fromCity),
  TextCellValue(r.toCity),
  TextCellValue(r.personPan),
  TextCellValue(r.personAadhaar),
  TextCellValue(r.bankName),
  TextCellValue(r.bankBranch),
  TextCellValue(r.bankAccountNo),
  TextCellValue(r.bankIfsc),
  // A sheet cannot open a file, so it names the documents on file.
  TextCellValue(r.documents.map((d) => d.label).join(', ')),
];

/// Builds the Vehicle Bank as a real .xlsx in the Vehicle Directory sheet's
/// layout.
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
  final defaultName = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultName, 'Vehicle Directory');
  final sheet = excel['Vehicle Directory'];

  // Header: groups across, ungrouped columns down both rows.
  var col = 0;
  for (final (title, leaves) in ledgerWorkbookHeaderGroups) {
    if (leaves.isEmpty) {
      sheet.merge(_at(col, 0), _at(col, 1), customValue: TextCellValue(title));
      col += 1;
    } else {
      sheet.merge(
        _at(col, 0),
        _at(col + leaves.length - 1, 0),
        customValue: TextCellValue(title),
      );
      for (var i = 0; i < leaves.length; i++) {
        sheet.updateCell(_at(col + i, 1), TextCellValue(leaves[i]));
      }
      col += leaves.length;
    }
  }
  // Style every header cell, merged or not, so the band prints without gaps.
  for (var r = 0; r < _headerRows; r++) {
    for (var c = 0; c < ledgerWorkbookHeaders.length; c++) {
      sheet.cell(_at(c, r)).cellStyle = _headerStyle;
    }
  }

  for (var i = 0; i < rows.length; i++) {
    final values = ledgerWorkbookRow(rows[i], i + 1);
    for (var c = 0; c < values.length; c++) {
      sheet.updateCell(
        _at(c, _headerRows + i),
        values[c],
        cellStyle: c == 0 ? _serialStyle : _bodyStyle,
      );
    }
  }

  for (var c = 0; c < _widths.length; c++) {
    sheet.setColumnWidth(c, _widths[c]);
  }

  return excel.encode();
}
