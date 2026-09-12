import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/masters/widgets/transporter_form_dialog.dart';
import 'package:lr_management/shared/models/transporter.dart';

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage() : super(const FlutterSecureStorage());
  @override
  Future<String?> readAccess() async => null;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> write({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

Future<void> _pump(WidgetTester tester, {Transporter? existing}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tokenStorageProvider.overrideWithValue(_FakeTokenStorage())],
      child: MaterialApp(
        home: Scaffold(body: TransporterFormDialog(existing: existing)),
      ),
    ),
  );
  await tester.pump();
}

/// A transporter created before migration 127: bank details and a cheque on
/// file, but no Aadhaar number, contact number or KYC photos.
Transporter _legacy() => Transporter.fromJson({
  'id': 't1',
  'name': 'ACME ROADLINES',
  'pan': 'AAAPA1234A',
  'tds_applicable': true,
  'version': 3,
  'bank_account': {
    'bank_name': 'ICICI',
    'account_holder': 'ACME ROADLINES',
    'account_no': '123456789',
    'ifsc': 'ICIC0000001',
    'cheque_file_key': 'k/cheque.jpg',
    'cheque_file_name': 'cheque.jpg',
  },
});

void main() {
  testWidgets('empty New Transporter form flags every mandatory field', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    // 8 required text fields (Name, PAN, Aadhaar Number, Contact Number, Bank,
    // Holder, Account No, IFSC) plus 3 mandatory uploads (Cheque, PAN Card
    // Photo, Aadhaar Card Photo). The TDS attachment stays optional, and TDS
    // Applicable defaults to "Yes" so it never reports Required.
    expect(find.text('Required'), findsNWidgets(11));
  });

  testWidgets('the new KYC fields are present on a new transporter', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Aadhaar Number'), findsOneWidget);
    expect(find.text('Contact Number'), findsOneWidget);
    expect(find.text('PAN Card Photo'), findsOneWidget);
    expect(find.text('Aadhaar Card Photo'), findsOneWidget);
  });

  testWidgets('a legacy transporter shows no Required on the KYC fields', (
    tester,
  ) async {
    // The point of the nullable-column decision: someone fixing an IFSC on a
    // transporter that predates these fields must not be stopped until they can
    // find an Aadhaar card. Asserted on the rendered form rather than by
    // tapping Save, because a valid save would fire a real network call.
    await _pump(tester, existing: _legacy());

    expect(find.text('Aadhaar Number'), findsOneWidget);
    expect(find.text('PAN Card Photo'), findsOneWidget);
    expect(find.text('Required'), findsNothing);
  });

  testWidgets('a malformed Aadhaar and contact number are both rejected', (
    tester,
  ) async {
    await _pump(tester, existing: _legacy());

    // Field order: Name, PAN, Aadhaar Number, Contact Number, …
    await tester.enterText(find.byType(TextFormField).at(2), '12345');
    await tester.enterText(find.byType(TextFormField).at(3), '98765');
    await tester.tap(find.text('Save'));
    await tester.pump();

    // Validation fails, so the save never reaches the network.
    expect(find.text('Aadhaar must be 12 digits'), findsOneWidget);
    expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
  });
}
