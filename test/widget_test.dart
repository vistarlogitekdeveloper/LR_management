import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/main.dart';

/// In-memory token storage so the smoke test never touches platform channels
/// (flutter_secure_storage / shared_preferences) or the network. With no stored
/// token the auth bootstrap resolves immediately to "signed out", so the router
/// settles on the login screen.
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

void main() {
  testWidgets('App boots into login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        ],
        child: const VistarApp(),
      ),
    );

    // The app shows a splash with an indeterminate CircularProgressIndicator
    // while auth initializes, so pumpAndSettle() would spin forever. Pump a
    // bounded number of frames until the router redirects to the login screen.
    for (var i = 0;
        i < 20 && find.text('Welcome back').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Welcome back'), findsOneWidget);
  });
}
