import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/core/telemetry/telemetry.dart';
import 'package:lr_management/shared/models/user.dart';

const _uuid = '7f3c2a10-1b2c-4d5e-8f90-a1b2c3d4e5f6';

void main() {
  test('screen names carry no record ids', () {
    expect(Telemetry.routePattern('/dashboard'), '/dashboard');
    expect(Telemetry.routePattern('/lrs/$_uuid'), '/lrs/:id');
    expect(Telemetry.routePattern('/lrs/$_uuid/edit?tab=2'), '/lrs/:id/edit');
    expect(Telemetry.routePattern('/tracking/lr/$_uuid'), '/tracking/lr/:id');
    expect(Telemetry.routePattern('/lrs/42/print'), '/lrs/:id/print');
    expect(
      Telemetry.routePattern('/admin/invoice-settings'),
      '/admin/invoice-settings',
    );
    expect(
      Telemetry.routePattern('/masters/part-descriptions'),
      isNot(contains(':')),
    );
    // The splash carries the page to return to in its query: dropped.
    expect(
      Telemetry.routePattern('/splash?from=%2Flrs%2FVLL-PUN-00012'),
      '/splash',
    );
  });

  test('LR numbers and vehicle plates become :ref', () {
    // LR numbers in the formats the numbering screen can produce.
    expect(Telemetry.routePattern('/lrs/VLL-PUN-26-27-00012'), '/lrs/:ref');
    expect(Telemetry.routePattern('/lrs/LR12'), '/lrs/:ref');
    expect(Telemetry.routePattern('/lrs/vll2627pun00012'), '/lrs/:ref');
    // One with `/` in it splits into segments: every one is replaced.
    expect(
      Telemetry.routePattern('/lrs/VLL/PUN/26-27/00012'),
      '/lrs/:ref/:ref/:ref/:id',
    );
    // Vehicle plates, with and without (encoded) spaces, any case.
    expect(Telemetry.routePattern('/vehicles/MH12AB1234'), '/vehicles/:ref');
    expect(Telemetry.routePattern('/vehicles/mh12ab1234'), '/vehicles/:ref');
    expect(
      Telemetry.routePattern('/vehicles/MH%2012%20AB%201234'),
      '/vehicles/:ref',
    );
    expect(
      Telemetry.routePattern('/lookups/manage/VEHICLE_CAPACITY'),
      '/lookups/manage/:ref',
    );
  });

  test('the LR journey is named from successful writes', () {
    expect(Telemetry.actionFor('POST', '/lrs'), 'lr_created');
    expect(Telemetry.actionFor('PATCH', '/lrs/$_uuid'), 'lr_updated');
    expect(Telemetry.actionFor('DELETE', '/lrs/$_uuid'), 'lr_deleted');
    expect(
      Telemetry.actionFor('POST', '/lrs/$_uuid/status'),
      'lr_status_changed',
    );
    expect(
      Telemetry.actionFor('POST', '/lrs/$_uuid/send-for-payment'),
      'lr_sent_for_payment',
    );
    expect(
      Telemetry.actionFor('POST', '/lrs/$_uuid/advance-paid'),
      'lr_advance_paid',
    );
    expect(
      Telemetry.actionFor('POST', '/lrs/$_uuid/payment-complete'),
      'lr_payment_completed',
    );
    expect(
      Telemetry.actionFor('POST', '/lrs/$_uuid/attachments'),
      'lr_attachment_uploaded',
    );
    expect(
      Telemetry.actionFor('DELETE', '/lrs/$_uuid/attachments/$_uuid'),
      'lr_attachment_deleted',
    );
    expect(Telemetry.actionFor('POST', '/ewb'), 'ewb_created');
    expect(
      Telemetry.actionFor('post', '/ewb/$_uuid/validate'),
      'ewb_validated',
    );
    expect(Telemetry.actionFor('POST', '/invoices'), 'invoice_created');
    expect(
      Telemetry.actionFor('POST', '/invoices/$_uuid/cancel'),
      'invoice_cancelled',
    );
    expect(
      Telemetry.actionFor('POST', '/tracking/lr/$_uuid/start'),
      'tracking_started',
    );
    expect(Telemetry.actionFor('POST', '/reports/mis/import'), 'mis_imported');
  });

  test('masters, admin and settings writes are named', () {
    expect(Telemetry.actionFor('POST', '/parties'), 'party_created');
    expect(Telemetry.actionFor('PATCH', '/vehicles/$_uuid'), 'vehicle_updated');
    expect(
      Telemetry.actionFor('DELETE', '/part-descriptions/$_uuid'),
      'part_description_deleted',
    );
    expect(
      Telemetry.actionFor('POST', '/transporters/$_uuid/document'),
      'transporter_document_uploaded',
    );
    expect(
      Telemetry.actionFor('POST', '/drivers/$_uuid/document'),
      'driver_document_uploaded',
    );
    expect(Telemetry.actionFor('POST', '/admin/users'), 'user_created');
    expect(
      Telemetry.actionFor('PUT', '/admin/users/$_uuid/permissions'),
      'user_permissions_changed',
    );
    expect(
      Telemetry.actionFor('POST', '/lookups/manage/VEHICLE_CAPACITY'),
      'lookup_option_created',
    );
    expect(
      Telemetry.actionFor('PATCH', '/system/numbering'),
      'lr_numbering_updated',
    );
    expect(
      Telemetry.actionFor('PUT', '/invoices/settings'),
      'invoice_settings_updated',
    );
  });

  test('reads, other methods, sign-in and unknown paths are not reported', () {
    expect(Telemetry.actionFor('GET', '/lrs'), isNull);
    expect(Telemetry.actionFor('GET', '/lrs/$_uuid'), isNull);
    expect(Telemetry.actionFor('GET', '/reports/mis.xlsx'), isNull);
    expect(Telemetry.actionFor('PUT', '/lrs/$_uuid'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/login'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/logout'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/refresh'), isNull);
    expect(Telemetry.actionFor('POST', '/somewhere/new'), isNull);
  });

  test('the user model reads the organisation code for the identify trait', () {
    final user = AppUser.fromJson({
      'id': _uuid,
      'username': 'someone',
      'role': {'id': 'r1', 'code': 'ACCOUNTS', 'name': 'Accounts'},
      'tenant': {'id': 't1', 'code': 'VISTAR', 'name': 'Vistar'},
    });
    expect(user.tenantCode, 'VISTAR');
    expect(user.role.code, 'ACCOUNTS');
    // The admin user list has no tenant object: null, not a throw.
    expect(
      AppUser.fromJson({'username': 'x', 'role': 'ADMIN'}).tenantCode,
      isNull,
    );
  });

  test(
    'off without ET_APP_ID and ET_WRITE_KEY (the default build); calls are safe',
    () async {
      expect(Telemetry.enabled, isFalse);
      await Telemetry.init();
      Telemetry.screen('/dashboard');
      Telemetry.track('lr_created');
      Telemetry.clientError(StateError('x'), source: 'zone', fatal: true);
      Telemetry.signedIn(userId: 'u1', role: 'ADMIN', tenant: 'VISTAR');
      Telemetry.signedOut();
    },
  );
}
