// The client gate on "Start tracking" has to mirror the server's exactly, or it
// either shows a button that 403s or hides an action the user is entitled to.
//
// Server authority (routes/trackingRoutes.js):
//   POST /tracking/lr/:id/start
//     -> perm.require(['TRACKING_START', 'ADMIN_ACCESS', 'SUPERADMIN_ACCESS'])
//
// These pin that list. If the route's allow-list changes, one of these fails.
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/models/user.dart';

AppUser _user(List<String> permissions, {UserRole role = UserRole.operator}) =>
    AppUser(
      username: 'tester',
      role: role,
      name: 'Tester',
      permissions: permissions,
    );

void main() {
  group('canStartTracking mirrors the server allow-list', () {
    test('granted by TRACKING_START alone', () {
      // The whole point of migration 142: an operator holding nothing else can
      // be given just this one capability.
      expect(_user(['TRACKING_START']).canStartTracking, isTrue);
    });

    test('granted by either admin umbrella', () {
      expect(_user(['ADMIN_ACCESS']).canStartTracking, isTrue);
      expect(_user(['SUPERADMIN_ACCESS']).canStartTracking, isTrue);
    });

    test('denied to a user holding only the tracking READ permission', () {
      // LR_VIEW opens the map, rechecks consent and shares the live link, but
      // starting a trip consumes the driver's SIM and is gated separately.
      expect(_user(['LR_VIEW']).canStartTracking, isFalse);
    });

    test('denied with no permissions at all', () {
      expect(_user(const []).canStartTracking, isFalse);
    });

    test('the role alone grants nothing — only the permissions do', () {
      // A user whose ROLE is admin but whose permission list is empty (every
      // toggle revoked per-user) must not get the button back through the role.
      expect(_user(const [], role: UserRole.admin).canStartTracking, isFalse);
      expect(
        _user(const [], role: UserRole.superAdmin).canStartTracking,
        isFalse,
      );
    });

    test('unrelated permissions do not leak the capability', () {
      expect(
        _user([
          'LR_CREATE',
          'LR_EDIT',
          'VEHICLE_BANK_VIEW',
          'MASTERS_MANAGE',
        ]).canStartTracking,
        isFalse,
      );
    });
  });

  group('the other tracking actions stay on LR_VIEW', () {
    test('a viewer keeps read access while losing start', () {
      final viewer = _user(['LR_VIEW']);
      // Guards against someone "fixing" the 403 by tightening the read gate
      // instead of granting the new permission.
      expect(viewer.can('LR_VIEW'), isTrue);
      expect(viewer.canStartTracking, isFalse);
    });
  });
}
