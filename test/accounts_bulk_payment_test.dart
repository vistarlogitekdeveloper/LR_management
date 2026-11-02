// Accounts → tick several LRs and pay them at once (2026-11-02). Each LR goes
// through the same call as its own button, one after another: ineligible ones
// are skipped, one failure never stops the rest, failures stay ticked.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/accounts/data/bulk_payment.dart';
import 'package:lr_management/features/accounts/widgets/bulk_payment_bar.dart';
import 'package:lr_management/features/lr/data/lr_repository.dart';
import 'package:lr_management/features/lr/providers/lr_providers.dart';
import 'package:lr_management/shared/models/lr_models.dart';

LorryReceipt _lr(
  String id, {
  num freight = 20000,
  num advance = 0,
  int version = 1,
}) => LorryReceipt.fromJson({
  'id': id,
  'number': 'LR/PUN/26-27/$id',
  'version': version,
  'freight': freight,
  'advance': advance,
  'advance_percent': 90,
  'transporter': {'id': 't1', 'name': 'NEW MATOSHREE ROADLINES'},
});

class _Repo implements LrRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The LR list with the two payment calls recorded instead of sent.
class _Notifier extends LrNotifier {
  _Notifier(List<LorryReceipt> lrs, {this.failIds = const {}})
    : super(_Repo(), null) {
    state = lrs;
  }
  final Set<String> failIds;
  final calls = <String>[];

  @override
  Future<void> refresh({bool force = false}) async {}

  Future<LorryReceipt> _pay(String id, int version, double advance) async {
    calls.add('$id@$version');
    if (failIds.contains(id)) {
      throw Exception('LR was modified by someone else');
    }
    final lr = state.firstWhere((l) => l.id == id);
    final paid = _lr(
      id,
      freight: lr.freight.freight,
      advance: advance,
      version: version + 1,
    );
    state = [for (final l in state) l.id == id ? paid : l];
    return paid;
  }

  @override
  Future<LorryReceipt> markAdvancePaid(String id, int version) =>
      _pay(id, version, 18000);

  @override
  Future<LorryReceipt> completePayment(String id, int version) =>
      _pay(id, version, 20000);
}

void main() {
  group('who can take what', () {
    test('advance: none paid yet; complete: a balance left', () {
      expect(bulkEligible(_lr('1'), BulkPayAction.advance), isTrue);
      expect(
        bulkEligible(_lr('1', advance: 18000), BulkPayAction.advance),
        isFalse,
      );
      expect(
        bulkEligible(_lr('1', advance: 18000), BulkPayAction.complete),
        isTrue,
      );
      expect(
        bulkEligible(_lr('1', advance: 20000), BulkPayAction.complete),
        isFalse,
      );
      expect(
        bulkEligible(_lr('1', freight: 0), BulkPayAction.advance),
        isFalse,
      );
    });

    test('amounts as the server computes them', () {
      expect(
        bulkAmount(_lr('1', freight: 18800), BulkPayAction.advance),
        17000,
      );
      expect(
        bulkAmount(
          _lr('1', freight: 28500, advance: 26000),
          BulkPayAction.complete,
        ),
        2500,
      );
    });
  });

  test('the run: skips, survives a failure, uses the latest version', () async {
    final latest = {'2': _lr('2', version: 7)};
    final calls = <String>[];
    final progress = <String>[];
    final r = await runBulkPay(
      selected: [_lr('1'), _lr('2'), _lr('3', advance: 18000), _lr('4')],
      action: BulkPayAction.advance,
      fresh: (lr) => latest[lr.id] ?? lr,
      pay: (lr) async {
        calls.add('${lr.id}@${lr.version}');
        if (lr.id == '4') throw Exception('boom');
      },
      describe: (e) => '$e',
      onProgress: (d, t) => progress.add('$d/$t'),
    );
    expect(calls, ['1@1', '2@7', '4@1']);
    expect(r.paid.map((l) => l.id), ['1', '2']);
    expect(r.failed.single.lr.id, '4');
    expect(r.skipped.single.id, '3');
    expect(progress.last, '3/3');
  });

  testWidgets('tick all, pay, summary; the failure stays ticked', (
    tester,
  ) async {
    final lrs = [_lr('1'), _lr('2'), _lr('3', advance: 18000)];
    final notifier = _Notifier(lrs, failIds: {'2'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [lrListProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (_, ref, _) => BulkPaymentBar(
                items: ref.watch(lrListProvider),
                showAmounts: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Select LRs to pay several at once'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.text('Mark Advance Paid (2)'), findsOneWidget);
    expect(find.text('Complete Payment (3)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-advance')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Total to release'), findsOneWidget);
    expect(
      find.textContaining('1 selected LR(s) do not need this'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('bulk-confirm')));
    await tester.pumpAndSettle();

    expect(notifier.calls, ['1@1', '2@1']);
    expect(find.text('Done, with 1 failed'), findsOneWidget);
    expect(find.textContaining('Advance marked paid: 1 LR.'), findsOneWidget);
    expect(find.textContaining('LR/PUN/26-27/2'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.text('1 selected'),
      findsOneWidget,
      reason: 'the failed LR stays ticked',
    );
  });
}
