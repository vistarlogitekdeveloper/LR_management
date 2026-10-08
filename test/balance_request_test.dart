// "Request for balance payment" (2026-10-08).
//
// After the advance is paid, the operator uploads the POD and requests the
// balance; Accounts sees it under "Balance Requested". These pin when the
// button is offered (mirroring the server's balanceRequestBlock), which LRs
// the Accounts filter shows, what counts as a POD, and that the dialog cannot
// be sent without one.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/lr/widgets/balance_request.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/widgets/app_button.dart';

Map<String, dynamic> _json({
  bool sent = true,
  num freight = 28500,
  num advance = 26000,
  String? balancePaidAt,
  String status = 'BOOKED',
  String? requestedAt,
  String? podId,
}) => {
  'id': 'lr1',
  'number': 'LR/SBN/26-27/02644',
  'lr_date': '2026-10-08',
  'version': 3,
  'sent_for_payment': sent,
  'freight': freight,
  'advance': advance,
  'balance_paid_at': balancePaidAt,
  'status': {'code': status},
  'balance_requested_at': requestedAt,
  'balance_request_pod_id': podId,
};

LorryReceipt _lr({
  bool sent = true,
  num freight = 28500,
  num advance = 26000,
  String? balancePaidAt,
  String status = 'BOOKED',
  String? requestedAt,
  String? podId,
}) => LorryReceipt.fromJson(
  _json(
    sent: sent,
    freight: freight,
    advance: advance,
    balancePaidAt: balancePaidAt,
    status: status,
    requestedAt: requestedAt,
    podId: podId,
  ),
);

void main() {
  group('when the balance can be requested', () {
    test('sent for payment, advance paid, balance outstanding: yes', () {
      expect(_lr().canRequestBalance, isTrue);
    });

    test('not before the advance is paid', () {
      expect(_lr(advance: 0).canRequestBalance, isFalse);
    });

    test('not once the balance is paid, or the advance covers the freight', () {
      expect(_lr(balancePaidAt: '2026-10-09').canRequestBalance, isFalse);
      expect(_lr(advance: 28500).canRequestBalance, isFalse);
    });

    test('not on a cancelled LR, or one not sent for payment', () {
      expect(_lr(status: 'CANCELLED').canRequestBalance, isFalse);
      expect(_lr(sent: false).canRequestBalance, isFalse);
    });

    test('still offered after a request, to replace the POD', () {
      final lr = _lr(requestedAt: '2026-10-08T10:00:00Z', podId: 'att1');
      expect(lr.isBalanceRequested, isTrue);
      expect(lr.canRequestBalance, isTrue);
      expect(lr.balanceRequestPodId, 'att1');
    });
  });

  group('the Accounts "Balance Requested" filter', () {
    test('lists a requested LR still waiting for its balance', () {
      expect(
        _lr(requestedAt: '2026-10-08T10:00:00Z').isBalanceRequested,
        isTrue,
      );
    });

    test('drops it once the balance is paid', () {
      expect(
        _lr(
          requestedAt: '2026-10-08T10:00:00Z',
          advance: 28500,
        ).isBalanceRequested,
        isFalse,
      );
      expect(
        _lr(
          requestedAt: '2026-10-08T10:00:00Z',
          balancePaidAt: '2026-10-09',
        ).isBalanceRequested,
        isFalse,
      );
    });

    test('never lists an LR that was not requested', () {
      expect(_lr().isBalanceRequested, isFalse);
    });

    test('an older backend (no request fields) changes nothing', () {
      final lr = LorryReceipt.fromJson(
        Map<String, dynamic>.from(_json())
          ..remove('balance_requested_at')
          ..remove('balance_request_pod_id'),
      );
      expect(lr.isBalanceRequested, isFalse);
      expect(lr.balanceRequestPodId, isNull);
      // ...and the button is not offered: the endpoint would only 404, so the
      // app can be deployed before the backend.
      expect(lr.balanceRequestSupported, isFalse);
      expect(lr.canRequestBalance, isFalse);
    });
  });

  test('a POD is a photo or a PDF under 25 MB', () {
    for (final name in [
      'pod.jpg',
      'POD.JPEG',
      'p.png',
      'IMG.HEIC',
      'scan.pdf',
    ]) {
      expect(podFileError(name, 1000), isNull, reason: name);
    }
    expect(podFileError('pod.xlsx', 1000), contains('photo'));
    expect(podFileError('pod', 1000), contains('photo'));
    expect(podFileError('pod.jpg', 0), contains('empty'));
    expect(podFileError('pod.jpg', 26 * 1024 * 1024), contains('25 MB'));
  });

  testWidgets('the request cannot be sent without a POD', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        showBalanceRequestDialog(context, ref, _lr()),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Request balance payment'), findsOneWidget);
    expect(find.text('POD (required)'), findsOneWidget);
    expect(find.text('No file chosen'), findsOneWidget);
    // The send button is there but disabled until a file is chosen.
    final send = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Request balance'),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('a requested LR opens as "Replace POD" with the POD links', (
    tester,
  ) async {
    final lr = _lr(requestedAt: '2026-10-08T10:00:00Z', podId: 'att1');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showBalanceRequestDialog(context, ref, lr),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Replace POD'), findsWidgets);
    expect(find.text('View POD'), findsOneWidget);
    expect(find.text('Download POD'), findsOneWidget);
  });
}
