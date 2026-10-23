// Two-point delivery, detention / express charges and the edit lock
// (2026-10-23, backend migration 222). The client gates mirror the server:
//   - POST /lrs with delivery_points 2: LR_TWO_POINT_DELIVERY or SUPERADMIN_ACCESS
//   - detention / express charges: LR_EXTRA_CHARGES or SUPERADMIN_ACCESS
//   - PATCH /lrs/:id beyond the payment fields: the super admin alone
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/lr/widgets/balance_charges_fields.dart';
import 'package:lr_management/features/lr/widgets/delivery_points_section.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/models/party.dart';
import 'package:lr_management/shared/models/user.dart';

AppUser _user(List<String> permissions, {UserRole role = UserRole.operator}) =>
    AppUser(
      username: 'tester',
      role: role,
      name: 'Tester',
      permissions: permissions,
    );

Party _party(String id, String name, String city) => Party(
  id: id,
  name: name,
  gst: '',
  city: city,
  address: '',
  contact: '',
  mobile: '',
  email: '',
  isConsignee: true,
);

void main() {
  group('who may do what', () {
    test(
      'Edit LR: the super admin alone, not an admin or an LR_EDIT holder',
      () {
        expect(_user(['LR_EDIT', 'ADMIN_ACCESS']).canEditLrDetails, isFalse);
        expect(_user(['LR_EDIT']).canEditLr, isTrue, reason: 'status / POD');
        expect(_user(['SUPERADMIN_ACCESS']).canEditLrDetails, isTrue);
        expect(_user([], role: UserRole.superAdmin).canEditLrDetails, isTrue);
      },
    );

    test(
      'two-point delivery and extra charges: granted, or the super admin',
      () {
        final admin = _user(['ADMIN_ACCESS', 'LR_CREATE']);
        expect(admin.canTwoPointDelivery, isFalse);
        expect(admin.canAddExtraCharges, isFalse);
        expect(_user(['LR_TWO_POINT_DELIVERY']).canTwoPointDelivery, isTrue);
        expect(_user(['LR_EXTRA_CHARGES']).canAddExtraCharges, isTrue);
        final sa = _user(['SUPERADMIN_ACCESS']);
        expect(sa.canTwoPointDelivery && sa.canAddExtraCharges, isTrue);
      },
    );
  });

  group('the LR model', () {
    test('reads the second drop and detention; single point by default', () {
      final lr = LorryReceipt.fromJson({
        'id': 'lr1',
        'number': 'LR/PUN/26-27/00009',
        'lr_date': '2026-10-23',
        'delivery_points': 2,
        'secondConsignee': {
          'id': 'c2',
          'name': 'TATA MOTORS',
          'city': 'Chakan',
        },
        'second_to_city': 'Chakan',
        'freight': 20000,
        'halting_charge': 500,
        'detention_charges': 700,
      });
      expect(lr.isTwoPoint, isTrue);
      expect(lr.secondConsignee!.name, 'TATA MOTORS');
      expect(lr.secondToCity, 'Chakan');
      expect(lr.freight.detentionCharges, 700);
      expect(lr.freight.total, 21200, reason: 'detention is in the total');

      final single = LorryReceipt.fromJson({'id': 'lr2', 'number': 'X'});
      expect(single.deliveryPoints, 1);
      expect(single.isTwoPoint, isFalse);
    });
  });

  group('the delivery points picker', () {
    testWidgets('single point first; two-point asks for another consignee', (
      tester,
    ) async {
      final a = _party('c1', 'BAJAJ', 'Bhosari');
      final b = _party('c2', 'TATA MOTORS', 'Chakan');
      var points = 1;
      Party? second;
      Widget build() => MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DeliveryPointsSection(
              points: points,
              first: a,
              second: second,
              options: [a, b],
              onPointsChanged: (v) => setState(() => points = v),
              onSecondChanged: (v) => setState(() => second = v),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build());
      expect(find.byKey(const ValueKey('second-consignee')), findsNothing);
      await tester.tap(find.text('Two-point'));
      await tester.pumpAndSettle();
      expect(points, 2);
      expect(find.byKey(const ValueKey('second-consignee')), findsOneWidget);
      expect(find.textContaining('Accounts and Management'), findsOneWidget);
      await tester.tap(find.text('Single point'));
      await tester.pumpAndSettle();
      expect(points, 1);
    });
  });

  group('charges with the balance POD', () {
    test('only the boxes with an amount are sent; a bad amount is null', () {
      expect(BalanceChargesFields.valuesOf('', ''), isEmpty);
      expect(BalanceChargesFields.valuesOf(' 750 ', ''), {
        'detention_charges': '750',
      });
      expect(BalanceChargesFields.valuesOf('100', '2500.5'), {
        'detention_charges': '100',
        'express_charges': '2500.5',
      });
      expect(BalanceChargesFields.valuesOf('-1', ''), isNull);
      expect(BalanceChargesFields.valuesOf('', 'abc'), isNull);
    });
  });
}
