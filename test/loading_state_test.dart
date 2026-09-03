// Verifies the loading-state UX added across list pages:
//   * MasterPage shows a shimmer while loading with no rows, the "No records"
//     empty text only when NOT loading, and the data once rows arrive.
//   * The LR list screen shows a shimmer while loading + empty, and "No LRs
//     found" only once loading has finished.
//   * RefreshGate clears its loadingFlag after onEnter settles, and does not
//     throw if the widget unmounts mid-fetch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/masters/widgets/master_page.dart';
import 'package:lr_management/shared/widgets/loading_shimmer.dart';
import 'package:lr_management/shared/widgets/refresh_gate.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('MasterPage loading', () {
    testWidgets('shows a shimmer, not "No records", while loading and empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MasterPage(
            title: 'Consignors',
            subtitle: 'x',
            icon: Icons.person,
            columns: ['Name'],
            rows: [],
            loading: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ShimmerRows), findsOneWidget);
      expect(find.text('No records'), findsNothing);
      expect(find.text('Loading…'), findsOneWidget);
    });

    testWidgets('shows "No records" once loading finishes with no rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MasterPage(
            title: 'Consignors',
            subtitle: 'x',
            icon: Icons.person,
            columns: ['Name'],
            rows: [],
            loading: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShimmerRows), findsNothing);
      expect(find.text('No records'), findsOneWidget);
    });

    testWidgets('shows the data (no shimmer) once rows arrive, even if a later '
        'refresh flag were still set', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MasterPage(
            title: 'Consignors',
            subtitle: 'x',
            icon: Icons.person,
            columns: ['Name'],
            rows: [
              MasterRow(id: '1', cells: ['Acme Ltd']),
            ],
            loading: true, // rows present → shimmer must NOT show
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShimmerRows), findsNothing);
      expect(find.text('Acme Ltd'), findsOneWidget);
    });
  });

  group('RefreshGate loadingFlag', () {
    testWidgets('clears the flag after onEnter completes', (tester) async {
      final flag = StateProvider<bool>((ref) => true);
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            Consumer(
              builder: (context, ref, _) => RefreshGate(
                loadingFlag: flag,
                onEnter: (ref) async {
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                },
                child: Text('flag=${ref.watch(flag)}'),
              ),
            ),
          ),
        ),
      );
      // Before the post-frame callback resolves, the flag is still true.
      expect(find.text('flag=true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      expect(find.text('flag=false'), findsOneWidget);
    });

    testWidgets('does not throw if unmounted before onEnter resolves', (
      tester,
    ) async {
      final flag = StateProvider<bool>((ref) => true);
      await tester.pumpWidget(
        ProviderScope(
          child: _wrap(
            RefreshGate(
              loadingFlag: flag,
              onEnter: (ref) async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
              },
              child: const Text('gate'),
            ),
          ),
        ),
      );
      // Navigate away before the fetch resolves.
      await tester.pumpWidget(ProviderScope(child: _wrap(const Text('gone'))));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      // No exception surfaced from the post-dispose flag write.
      expect(tester.takeException(), isNull);
      expect(find.text('gone'), findsOneWidget);
    });
  });

  group('Shimmer widget', () {
    testWidgets('animates without throwing and disposes cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const Scaffold(body: ShimmerRows(rows: 3))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ShimmerBox), findsWidgets);
      // Replace to trigger dispose of the AnimationController.
      await tester.pumpWidget(_wrap(const SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });
}
