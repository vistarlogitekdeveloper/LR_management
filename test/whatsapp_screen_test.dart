// Admin → WhatsApp Alerts (2026-11-02): status, per-alert switches, a test
// message and the delivery log, from the server's /whatsapp endpoints.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/admin/data/whatsapp_repository.dart';
import 'package:lr_management/features/admin/screens/whatsapp_screen.dart';

WhatsappStatus _status({bool enabled = true}) => WhatsappStatus.fromJson({
  'configured': true,
  'enabled': enabled,
  'alerts': [
    {
      'kind': 'SPECIAL_HALT',
      'label': 'Special vehicle halt',
      'template': 'vtms_special_halt',
      'on': true,
    },
    {
      'kind': 'HALT',
      'label': 'Vehicle halt (5 h+)',
      'template': 'vtms_halt',
      'on': false,
    },
  ],
});

Future<void> _pump(
  WidgetTester tester, {
  bool enabled = true,
  List<WhatsappMessage> log = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        whatsappStatusProvider.overrideWith(
          (ref) async => _status(enabled: enabled),
        ),
        whatsappMessagesProvider.overrideWith((ref) async => log),
      ],
      child: const MaterialApp(home: WhatsappScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('reads the server status and log rows', () {
    final s = _status();
    expect(s.enabled, isTrue);
    expect(s.alerts.map((a) => a.on), [true, false]);
    final m = WhatsappMessage.fromJson({
      'id': '1',
      'kind': 'SPECIAL_HALT',
      'to_phone': '919822011223',
      'template': 'vtms_special_halt',
      'status': 'failed',
      'error': '131026 Message undeliverable',
      'created_at': '2026-11-02T05:00:00Z',
    });
    expect(m.status, 'failed');
    expect(m.error, contains('131026'));
  });

  testWidgets('on: each alert has a switch, and the log shows status', (
    tester,
  ) async {
    await _pump(
      tester,
      log: [
        WhatsappMessage.fromJson({
          'id': '1',
          'kind': 'SPECIAL_HALT',
          'to_phone': '919822011223',
          'template': 't',
          'status': 'read',
        }),
      ],
    );
    expect(find.textContaining('alerts are being sent'), findsOneWidget);
    expect(find.text('Special vehicle halt'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('wa-HALT')))
          .value,
      isFalse,
    );
    expect(find.text('READ'), findsOneWidget);
    expect(find.textContaining('+919822011223'), findsOneWidget);
  });

  testWidgets('switched off on the server: said plainly, nothing sent yet', (
    tester,
  ) async {
    await _pump(tester, enabled: false);
    expect(find.textContaining('switched off on the server'), findsOneWidget);
    expect(find.text('Nothing sent yet.'), findsOneWidget);
  });
}
