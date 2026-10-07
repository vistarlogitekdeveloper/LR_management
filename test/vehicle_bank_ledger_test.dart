// The Vehicle Bank ledger's column set IS the spec — the office's "Vehicle
// Directory" sheet — so it is pinned here: the order and grouping, the parity
// between the on-screen table and the workbook, and the two rules that decide
// what a cell may contain (no cross-party KYC fallback, and no bank block
// without the permission).
import 'package:excel/excel.dart';
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
  'person_email': 'salman@example.com',
  'driver_id': personIsDriver ? 'd1' : null,
  'vehicle_type': '20 FT SXL, 32 FT MXL',
  'documents': [
    {
      'owner': 'driver',
      'owner_id': 'd1',
      'type': 'pan',
      'label': 'PAN',
      'file_name': 'salman-pan.jpg',
      'viewable': true,
    },
    {
      'owner': 'transporter',
      'owner_id': 't1',
      'type': 'cheque',
      'label': 'Cheque',
      'file_name': '',
      'viewable': false,
    },
  ],
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
    // The office's "Vehicle Directory" sheet, column for column.
    const sheet = [
      'Sr.no.',
      'Driver/Owner Name',
      'Contact Number',
      'Mail Id',
      'Vehicle Type',
      'From',
      'To',
      'Pan Card',
      'Adhar Card',
      'Bank Name',
      'Branch Name',
      'Bank AC No',
      'IFSC Code',
      'Upload Document',
    ];

    test(
      'the table shows the Vehicle Directory sheet\'s 14 columns, in order',
      () {
        expect(ledgerColumns.map((c) => c.$1).toList(), sheet);
      },
    );

    test(
      'the table groups Route, KYC Documents and Bank Details as the sheet does',
      () {
        String? groupOf(String label) =>
            ledgerColumns.firstWhere((c) => c.$1 == label).$3;
        expect(groupOf('From'), 'Route');
        expect(groupOf('To'), 'Route');
        expect(groupOf('Pan Card'), 'KYC Documents');
        expect(groupOf('Adhar Card'), 'KYC Documents');
        for (final c in [
          'Bank Name',
          'Branch Name',
          'Bank AC No',
          'IFSC Code',
        ]) {
          expect(groupOf(c), 'Bank Details', reason: c);
        }
        expect(groupOf('Mail Id'), isNull);
      },
    );

    test(
      'the workbook has the same columns as the table, in the same order',
      () {
        // The two lists are maintained separately — this is what stops a column
        // added to the screen from quietly missing from the download.
        expect(ledgerWorkbookHeaders, sheet);
        expect(ledgerWorkbookHeaderGroups.map((g) => g.$1).toList(), [
          'Sr.no.',
          'Driver/Owner Name',
          'Contact Number',
          'Mail Id',
          'Vehicle Type',
          'Route',
          'KYC Documents',
          'Bank Details',
          'Upload Document',
        ]);
      },
    );

    test('a sheet row has one value per column, identifiers as text', () {
      final values = ledgerWorkbookRow(LedgerRow.fromJson(_json()), 3);
      expect(values.length, sheet.length);
      expect(values[0], isA<IntCellValue>());
      expect(values.skip(1).every((v) => v is TextCellValue), isTrue);
      String text(int i) => (values[i] as TextCellValue).value.toString();
      expect(text(1), 'SALMAN');
      expect(text(3), 'salman@example.com');
      expect(text(4), '20 FT SXL, 32 FT MXL');
      expect(text(5), 'CHAKAN');
      expect(text(6), 'DEWAS');
      expect(text(11), '50100288210');
      expect(text(13), 'PAN, Cheque');
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
      expect(row.personEmail, 'salman@example.com');
      expect(row.driverId, 'd1');
      expect(row.vehicleType, '20 FT SXL, 32 FT MXL');
      expect(row.personPan, 'ABCDE1234F');
      expect(row.lrCount, 7);
      expect(row.lastLrDate, DateTime(2026, 9, 10));
      expect(row.regionName, 'Pune');
    });

    test('documents parse with owner, type and whether they may be opened', () {
      final docs = LedgerRow.fromJson(_json()).documents;
      expect(docs.map((d) => '${d.ownerType}:${d.type}'), [
        'driver:pan',
        'transporter:cheque',
      ]);
      expect(docs.first.viewable, isTrue);
      expect(docs.first.fileName, 'salman-pan.jpg');
      expect(docs.last.viewable, isFalse);
      expect(docs.last.label, 'Cheque');
    });

    test('a row from an older server (no new fields) still parses', () {
      final old = Map<String, dynamic>.from(_json())
        ..remove('person_email')
        ..remove('vehicle_type')
        ..remove('documents')
        ..remove('driver_id');
      final row = LedgerRow.fromJson(old);
      expect(row.personEmail, isEmpty);
      expect(row.vehicleType, isEmpty);
      expect(row.documents, isEmpty);
      expect(row.driverId, isNull);
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
