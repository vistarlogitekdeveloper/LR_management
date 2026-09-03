// Verifies the Reports "Download Excel" date-range filter keeps both ends
// inclusive (whole days) and that a null range exports every LR.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/reports/screens/reports_screen.dart';
import 'package:lr_management/shared/models/lr_models.dart';

LorryReceipt _lr(String number, String date) => LorryReceipt.fromJson({
      'id': number,
      'number': number,
      'lr_date': date,
    });

void main() {
  final lrs = [
    _lr('A', '2026-06-30'),
    _lr('B', '2026-07-01'),
    _lr('C', '2026-07-15'),
    _lr('D', '2026-07-31'),
    _lr('E', '2026-08-01'),
  ];

  test('a null range exports every LR', () {
    expect(lrsInExportRange(lrs, null).length, lrs.length);
  });

  test('both ends of the range are inclusive', () {
    final rows = lrsInExportRange(
      lrs,
      DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      ),
    );
    expect(rows.map((l) => l.number), ['B', 'C', 'D']);
  });

  test('the end day is included whatever time the LR carries', () {
    final rows = lrsInExportRange(
      [_lr('X', '2026-07-31T23:45:00')],
      DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31, 9, 30),
      ),
    );
    expect(rows.length, 1);
  });

  test('a range with no LRs comes back empty', () {
    final rows = lrsInExportRange(
      lrs,
      DateTimeRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      ),
    );
    expect(rows, isEmpty);
  });
}
