// Manual LR numbers on Create LR (2026-10-12): an operator may enter a number
// of their own, starting LR/Manual/ and unique in the organisation. The
// rules, the region code no longer read out of a manual number, and the
// banner: switching modes, the live check, and what it reports to the form.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/lr/data/lr_number_check.dart';
import 'package:lr_management/features/lr/data/lr_repository.dart';
import 'package:lr_management/features/lr/providers/lr_providers.dart';
import 'package:lr_management/features/lr/utils/manual_lr_entry.dart';
import 'package:lr_management/features/lr/utils/manual_lr_number.dart';
import 'package:lr_management/features/lr/widgets/lr_number_banner.dart';

void main() {
  group('the rule (mirrors the server)', () {
    test('the prefix is fixed; what is typed after it is upper-cased', () {
      expect(manualLrRest('pun/0001'), 'PUN/0001');
      expect(
        manualLrRest(' LR/Manual/pun/7 '),
        'PUN/7',
        reason: 'a pasted full number keeps its rest',
      );
      expect(manualLrRest('lr/manual/A1'), 'A1');
    });

    test('format errors', () {
      expect(manualLrRestError(''), contains('Type the number'));
      expect(manualLrRestError('PUN/0001'), isNull);
      expect(manualLrRestError('A-1_2.3'), isNull);
      expect(manualLrRestError('9' * 30), isNull, reason: '40 in all');
      expect(manualLrRestError('9' * 31), contains('Too long'));
      for (final bad in ['-1', '/1', 'A//1', 'A/', 'A B', 'A#1']) {
        expect(manualLrRestError(bad), isNotNull, reason: bad);
      }
    });

    test('isManualLrNumber in any case', () {
      expect(isManualLrNumber('LR/Manual/1'), isTrue);
      expect(isManualLrNumber('lr/MANUAL/1'), isTrue);
      expect(isManualLrNumber('LR/PUN/26-27/00001'), isFalse);
    });

    test('a save is blocked only by a wrong format or a used number', () {
      expect(
        const ManualLrEntry('LR/Manual/', ManualLrStatus.invalid, 'x').blocker,
        'x',
      );
      expect(
        const ManualLrEntry(
          'LR/Manual/1',
          ManualLrStatus.taken,
          'used',
        ).blocker,
        'used',
      );
      for (final s in [
        ManualLrStatus.available,
        ManualLrStatus.checking,
        ManualLrStatus.unknown,
      ]) {
        expect(
          ManualLrEntry('LR/Manual/1', s).blocker,
          isNull,
          reason: '$s — the server checks again',
        );
      }
    });
  });

  group('the region read out of an LR number', () {
    test('an automatic number names its region; a manual one names none', () {
      expect(regionCodeFromLrNumber('LR/PUN/26-27/00012'), 'PUN');
      expect(regionCodeFromLrNumber('LR/sbn/26-27/00012'), 'SBN');
      expect(
        regionCodeFromLrNumber('LR/Manual/PUN/0001'),
        isNull,
        reason: '"Manual" is not a region',
      );
      expect(regionCodeFromLrNumber('LR//26-27/00002'), isNull);
      expect(regionCodeFromLrNumber('LR'), isNull);
    });
  });

  group('the banner', () {
    testWidgets('automatic: the preview and an "Enter manually" switch', (
      tester,
    ) async {
      final h = await _pump(tester, _Repo());
      expect(find.text('LR/PUN/26-27/00002'), findsOneWidget);
      expect(find.text('Enter manually'), findsOneWidget);
      expect(h.reports, isEmpty);
    });

    testWidgets('manual: fixed prefix, live check, available', (tester) async {
      final repo = _Repo();
      final h = await _pump(tester, repo);
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      expect(find.text('LR Number (manual)'), findsOneWidget);
      expect(
        find.text('LR/Manual/'),
        findsOneWidget,
        reason: 'the prefix is shown, not typed',
      );
      expect(
        h.reports.last?.status,
        ManualLrStatus.invalid,
        reason: 'empty is not a number yet',
      );

      await tester.enterText(
        find.byKey(const ValueKey('manual-lr-number')),
        'pun/0001',
      );
      await tester.pump();
      expect(h.reports.last?.status, ManualLrStatus.checking);
      expect(repo.asked, isEmpty, reason: 'waits for typing to stop');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(repo.asked, ['LR/Manual/PUN/0001']);
      expect(h.reports.last?.status, ManualLrStatus.available);
      expect(h.reports.last?.number, 'LR/Manual/PUN/0001');
      expect(find.text('LR/Manual/PUN/0001 is available'), findsOneWidget);
    });

    testWidgets('a used number is reported with the server\'s message', (
      tester,
    ) async {
      final h = await _pump(tester, _Repo(taken: {'LR/Manual/7'}));
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-lr-number')),
        '7',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(h.reports.last?.status, ManualLrStatus.taken);
      expect(find.textContaining('already used'), findsOneWidget);
    });

    testWidgets('a wrong format is said at once, without asking the server', (
      tester,
    ) async {
      final repo = _Repo();
      final h = await _pump(tester, repo);
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-lr-number')),
        'A//1',
      );
      await tester.pump(const Duration(milliseconds: 450));
      expect(h.reports.last?.status, ManualLrStatus.invalid);
      expect(repo.asked, isEmpty);
    });

    testWidgets('pasting the whole number keeps only what follows the prefix', (
      tester,
    ) async {
      final h = await _pump(tester, _Repo());
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-lr-number')),
        'LR/Manual/pun/9',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('manual-lr-number')),
      );
      expect(field.controller!.text, 'PUN/9');
      expect(h.reports.last?.number, 'LR/Manual/PUN/9');
    });

    testWidgets('only the answer for what is typed now counts', (tester) async {
      final repo = _Repo(slow: true);
      final h = await _pump(tester, repo);
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('manual-lr-number'));
      await tester.enterText(field, '1');
      await tester.pump(const Duration(milliseconds: 450)); // asks for 1
      await tester.enterText(field, '12');
      await tester.pump(const Duration(milliseconds: 450)); // asks for 12
      repo.release('LR/Manual/12');
      await tester.pump();
      repo.release('LR/Manual/1'); // the stale answer arrives last
      await tester.pumpAndSettle();
      expect(h.reports.last?.number, 'LR/Manual/12');
      expect(h.reports.last?.status, ManualLrStatus.available);
    });

    testWidgets('the server unreachable: shown, and the save is not blocked', (
      tester,
    ) async {
      final h = await _pump(tester, _Repo(fails: true));
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-lr-number')),
        '5',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(h.reports.last?.status, ManualLrStatus.unknown);
      expect(h.reports.last?.blocker, isNull);
      expect(find.textContaining('checked again on save'), findsOneWidget);
    });

    testWidgets('"Use automatic" goes back: nothing manual is sent', (
      tester,
    ) async {
      final h = await _pump(tester, _Repo());
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('manual-lr-number')),
        '5',
      );
      await tester.tap(find.text('Use automatic'));
      await tester.pumpAndSettle();
      expect(h.reports.last, isNull);
      expect(find.text('LR/PUN/26-27/00002'), findsOneWidget);
    });

    testWidgets('editing an LR: its number, no way to change it', (
      tester,
    ) async {
      await _pump(tester, _Repo(), isEdit: true, number: 'LR/Manual/PUN/0001');
      expect(find.text('LR Number'), findsOneWidget);
      expect(find.text('LR/Manual/PUN/0001'), findsOneWidget);
      expect(find.text('Enter manually'), findsNothing);
    });

    testWidgets('fits a phone', (tester) async {
      await _pump(tester, _Repo(), size: const Size(360, 800));
      await tester.tap(find.text('Enter manually'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

class _Harness {
  final reports = <ManualLrEntry?>[];
}

Future<_Harness> _pump(
  WidgetTester tester,
  _Repo repo, {
  bool isEdit = false,
  String number = 'LR/PUN/26-27/00002',
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [lrRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: LrNumberBanner(
              isEdit: isEdit,
              number: number,
              onManualChanged: h.reports.add,
            ),
          ),
        ),
      ),
    ),
  );
  return h;
}

class _Repo implements LrRepository {
  _Repo({this.taken = const {}, this.fails = false, this.slow = false});
  final Set<String> taken;
  final bool fails;
  final bool slow;
  final asked = <String>[];
  final _pending = <String, Completer<LrNumberCheck>>{};

  void release(String number) =>
      _pending.remove(number)?.complete(_answer(number));

  LrNumberCheck _answer(String number) => taken.contains(number)
      ? LrNumberCheck(
          number: number,
          code: 'LR_NUMBER_TAKEN',
          message: 'LR number $number is already used.',
        )
      : LrNumberCheck(number: number, available: true);

  @override
  Future<LrNumberCheck> checkNumber(String number) async {
    asked.add(number);
    if (fails) throw Exception('offline');
    if (slow) return (_pending[number] = Completer<LrNumberCheck>()).future;
    return _answer(number);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
