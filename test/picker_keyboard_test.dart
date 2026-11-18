// The searchable pickers (Vehicle, Driver, Transporter, Route, filters) work
// from the keyboard: type to filter, Up / Down to move, Enter to pick, Esc to
// close — focus stays in the search box.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/widgets/searchable_field.dart';

void main() {
  Future<List<String?>> pumpPicker(
    WidgetTester tester, {
    String? initial,
    Future<String?> Function(String query)? onAddNew,
  }) async {
    final changes = <String?>[];
    String? value = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 260,
              child: SearchableField<String>(
                value: value,
                options: const ['CG04NZ6578', 'DD01M9163', 'MH12AB1234'],
                labelOf: (v) => v,
                hintText: 'Select vehicle',
                clearable: true,
                onAddNew: onAddNew,
                addNewLabel: 'Add new vehicle',
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

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pumpAndSettle();
  }

  testWidgets('Enter picks the first option', (tester) async {
    final changes = await pumpPicker(tester, onAddNew: (_) async => null);
    await open(tester, 'Select vehicle');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['CG04NZ6578']);
  });

  testWidgets('Down twice then Enter picks the third option', (tester) async {
    final changes = await pumpPicker(tester);
    await open(tester, 'Select vehicle');
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['MH12AB1234']);
  });

  testWidgets('Up from the first option reaches None, then Add new', (
    tester,
  ) async {
    final changes = await pumpPicker(tester, onAddNew: (q) async => 'NEW-$q');
    await open(tester, 'Select vehicle');
    await key(tester, LogicalKeyboardKey.arrowUp);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, [null], reason: 'None clears the field');

    await open(tester, 'Select vehicle');
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes.last, 'NEW-');
  });

  testWidgets('typing filters, and Enter picks the top match', (tester) async {
    final changes = await pumpPicker(tester);
    await open(tester, 'Select vehicle');
    await tester.enterText(find.byType(TextField), 'dd01');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['DD01M9163']);
  });

  testWidgets('Enter on a search with no match opens Add new with the text', (
    tester,
  ) async {
    final changes = await pumpPicker(tester, onAddNew: (q) async => 'NEW-$q');
    await open(tester, 'Select vehicle');
    await tester.enterText(find.byType(TextField), 'KA01ZZ');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['NEW-KA01ZZ']);
  });

  testWidgets('arrows start from the current value', (tester) async {
    final changes = await pumpPicker(tester, initial: 'DD01M9163');
    await open(tester, 'DD01M9163');
    await key(tester, LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, ['MH12AB1234']);
  });

  testWidgets('Esc closes without changing anything', (tester) async {
    final changes = await pumpPicker(tester);
    await open(tester, 'Select vehicle');
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Search…'), findsNothing);
    expect(changes, isEmpty);
  });
}
