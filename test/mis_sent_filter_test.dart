// Verifies the MIS "payment stage" filter control end-to-end at the widget
// level: the SearchableField<bool> the reports screen uses must yield true for
// "Sent for advance", false for "Not yet sent", and null when cleared — the
// exact contract misXlsx(sentForPayment:) depends on. A false result must be
// distinct from a null (cleared) result, which is the subtle bit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/widgets/searchable_field.dart';

void main() {
  // Mounts the dropdown exactly as configured in reports_screen.dart and
  // returns a harness that records every onChanged value.
  Future<List<bool?>> pumpFilter(WidgetTester tester, {bool? initial}) async {
    final changes = <bool?>[];
    bool? value = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 190,
              child: SearchableField<bool>(
                value: value,
                options: const [true, false],
                labelOf: (v) => v ? 'Sent for advance' : 'Not yet sent',
                hintText: 'All LRs',
                dialogTitle: 'Payment stage',
                clearable: true,
                onChanged: (v) {
                  changes.add(v);
                  setState(() => value = v);
                },
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('defaults to "All LRs" when nothing is selected', (tester) async {
    await pumpFilter(tester);
    expect(find.text('All LRs'), findsOneWidget);
    expect(find.text('Sent for advance'), findsNothing);
  });

  testWidgets('picking "Sent for advance" yields true', (tester) async {
    final changes = await pumpFilter(tester);
    await tester.tap(find.text('All LRs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sent for advance').last);
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.text('Sent for advance'), findsOneWidget);
  });

  testWidgets('picking "Not yet sent" yields false (not null)', (tester) async {
    final changes = await pumpFilter(tester);
    await tester.tap(find.text('All LRs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not yet sent').last);
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(changes.first, isNotNull); // false must survive as false
  });

  testWidgets('clearing a selection yields null (back to "All LRs")', (
    tester,
  ) async {
    final changes = await pumpFilter(tester, initial: true);
    // Field shows the current selection.
    expect(find.text('Sent for advance'), findsOneWidget);
    await tester.tap(find.text('Sent for advance'));
    await tester.pumpAndSettle();
    // The clearable picker offers a "— None —" entry.
    await tester.tap(find.text('— None —'));
    await tester.pumpAndSettle();
    expect(changes, [null]);
    expect(find.text('All LRs'), findsOneWidget);
  });
}
