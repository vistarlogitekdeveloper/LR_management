// The Active/History switch now rides in the Live Tracking header row, so it
// has to survive both of AppTopbar's layouts: the single Row at >=900 px (which
// hands actions UNBOUNDED width) and the stacked Wrap below it. These pin it at
// both ends of the supported range, including textScaler 2.0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/shell/widgets/app_topbar.dart';
import 'package:lr_management/features/tracking/data/trip_history.dart';
import 'package:lr_management/features/tracking/widgets/tracking_tabs.dart';
import 'package:lr_management/shared/widgets/app_button.dart';

/// Pumps the switch exactly as the screen uses it: as the first of AppTopbar's
/// actions, ahead of Refresh.
Future<void> _pumpAt(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  TrackingTab selected = TrackingTab.active,
  ValueChanged<TrackingTab>? onChanged,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Column(
            children: [
              AppTopbar(
                title: 'Live Tracking',
                subtitle: 'All active vehicles',
                actions: [
                  TrackingTabs(
                    selected: selected,
                    onChanged: onChanged ?? (_) {},
                    activeCount: 30,
                    historyCount: 324,
                  ),
                  const AppButton(
                    label: 'Refresh',
                    icon: Icons.refresh_rounded,
                    kind: BtnKind.ghost,
                    small: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('sits in the header row on a 360 px viewport', (tester) async {
    await _pumpAt(tester, size: const Size(360, 720));
    expect(tester.takeException(), isNull);
    expect(find.text('Active trips'), findsOneWidget);
  });

  testWidgets('sits in the header row at 360 px, textScaler 2.0', (
    tester,
  ) async {
    await _pumpAt(tester, size: const Size(360, 720), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives AppTopbar unbounded action width at 900 px', (
    tester,
  ) async {
    // 900 is AppTopbar's switch to a single Row, where a non-flex action gets
    // maxWidth: Infinity — the case a greedy scroll view would assert on.
    await _pumpAt(tester, size: const Size(900, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives the unbounded Row at 900 px, textScaler 2.0', (
    tester,
  ) async {
    await _pumpAt(tester, size: const Size(900, 800), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sits in the header row on a 1920 px viewport', (tester) async {
    await _pumpAt(tester, size: const Size(1920, 1080));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares the header row with Refresh on a wide viewport', (
    tester,
  ) async {
    await _pumpAt(tester, size: const Size(1440, 900));

    // Same vertical band as the title and Refresh — that is the whole point of
    // the move, and a regression here would silently restore the extra row.
    final title = tester.getRect(find.text('Live Tracking'));
    final tabs = tester.getRect(find.text('Active trips'));
    final refresh = tester.getRect(find.text('Refresh'));
    expect(tabs.center.dy, closeTo(title.center.dy, 40));
    expect(tabs.center.dy, closeTo(refresh.center.dy, 4));
    expect(tabs.left, greaterThan(title.right));
    expect(refresh.left, greaterThan(tabs.right));
  });

  testWidgets('reports the selection and its count to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpAt(tester, size: const Size(1280, 800));

    // One merged node per tab, carrying the name and the count together.
    final active = tester.getSemantics(
      find.ancestor(
        of: find.text('Active trips'),
        matching: find.byType(MergeSemantics),
      ),
    );
    expect(active.label, contains('Active trips'));
    expect(active.label, contains('30'));

    final history = tester.getSemantics(
      find.ancestor(
        of: find.text('History'),
        matching: find.byType(MergeSemantics),
      ),
    );
    expect(history.label, contains('History'));
    expect(history.label, contains('324'));

    handle.dispose();
  });

  testWidgets('switching tabs reports the new tab once', (tester) async {
    final picked = <TrackingTab>[];
    await _pumpAt(tester, size: const Size(1280, 800), onChanged: picked.add);

    await tester.tap(find.text('History'));
    await tester.pump();
    // Re-tapping the tab already shown must not fire again.
    await tester.tap(find.text('Active trips'));
    await tester.pump();

    expect(picked, [TrackingTab.history]);
  });
}
