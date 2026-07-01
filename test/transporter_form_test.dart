import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/masters/widgets/transporter_form_dialog.dart';

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

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: TransporterFormDialog()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('empty New Transporter form flags every field on Save',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    // 6 required text fields (Name, PAN, Bank, Holder, Account No, IFSC) plus
    // the two required uploads (Cheque, TDS) each show a "Required" message.
    expect(find.text('Required'), findsNWidgets(8));
  });
}
