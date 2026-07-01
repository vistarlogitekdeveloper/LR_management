import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/auth/data/login_prefs.dart';
import 'package:lr_management/features/auth/screens/login_screen.dart';

/// In-memory token storage so tests never touch platform channels or network.
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

Future<void> _pumpLogin(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  // Let initState's async prefs load resolve and the first frames settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders the sign-in form without any demo credentials',
        (tester) async {
      await _pumpLogin(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);

      // The dev-only affordances must be gone before this ships to a client.
      expect(find.text('Demo logins'), findsNothing);
      expect(find.text('or sign in as'), findsNothing);
      expect(find.textContaining('123456'), findsNothing);
      // Username field must start empty (no pre-filled 'admin').
      expect(find.text('admin'), findsNothing);
    });

    testWidgets('blocks submit and shows errors when fields are empty',
        (tester) async {
      await _pumpLogin(tester);

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Username is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      // Still on the login screen (no navigation happened).
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('validation clears once valid input is entered',
        (tester) async {
      await _pumpLogin(tester);

      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Username is required'), findsOneWidget);

      await tester.enterText(
          find.byType(TextFormField).first, 'operator');
      await tester.pump();
      expect(find.text('Username is required'), findsNothing);
    });

    testWidgets('remember-me checkbox toggles', (tester) async {
      await _pumpLogin(tester);

      Checkbox box() => tester.widget<Checkbox>(find.byType(Checkbox));
      expect(box().value, isFalse);

      await tester.tap(find.text('Remember me'));
      await tester.pump();
      expect(box().value, isTrue);
    });
  });

  group('LoginPrefs', () {
    test('remembers the username only while the box is ticked', () async {
      SharedPreferences.setMockInitialValues({});

      await LoginPrefs.save(remember: true, username: 'operator');
      final remembered = await LoginPrefs.load();
      expect(remembered.remember, isTrue);
      expect(remembered.username, 'operator');

      // Unchecking must clear the stored username.
      await LoginPrefs.save(remember: false, username: 'operator');
      final cleared = await LoginPrefs.load();
      expect(cleared.remember, isFalse);
      expect(cleared.username, '');
    });

    test('never returns a username when nothing was saved', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await LoginPrefs.load();
      expect(result.remember, isFalse);
      expect(result.username, '');
    });
  });
}
