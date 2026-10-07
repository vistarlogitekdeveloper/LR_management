// The Vehicle Bank screen lays out the Vehicle Directory sheet's 14 columns
// without overflow, at a desktop width (the table, with its two-row grouped
// header) and a phone width (stacked cards), and the Upload Document chips say
// which files are on file.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/vehicle_bank/data/ledger_row.dart';
import 'package:lr_management/features/vehicle_bank/widgets/ledger_directory.dart';

final _rows = [
  LedgerRow.fromJson({
    'key': 'a',
    'person_name': 'SALMAN KHAN',
    'person_is_driver': true,
    'person_mobile': '9039992453',
    'person_email': 'salman.khan.transport@example.com',
    'vehicle_type': '20 FT SXL, 32 FT MXL',
    'transporter_name': 'ONKAR SATISH SONAR',
    'from_city': 'CHAKAN',
    'to_city': 'DEWAS',
    'person_pan': 'ABCDE1234F',
    'person_aadhaar': '123456789012',
    'bank_name': 'HDFC BANK',
    'bank_branch': 'CHAKAN MIDC',
    'bank_account_no': '50100288210123',
    'bank_ifsc': 'HDFC0001234',
    'pii_visible': true,
    'documents': [
      {
        'owner': 'driver',
        'owner_id': 'd1',
        'type': 'pan',
        'label': 'PAN',
        'viewable': true,
      },
      {
        'owner': 'transporter',
        'owner_id': 't1',
        'type': 'cheque',
        'label': 'Cheque',
        'viewable': true,
      },
      {
        'owner': 'transporter',
        'owner_id': 't1',
        'type': 'tds',
        'label': 'TDS',
        'viewable': false,
      },
    ],
  }),
  LedgerRow.fromJson({
    'key': 'b',
    'person_name': 'SHREE GANESH ROADLINES',
    'person_is_driver': false,
    'from_city': 'PUNE',
    'to_city': 'CHENNAI',
    'pii_visible': true,
  }),
];

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: LedgerDirectory(rows: _rows, padding: 16)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop: the table shows the sheet header and every column', (
    tester,
  ) async {
    await _pump(tester, const Size(1900, 900));
    expect(tester.takeException(), isNull);

    for (final label in [
      'Sr.no.',
      'Driver/Owner Name',
      'Contact Number',
      'Mail Id',
      'Vehicle Type',
      'Route',
      'From',
      'To',
      'KYC Documents',
      'Pan Card',
      'Adhar Card',
      'Bank Details',
      'Bank Name',
      'Branch Name',
      'Bank AC No',
      'IFSC Code',
      'Upload Document',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('salman.khan.transport@example.com'), findsOneWidget);
    expect(find.text('20 FT SXL, 32 FT MXL'), findsOneWidget);
    expect(find.text('CHAKAN MIDC'), findsOneWidget);
    expect(find.text('driver · ONKAR SATISH SONAR'), findsOneWidget);
    expect(find.text('owner'), findsOneWidget);
    for (final doc in ['PAN', 'Cheque', 'TDS']) {
      expect(find.text(doc), findsOneWidget, reason: doc);
    }
  });

  testWidgets(
    'a narrower window scrolls the table sideways, without overflow',
    (tester) async {
      await _pump(tester, const Size(1100, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('Upload Document'), findsOneWidget);
    },
  );

  testWidgets('phone: each row is a card with the sheet\'s groups', (
    tester,
  ) async {
    await _pump(tester, const Size(400, 1600));
    expect(tester.takeException(), isNull);
    expect(find.text('Mail Id'), findsNWidgets(2));
    expect(find.text('ROUTE'), findsNWidgets(2));
    expect(find.text('KYC DOCUMENTS'), findsNWidgets(2));
    expect(find.text('BANK DETAILS'), findsNWidgets(2));
    expect(find.text('UPLOAD DOCUMENT'), findsNWidgets(2));
    expect(find.text('Cheque'), findsOneWidget);
  });
}
