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
      overrides: [tokenStorageProvider.overrideWithValue(_FakeTokenStorage())],
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

    testWidgets('new password shorter than 6 chars is rejected', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'oldpass99');
      await tester.enterText(find.byType(TextFormField).at(1), 'ab1');
      await tester.enterText(find.byType(TextFormField).at(2), 'ab1');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      expect(find.text('Min 6 characters'), findsOneWidget);
    });

    // Pins the boundary itself, not just "something short fails" — the minimum
    // has already moved once (10 → 6) and the length-only test above kept
    // passing its old assertion right up until the message text changed.
    testWidgets('6 characters clears the length rule, 5 does not', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'oldpass99');
      await tester.enterText(find.byType(TextFormField).at(1), 'abcd1');
      await tester.enterText(find.byType(TextFormField).at(2), 'abcd1');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      expect(find.text('Min 6 characters'), findsOneWidget);

      // Six characters, but no digit — so the length rule is satisfied while
      // the form stays invalid on the *next* rule. That keeps this a pure
      // validator check: a fully valid form would submit and leave the real
      // network call pending, which the test binding rejects.
      await tester.enterText(find.byType(TextFormField).at(1), 'abcdef');
      await tester.enterText(find.byType(TextFormField).at(2), 'abcdef');
      await tester.tap(find.text('Update password'));
      await tester.pump();
      expect(find.text('Min 6 characters'), findsNothing);
      expect(find.text('Must contain a number'), findsOneWidget);
    });
  });
}
