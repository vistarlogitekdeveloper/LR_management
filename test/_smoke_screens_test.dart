// TEMPORARY diagnostic harness (not part of the suite — delete after the bug hunt).
//
// Mounts each real screen behind a Dio mock adapter that replays REAL payloads
// recorded from the live backend (test/_fixtures.json), and reports any
// exception thrown during build/settle. This exercises the true widget tree
// against true API response shapes.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_client.dart';
import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/core/theme/app_theme.dart';

import 'package:lr_management/features/lr/screens/lr_list_screen.dart';
import 'package:lr_management/features/lr/screens/create_lr_screen.dart';
import 'package:lr_management/features/lr/screens/lr_detail_screen.dart';
import 'package:lr_management/features/masters/screens/parties_screen.dart';
import 'package:lr_management/features/masters/screens/routes_screen.dart';
import 'package:lr_management/features/masters/screens/vehicles_screen.dart';
import 'package:lr_management/features/masters/screens/transporters_screen.dart';
import 'package:lr_management/features/masters/screens/drivers_screen.dart';
import 'package:lr_management/features/masters/screens/consignors_screen.dart';
import 'package:lr_management/features/masters/screens/consignees_screen.dart';
import 'package:lr_management/features/masters/screens/part_descriptions_screen.dart';
import 'package:lr_management/features/admin/screens/users_screen.dart';
import 'package:lr_management/features/admin/screens/admin_screen.dart';
import 'package:lr_management/features/admin/screens/settings_screen.dart';
import 'package:lr_management/features/lr/screens/print_lr_screen.dart';
import 'package:lr_management/features/admin/screens/regions_screen.dart';
import 'package:lr_management/features/admin/screens/numbering_screen.dart';
import 'package:lr_management/features/admin/screens/lr_format_screen.dart';
import 'package:lr_management/features/admin/screens/capacity_options_screen.dart';
import 'package:lr_management/features/admin/screens/audit_screen.dart';
import 'package:lr_management/features/reports/screens/reports_screen.dart';
import 'package:lr_management/features/dashboard/screens/dashboard_screen.dart';
import 'package:lr_management/features/accounts/screens/accounts_screen.dart';
import 'package:lr_management/features/warehouse/screens/warehouse_screen.dart';
import 'package:lr_management/features/ewb/screens/ewb_screen.dart';
import 'package:lr_management/features/auth/screens/profile_screen.dart';

late Map<String, dynamic> fx;
String lrId = '';

/// Serves recorded payloads for any request path, ignoring the `_ts`
/// cache-buster and query params the client appends.
class _FixtureAdapter implements HttpClientAdapter {
  final List<String> unmatched = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8ListStub>? _,
      Future<void>? _) async {
    final path = options.path.split('?').first;
    dynamic body = fx[path];
    if (body == null && RegExp(r'^/lrs/[0-9a-f-]{36}$').hasMatch(path)) {
      body = fx['/lrs/:id'];
    }
    if (body == null) {
      // Unknown endpoint -> empty envelope (mirrors an empty list from the API)
      unmatched.add('${options.method} $path');
      body = {'success': true, 'data': [], 'meta': {'next_cursor': null}};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

typedef Uint8ListStub = List<int>;

class _MemTokens implements TokenStorage {
  String? a = 'test-access';
  String? r = 'test-refresh';
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccess() async => a;
  @override
  Future<String?> readRefresh() async => r;
  @override
  Future<void> write({required String access, required String refresh}) async {}
}

Future<List<String>> mountAndCollect(
  WidgetTester tester,
  String name,
  Widget screen,
) async {
  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString());

  final adapter = _FixtureAdapter();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_MemTokens()),
        apiClientProvider.overrideWith((ref) {
          final c = ApiClient(_MemTokens());
          c.dio.httpClientAdapter = adapter;
          return c;
        }),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );

  for (var i = 0; i < 12; i++) {
    try {
      await tester.pump(const Duration(milliseconds: 300));
    } catch (e) {
      errors.add('pump: $e');
    }
  }
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  } catch (_) {/* animations may never settle; already pumped */}

  FlutterError.onError = prev;
  final tex = tester.takeException();
  if (tex != null) errors.add('takeException: $tex');
  return errors;
}

void main() {
  setUpAll(() {
    fx = jsonDecode(File('test/_fixtures.json').readAsStringSync())
        as Map<String, dynamic>;
    lrId = ((fx['/lrs']['data'] as List).first as Map)['id'] as String;
  });

  final screens = <String, Widget Function()>{
    'DashboardScreen': () => const DashboardScreen(),
    'LrListScreen': () => const LrListScreen(),
    'CreateLrScreen(new)': () => const CreateLrScreen(),
    'LrDetailScreen': () => LrDetailScreen(id: lrId),
    'PrintLrScreen': () => PrintLrScreen(id: lrId),
    'CreateLrScreen(edit)': () => CreateLrScreen(editId: lrId),
    'PartiesScreen': () => const PartiesScreen(),
    'RoutesScreen': () => const RoutesScreen(),
    'VehiclesScreen': () => const VehiclesScreen(),
    'TransportersScreen': () => const TransportersScreen(),
    'DriversScreen': () => const DriversScreen(),
    'ConsignorsScreen': () => const ConsignorsScreen(),
    'ConsigneesScreen': () => const ConsigneesScreen(),
    'PartDescriptionsScreen': () => const PartDescriptionsScreen(),
    'UsersAdminScreen': () => const UsersAdminScreen(),
    'AdminScreen': () => const AdminScreen(),
    'SettingsScreen': () => const SettingsScreen(),
    'RegionsScreen': () => const RegionsScreen(),
    'NumberingScreen': () => const NumberingScreen(),
    'LrFormatScreen': () => const LrFormatScreen(),
    'CapacityOptionsScreen': () => const CapacityOptionsScreen(),
    'AuditScreen': () => const AuditScreen(),
    'ReportsScreen': () => const ReportsScreen(),
    'AccountsScreen': () => const AccountsScreen(),
    'WarehouseScreen': () => const WarehouseScreen(),
    'EwbScreen': () => const EwbScreen(),
    'ProfileScreen': () => const ProfileScreen(),
  };

  screens.forEach((name, build) {
    testWidgets('SMOKE $name', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      List<String> errs;
      try {
        errs = await mountAndCollect(tester, name, build());
      } catch (e, st) {
        errs = ['THREW ON MOUNT: $e\n${st.toString().split('\n').take(6).join('\n')}'];
      }
      if (errs.isNotEmpty) {
        // ignore: avoid_print
        print('\n@@@ $name -> ${errs.length} error(s)');
        for (final e in errs.take(3)) {
          // ignore: avoid_print
          print('@@@   ${e.split('\n').take(4).join(' | ')}');
        }
      } else {
        // ignore: avoid_print
        print('@@@ $name -> OK');
      }
    });
  });
}
