// Regression test for the 412 VERSION_CONFLICT that made an LR uneditable.
//
// PATCH /ewb/:id enforces its own optimistic lock (If-Match), exactly as the LR
// does. The Flutter EwayBill model did not carry `version`, so the save path
// hard-coded If-Match: 0 — which matches only an E-way bill that has never been
// edited.
//
// The failure was self-perpetuating, which is why it looked like a permission
// problem: LrRepository.update() PATCHes the LR FIRST and the EWB second, so
// on the second edit of any LR carrying an EWB the LR saved (version +1) and
// the EWB step then threw. The form was left holding the pre-save LR version,
// and every retry answered 412 VERSION_CONFLICT with a current_version one
// higher than before.
//
// These pin the parsing that makes the correct version available to send.
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/models/lr_models.dart';

void main() {
  group('EwayBill.version', () {
    test('is parsed from the API response', () {
      final ewb = EwayBill.fromJson({
        'id': 'e1',
        'number': 'EWB123456789012',
        'expiry_at': '2026-10-15',
        'load_type_id': 'lt1',
        'validation_status': 'valid',
        'version': 3,
      });

      expect(ewb.version, 3);
      expect(ewb.id, 'e1');
      expect(ewb.number, 'EWB123456789012');
    });

    test('defaults to 0 when the field is absent', () {
      // A backend that predates the field must not crash the client, and 0 is
      // the server's own default for a never-edited row.
      final ewb = EwayBill.fromJson({'id': 'e1', 'number': 'EWB1'});
      expect(ewb.version, 0);
    });

    test('survives arriving as a string', () {
      // Numeric JSON fields reach this app as strings often enough that a plain
      // cast is a runtime crash waiting to happen.
      final ewb = EwayBill.fromJson({
        'id': 'e1',
        'number': 'EWB1',
        'version': '7',
      });
      expect(ewb.version, 7);
    });

    test(
      'a version above 0 is what the old hard-coded 0 would have missed',
      () {
        // The exact shape of the bug: an EWB edited once already.
        final ewb = EwayBill.fromJson({
          'id': 'e1',
          'number': 'EWB1',
          'version': 1,
        });
        expect(ewb.version, isNot(0));
        expect(ewb.version, 1);
      },
    );
  });

  group('LorryReceipt carries the EWB version through', () {
    Map<String, dynamic> lrJson(Map<String, dynamic> ewayBill) => {
      'id': 'lr1',
      'number': 'LR/PUN/26-27/01009',
      'lr_date': '2026-09-10',
      'entered_by': 'u1',
      'version': 5,
      'from_city': 'CHAKAN',
      'to_city': 'DEWAS',
      'ewayBill': ewayBill,
    };

    test('nested under the ewayBill association alias', () {
      final lr = LorryReceipt.fromJson(
        lrJson({'id': 'e1', 'number': 'EWB1', 'version': 2}),
      );

      // This is the value the edit form must send as If-Match on PATCH /ewb/:id.
      expect(lr.ewb, isNotNull);
      expect(lr.ewb!.version, 2);
      // And the LR's own lock counter stays separate — two independent locks.
      expect(lr.version, 5);
    });

    test('an LR with no EWB leaves ewb null, so nothing is sent', () {
      final lr = LorryReceipt.fromJson({
        'id': 'lr1',
        'number': 'LR/PUN/26-27/01010',
        'lr_date': '2026-09-10',
        'entered_by': 'u1',
        'version': 1,
      });
      expect(lr.ewb, isNull);
    });
  });
}
