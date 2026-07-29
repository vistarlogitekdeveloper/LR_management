// Verifies the Reports "Download Excel" splits In/Out into separate Date and
// 24-hour Time columns (previously one combined 12-hour "01 Jul 2026, 03:15 PM"
// cell).
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/utils/formatters.dart';
import 'package:lr_management/features/reports/services/export_service.dart';
import 'package:lr_management/shared/models/lr_models.dart';

LorryReceipt _lr({String? inDt, String? outDt}) => LorryReceipt.fromJson({
      'id': 'lr1',
      'number': 'LR/PUN/26-27/00001',
      'lr_date': '2026-07-01',
      'in_datetime': ?inDt,
      'out_datetime': ?outDt,
    });

/// Row-major cell text from the first sheet.
List<List<String>> _grid(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables[excel.tables.keys.first]!;
  return sheet.rows
      .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
      .toList();
}

void main() {
  test('formatTime24 renders a 24-hour clock', () {
    expect(formatTime24(DateTime(2026, 7, 1, 15, 15)), '15:15');
    expect(formatTime24(DateTime(2026, 7, 1, 0, 5)), '00:05');
    expect(formatTime24(DateTime(2026, 7, 1, 12, 0)), '12:00');
    expect(formatTime24(DateTime(2026, 7, 1, 9, 7)), '09:07');
  });

  test('workbook has separate In/Out Date and Time (24h) columns', () {
    final bytes = ExportService.buildLrsWorkbook([
      // 15:15 local == 3:15 PM; the old export wrote "01 Jul 2026, 03:15 PM".
      _lr(inDt: '2026-07-01T15:15:00', outDt: '2026-07-01T18:30:00'),
    ]);
    expect(bytes, isNotNull);
    final grid = _grid(bytes!);
    final headers = grid.first;

    // The four split headers exist, contiguous and in order.
    final inDate = headers.indexOf('In Date');
    expect(inDate, greaterThanOrEqualTo(0));
    expect(headers[inDate + 1], 'In Time');
    expect(headers[inDate + 2], 'Out Date');
    expect(headers[inDate + 3], 'Out Time');
    // The old combined format must be gone.
    expect(headers.where((h) => h == 'In Date').length, 1);

    final row = grid[1]; // single data row
    expect(row[inDate], '01 Jul 2026');
    expect(row[inDate + 1], '15:15'); // 24-hour, no AM/PM
    expect(row[inDate + 2], '01 Jul 2026');
    expect(row[inDate + 3], '18:30');
    // No cell still carries the old combined 12-hour string.
    expect(row.any((c) => c.contains('PM') || c.contains('AM')), isFalse);
  });

  test('blank In/Out datetimes leave all four columns empty', () {
    final bytes = ExportService.buildLrsWorkbook([_lr()]);
    final grid = _grid(bytes!);
    final headers = grid.first;
    final inDate = headers.indexOf('In Date');
    final row = grid[1];
    expect(row[inDate], '');
    expect(row[inDate + 1], '');
    expect(row[inDate + 2], '');
    expect(row[inDate + 3], '');
  });

  test('header and data-row cell counts stay aligned after the split', () {
    final bytes = ExportService.buildLrsWorkbook([_lr(inDt: '2026-07-01T08:00:00')]);
    final grid = _grid(bytes!);
    expect(grid[1].length, grid.first.length);
  });
}
