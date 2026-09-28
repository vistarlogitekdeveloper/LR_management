// The Vehicle Bank ledger's column set IS the spec, so it is pinned here: the
// order, the parity between the on-screen table and the workbook, and the two
// rules that decide what a cell may contain (no cross-party KYC fallback, and
// no bank block without the permission).
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/vehicle_bank/data/ledger_row.dart';
import 'package:lr_management/features/vehicle_bank/data/ledger_workbook.dart';
import 'package:lr_management/features/vehicle_bank/data/vehicle_bank_models.dart';
import 'package:lr_management/features/vehicle_bank/widgets/ledger_table.dart';

/// A row exactly as the API sends it, so the parsing rules are exercised rather
/// than bypassed by constructing the Dart object directly.
Map<String, dynamic> _json({
  bool piiVisible = true,
  bool personIsDriver = true,
  String aadhaar = '123456789012',
  Map<String, dynamic> bank = const {
    'bank_name': 'HDFC',
    'bank_branch': '',
    'bank_account_no': '50100288210',
    'bank_ifsc': 'HDFC0001234',
  },
}) => {
  'key': 'd1|t1|CHAKAN|DEWAS',
  'source_city': 'CHAKAN',
  'person_name': personIsDriver ? 'SALMAN' : 'ONKAR SATISH SONAR',
  'person_is_driver': personIsDriver,
  'person_mobile': '9039992453',
  'transporter_id': 't1',
  'transporter_name': 'ONKAR SATISH SONAR',
  'transporter_mobile': '9812345670',
  'from_city': 'CHAKAN',
  'to_city': 'DEWAS',
  // Postgres NUMERIC arrives as a STRING — a plain cast would throw.
  'route_distance_km': '620.50',
  'person_pan': 'ABCDE1234F',
  'person_aadhaar': aadhaar,
  ...bank,
  'region_id': 'g1',
  'region_name': 'Pune',
  'pii_visible': piiVisible,
  'lr_count': '7',
  'last_lr_date': '2026-09-10',
};

void main() {
  group('column spec', () {
    test('the table shows the 13 agreed columns in the agreed order', () {
      expect(ledgerColumns.map((c) => c.$1).toList(), [
        'Sr.',
        'Source',
        'Driver / Owner',
        'Contact',
        'Transporter',
        'Transporter Contact',
        'Route',
        'PAN',
        'Aadhaar',
        'Bank Name',
        'Branch',
        'Bank A/C No',
        'IFSC',
      ]);
    });

    test('the workbook has one header per table column, in the same order', () {
      // The two lists are maintained separately — this is what stops a column
      // added to the screen from quietly missing from the download.
      expect(ledgerWorkbookHeaders.length, ledgerColumns.length);
      expect(ledgerWorkbookHeaders.first, 'Sr.no.');
      expect(ledgerWorkbookHeaders[1], 'Source');
      expect(ledgerWorkbookHeaders[6], 'Route');
      expect(ledgerWorkbookHeaders.last, 'IFSC Code');
    });
  });

  group('LedgerRow.fromJson', () {
    test('parses a full row, including NUMERIC-as-string distance', () {
      final row = LedgerRow.fromJson(_json());

      expect(row.key, 'd1|t1|CHAKAN|DEWAS');
      expect(row.sourceCity, 'CHAKAN');
      expect(row.personName, 'SALMAN');
      expect(row.personIsDriver, isTrue);
      expect(row.personMobile, '9039992453');
      expect(row.transporterName, 'ONKAR SATISH SONAR');
      expect(row.transporterMobile, '9812345670');
      expect(row.routeLabel, 'CHAKAN → DEWAS');
      expect(row.routeDistanceKm, 620.5);
      expect(row.personPan, 'ABCDE1234F');
      expect(row.lrCount, 7);
      expect(row.lastLrDate, DateTime(2026, 9, 10));
      expect(row.regionName, 'Pune');
    });

    test('an owner row is flagged, so the name is not read as a driver', () {
      final row = LedgerRow.fromJson(_json(personIsDriver: false));
      expect(row.personIsDriver, isFalse);
      expect(row.personName, 'ONKAR SATISH SONAR');
    });

    test('a masked caller gets the masked Aadhaar and no bank block', () {
      final row = LedgerRow.fromJson(
        _json(
          piiVisible: false,
          aadhaar: 'XXXX XXXX 9012',
          bank: const {
            'bank_name': '',
            'bank_branch': '',
            'bank_account_no': '',
            'bank_ifsc': '',
          },
        ),
      );

      expect(row.piiVisible, isFalse);
      expect(row.personAadhaar, 'XXXX XXXX 9012');
      expect(row.hasBankDetails, isFalse);
      // The client never reassembles a masked value into a real one.
      expect(row.personAadhaar, isNot(contains('5678')));
    });

    test('a missing route leaves the label empty rather than "? → ?"', () {
      final row = LedgerRow.fromJson({
        ...(_json()),
        'from_city': '',
        'to_city': '',
      });
      expect(row.routeLabel, isEmpty);
    });
  });

  group('buildLedgerWorkbook', () {
    test(
      'returns null for an empty ledger rather than a headers-only file',
      () {
        expect(buildLedgerWorkbook(const []), isNull);
      },
    );

    test('encodes a workbook for a non-empty ledger', () {
      final bytes = buildLedgerWorkbook([LedgerRow.fromJson(_json())]);
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(0));
      // .xlsx is a zip; "PK" is its magic number. Cheap proof we produced a real
      // workbook rather than an empty buffer.
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });
  });

  group('VehicleBankFilter.toLedgerQueryParameters', () {
    test('drops the two truck-only filters and keeps the rest', () {
      const filter = VehicleBankFilter(
        q: 'salman',
        regionId: 'g1',
        fromCity: 'chakan',
        toCity: 'dewas',
        transporterId: 't1',
        driverId: 'd1',
        active: false,
        expiringWithinDays: 30,
      );

      final params = filter.toLedgerQueryParameters();

      // A vendor row has no fitness certificate, so offering these would be a
      // filter that silently does nothing — the server strips them too.
      expect(params.containsKey('active'), isFalse);
      expect(params.containsKey('expiring_within_days'), isFalse);

      expect(params['q'], 'salman');
      expect(params['region_id'], 'g1');
      expect(params['from_city'], 'chakan');
      expect(params['to_city'], 'dewas');
      expect(params['transporter_id'], 't1');
      expect(params['driver_id'], 'd1');
    });

    test('an empty filter sends nothing at all', () {
      expect(VehicleBankFilter.empty.toLedgerQueryParameters(), isEmpty);
    });
  });
}
