// Vehicle tracking that cannot silently fail (2026-10-08).
//
// Tracking starts when an LR is saved and follows the phone of the LR's driver.
// These pin the app side of that: the LR form requires a driver with a usable
// mobile, a vehicle change no longer overwrites a hand-picked driver, the
// tracking panel says why it cannot start BEFORE Start is pressed (and offers a
// restart once a trip is over), and the consent status is read one way
// everywhere.
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/lr/utils/lr_driver_rules.dart';
import 'package:lr_management/features/tracking/data/tracking_action.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';
import 'package:lr_management/features/tracking/widgets/tracking_common.dart';
import 'package:lr_management/shared/models/driver.dart';

Driver _driver(
  String id, {
  String mobile = '9822011223',
  String name = 'RAMESH',
}) => Driver(id: id, name: name, mobile: mobile, licenseNo: 'L1');

LrTracking _tracking({
  String? state,
  String? driverName = 'RAMESH',
  String? driverMobile = '9822011223',
  bool? mobileValid = true,
  bool? active = true,
  bool closed = false,
  bool canRestart = false,
}) => LrTracking(
  lrId: 'lr1',
  trackingState: state,
  driverName: driverName,
  driverMobile: driverMobile,
  driverMobileValid: mobileValid,
  driverActive: active,
  lrClosed: closed,
  canRestart: canRestart,
);

void main() {
  group('lrDriverError (LR form)', () {
    test('a driver is required on a new or open LR', () {
      expect(
        lrDriverError(driver: null, closed: false),
        contains('Select a driver'),
      );
    });

    test('a delivered / cancelled LR may stay without one', () {
      expect(lrDriverError(driver: null, closed: true), isNull);
    });

    test('a driver with a valid mobile is fine, however it was typed', () {
      for (final m in [
        '9822011223',
        '+91 98220 11223',
        '09822011223',
        '9123456789',
      ]) {
        expect(
          lrDriverError(driver: _driver('d1', mobile: m), closed: false),
          isNull,
          reason: m,
        );
      }
    });

    test('a driver with no or a bad mobile is refused, by name', () {
      expect(
        lrDriverError(driver: _driver('d1', mobile: ''), closed: false),
        contains('RAMESH has no mobile number'),
      );
      expect(
        lrDriverError(driver: _driver('d1', mobile: '98220'), closed: false),
        contains("RAMESH's mobile (98220) is not a valid 10-digit number"),
      );
    });

    test(
      'the driver already saved on the LR is not re-checked (like the server)',
      () {
        expect(
          lrDriverError(
            driver: _driver('d1', mobile: 'bad'),
            closed: false,
            savedDriverId: 'd1',
          ),
          isNull,
        );
        expect(
          lrDriverError(
            driver: _driver('d2', mobile: 'bad'),
            closed: false,
            savedDriverId: 'd1',
          ),
          isNotNull,
        );
      },
    );
  });

  group('driverAfterVehicleChange', () {
    final vehicleDriver = _driver('vd');

    test('an empty driver field takes the vehicle\'s driver', () {
      final d = driverAfterVehicleChange(
        current: null,
        previousVehicleDriverId: null,
        newVehicleDriver: vehicleDriver,
      );
      expect(d?.id, 'vd');
    });

    test('a driver the previous vehicle brought is replaced', () {
      final d = driverAfterVehicleChange(
        current: _driver('old-vehicle-driver'),
        previousVehicleDriverId: 'old-vehicle-driver',
        newVehicleDriver: vehicleDriver,
      );
      expect(d?.id, 'vd');
    });

    test(
      'a hand-picked driver is kept (it used to be overwritten silently)',
      () {
        final d = driverAfterVehicleChange(
          current: _driver('picked'),
          previousVehicleDriverId: 'old-vehicle-driver',
          newVehicleDriver: vehicleDriver,
        );
        expect(d?.id, 'picked');
      },
    );

    test('a vehicle with no driver changes nothing', () {
      final d = driverAfterVehicleChange(
        current: _driver('picked'),
        previousVehicleDriverId: null,
        newVehicleDriver: null,
      );
      expect(d?.id, 'picked');
    });
  });

  group('trackingActionFor (tracking panel)', () {
    TrackingAction act(LrTracking t, {bool canStart = true}) =>
        trackingActionFor(t, canStart: canStart);

    test('no trip and everything in order: Start', () {
      expect(act(_tracking()), TrackingAction.start);
    });

    test('a live trip offers nothing to start', () {
      expect(act(_tracking(state: 'RUNNING')), TrackingAction.none);
      expect(act(_tracking(state: 'SUBMITTED')), TrackingAction.none);
    });

    test('a stopped / ended trip on an open LR offers Restart', () {
      expect(
        act(_tracking(state: 'STOPPED', canRestart: true)),
        TrackingAction.restart,
      );
      expect(
        act(_tracking(state: 'ENDED', canRestart: true)),
        TrackingAction.restart,
      );
      expect(
        act(_tracking(state: 'ENDED')),
        TrackingAction.none,
        reason: 'server said no',
      );
    });

    test('each reason Start would fail is named before it is pressed', () {
      expect(act(_tracking(), canStart: false), TrackingAction.noPermission);
      expect(act(_tracking(driverName: '')), TrackingAction.noDriver);
      expect(act(_tracking(active: false)), TrackingAction.inactiveDriver);
      expect(act(_tracking(mobileValid: false)), TrackingAction.badMobile);
    });

    test(
      'a closed LR that was never tracked says so instead of offering Start',
      () {
        expect(act(_tracking(closed: true)), TrackingAction.closed);
        expect(
          act(_tracking(closed: true, state: 'STOPPED')),
          TrackingAction.none,
        );
      },
    );

    test(
      'an older server that sends no readiness fields still shows Start',
      () {
        expect(
          act(_tracking(mobileValid: null, active: null)),
          TrackingAction.start,
        );
      },
    );
  });

  group('consent status', () {
    test('only ALLOWED is granted; a refusal is not "pending"', () {
      expect(consentKind('ALLOWED'), ConsentKind.granted);
      expect(consentKind('allowed'), ConsentKind.granted);
      expect(consentKind('PENDING'), ConsentKind.pending);
      expect(consentKind('CONSENT_PENDING'), ConsentKind.pending);
      // Both used to be misread: NOT_ALLOWED as pending (badge) and as granted
      // (fleet pin, which matched anything containing "ALLOW").
      expect(consentKind('NOT_ALLOWED'), ConsentKind.refused);
      expect(consentKind('DENIED'), ConsentKind.refused);
      expect(consentKind(null), ConsentKind.unknown);
      expect(consentKind(''), ConsentKind.unknown);
    });

    test('labels never show the raw provider code', () {
      expect(consentLabel('NOT_ALLOWED'), 'Consent not given');
      expect(consentLabel('ALLOWED'), 'Consent OK');
      expect(consentLabel('PENDING'), 'Consent pending');
    });
  });

  test('the tracking response parses the readiness fields', () {
    final t = LrTracking.fromJson({
      'lr_id': 'lr1',
      'driver_name': 'RAMESH',
      'driver_mobile': '98220',
      'driver_mobile_valid': false,
      'driver_active': true,
      'lr_closed': false,
      'can_restart': true,
      'tracking_state': 'STOPPED',
    });
    expect(t.driverMobile, '98220');
    expect(t.driverMobileValid, isFalse);
    expect(t.driverActive, isTrue);
    expect(t.canRestart, isTrue);
    expect(t.lrClosed, isFalse);
    expect(trackingActionFor(t, canStart: true), TrackingAction.badMobile);
  });
}
