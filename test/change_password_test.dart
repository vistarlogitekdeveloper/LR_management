import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/auth/screens/change_password_screen.dart';

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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
      ],
      child: const MaterialApp(home: ChangePasswordScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  group('ChangePasswordScreen', () {
    testWidgets('each password field has a show/hide toggle', (tester) async {
      await _pump(tester);
      // Three fields, each obscured with a "show password" eye icon.
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(3));
    });

    testWidgets('tapping an eye toggle reveals that field', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.visibility_outlined).first);
      await tester.pump();
      // One field is now revealed → its icon flips to "hide".
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    });

    testWidgets('mismatched confirmation blocks submit', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'oldpass99');
      await tester.enterText(find.byType(TextFormField).at(1), 'newpassw12');
      await tester.enterText(find.byType(TextFormField).at(2), 'different12');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('new password shorter than 10 chars is rejected',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'oldpass99');
      await tester.enterText(find.byType(TextFormField).at(1), 'ab1');
      await tester.enterText(find.byType(TextFormField).at(2), 'ab1');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      expect(find.text('Min 10 characters'), findsOneWidget);
    });
  });
}
