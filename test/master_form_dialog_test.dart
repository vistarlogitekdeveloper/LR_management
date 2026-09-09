import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/widgets/form_field_spec.dart';
import 'package:lr_management/shared/widgets/master_form_dialog.dart';

/// Regression tests for the "Edit Vehicle saved blanks over my data" incident.
///
/// The master save endpoints used to echo a row without its joined associations,
/// so the list row blanked out. Re-opening Edit on that blanked row then handed
/// this dialog empty values — and it silently preselected the FIRST option for a
/// required dropdown, so hitting Save wrote that arbitrary guess to the database.
/// The blanking is fixed on the server; these tests pin the dialog behaviour that
/// turned it into real data loss.

Future<Map<String, String>?> _pump(
  WidgetTester tester,
  List<FormFieldSpec> fields, {
  Map<String, String> initial = const {},
}) async {
  Map<String, String>? saved;
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MasterFormDialog(
          title: 'Edit Vehicle',
          fields: fields,
          initial: initial,
          onSave: (values) async {
            saved = values;
            return true;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return saved;
}

List<FormFieldSpec> _vehicleFields({String? type}) => [
  FormFieldSpec(name: 'number', label: 'Vehicle Number', required: true),
  FormFieldSpec(
    name: 'type',
    label: 'Vehicle Type',
    type: FieldType.dropdown,
    required: true,
    options: const ['Open Body', '10 MT', '20 MT'],
    initialValue: type,
  ),
];

void main() {
  testWidgets('an empty required dropdown does not preselect the first option', (
    tester,
  ) async {
    await _pump(tester, _vehicleFields(type: ''));

    // "Open Body" is merely first in the list — it must not be presented as the
    // vehicle's type just because the value arrived empty.
    expect(find.text('Open Body'), findsNothing);
    expect(find.text('Select Vehicle Type'), findsOneWidget);
  });

  testWidgets('Save is blocked, not silently guessed, when a required dropdown '
      'is empty', (tester) async {
    Map<String, String>? saved;
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MasterFormDialog(
            title: 'Edit Vehicle',
            fields: _vehicleFields(type: ''),
            initial: const {'number': 'MH18BG9318'},
            onSave: (values) async {
              saved = values;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(saved, isNull, reason: 'must not save an unset required dropdown');
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('a supplied dropdown value is preserved', (tester) async {
    await _pump(tester, _vehicleFields(type: '10 MT'));
    expect(find.text('10 MT'), findsOneWidget);
  });
}
