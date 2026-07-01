import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/core/utils/lr_number_format.dart';

void main() {
  group('indianFinancialYear', () {
    test('Apr 1 starts the new FY', () {
      expect(indianFinancialYear(DateTime(2027, 4, 1)), '27-28');
    });
    test('Mar 31 is still the previous FY', () {
      expect(indianFinancialYear(DateTime(2027, 3, 31)), '26-27');
    });
    test('February falls in the FY that started last April', () {
      expect(indianFinancialYear(DateTime(2027, 2, 15)), '26-27');
    });
    test('August is in the current FY', () {
      expect(indianFinancialYear(DateTime(2026, 8, 10)), '26-27');
    });
  });

  group('formatLrNumber', () {
    test('renders the per-region financial-year template', () {
      expect(
        formatLrNumber(
          '{prefix}/{REGION}/{FY}/{seq:05d}',
          prefix: 'LR',
          region: 'PUN',
          seq: 1,
          at: DateTime(2026, 8, 10),
        ),
        'LR/PUN/26-27/00001',
      );
    });

    test('tenant-wide fallback row has an empty region segment', () {
      expect(
        formatLrNumber(
          '{prefix}/{REGION}/{FY}/{seq:05d}',
          prefix: 'LR',
          region: '',
          seq: 1,
          at: DateTime(2026, 8, 10),
        ),
        'LR//26-27/00001',
      );
    });

    test('still supports the legacy monthly template', () {
      expect(
        formatLrNumber(
          '{prefix}/{YY}/{MM}/{seq:05d}',
          prefix: 'LR',
          region: 'PUN',
          seq: 9,
          at: DateTime(2026, 7, 3),
        ),
        'LR/26/07/00009',
      );
    });

    test('bare {seq} is not zero-padded', () {
      expect(
        formatLrNumber('{prefix}-{seq}',
            prefix: 'X', region: '', seq: 42, at: DateTime(2026, 8, 1)),
        'X-42',
      );
    });
  });
}
