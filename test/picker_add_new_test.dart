// Verifies the "Add new …" entry the LR page's Vehicle / Driver / Transporter /
// Route pickers rely on: it appears only when the caller passes onAddNew (the
// permission gate — an operator without the master's manage permission gets a
// pick-only picker), it hands the typed search text to the create form, and the
// record the form returns is selected on the field.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/widgets/searchable_field.dart';

void main() {
  // Mounts a picker the way create_lr_screen.dart does. [onAddNew] null models
  // a user without the manage permission.
  Future<List<String?>> pumpPicker(
    WidgetTester tester, {
    Future<String?> Function(String query)? onAddNew,
  }) async {
    final changes = <String?>[];
    String? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 260,
              child: SearchableField<String>(
                value: value,
                options: const ['MH12AB1234', 'MH14XY9999'],
                labelOf: (v) => v,
                hintText: 'Select vehicle',
                dialogTitle: 'Select Vehicle',
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

  testWidgets('no add entry without the manage permission', (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Select vehicle'));
    await tester.pumpAndSettle();
    expect(find.text('Add new vehicle'), findsNothing);
    expect(find.text('MH12AB1234'), findsOneWidget);
  });

  testWidgets('the add entry shows for a permitted user', (tester) async {
    await pumpPicker(tester, onAddNew: (_) async => null);
    await tester.tap(find.text('Select vehicle'));
    await tester.pumpAndSettle();
    expect(find.text('Add new vehicle'), findsOneWidget);
  });

  testWidgets('the created record is selected on the field', (tester) async {
    final changes = await pumpPicker(
      tester,
      onAddNew: (query) async => 'MH20NEW0001',
    );
    await tester.tap(find.text('Select vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new vehicle'));
    await tester.pumpAndSettle();
    expect(changes, ['MH20NEW0001']);
    expect(find.text('MH20NEW0001'), findsOneWidget);
  });

  testWidgets('backing out of the create form changes nothing', (tester) async {
    final changes = await pumpPicker(tester, onAddNew: (_) async => null);
    await tester.tap(find.text('Select vehicle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new vehicle'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('Select vehicle'), findsOneWidget);
  });

  testWidgets('the typed search text reaches the create form and the entry '
      'survives a no-match search', (tester) async {
    String? seen;
    await pumpPicker(
      tester,
      onAddNew: (query) async {
        seen = query;
        return null;
      },
    );
    await tester.tap(find.text('Select vehicle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MH31ZZ');
    await tester.pumpAndSettle();
    // Nothing matches, which is exactly when adding one is wanted.
    expect(find.text('No matches'), findsOneWidget);
    await tester.tap(find.text('Add new vehicle "MH31ZZ"'));
    await tester.pumpAndSettle();
    expect(seen, 'MH31ZZ');
  });
}
