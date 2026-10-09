import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/tracking/data/fleet_filter.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';
import 'package:lr_management/features/tracking/widgets/halt_widgets.dart';

// A truck standing within ~2 km for 5 h raises the halt alert (server:
// services/tripHalt.service.js); the app shows it on Live Tracking and the
// trip screen, and lets someone acknowledge it with the reason.
void main() {
  Map<String, dynamic> haltJson({
    double hours = 12.5,
    bool ongoing = true,
    String? ack,
  }) => {
    'id': 'h1',
    'started_at': '2026-10-08T16:10:00.000Z',
    'ended_at': ongoing ? null : '2026-10-09T04:40:00.000Z',
    'ongoing': ongoing,
    'hours': hours,
    'lat': 19.9975,
    'lng': 73.7898,
    'city': 'Nashik',
    'alerted': hours >= 10,
    'acknowledged_at': ack == null ? null : '2026-10-09T05:00:00.000Z',
    'ack_reason': ack,
  };

  test('a halt reads from the server, with a readable duration', () {
    final h = TripHalt.fromJson(haltJson());
    expect(h.ongoing, isTrue);
    expect(h.overAlertLimit, isTrue);
    expect(h.durationLabel, '12 h 30 m');
    expect(haltSummary(h), startsWith('Halted 12 h 30 m at Nashik since '));
    expect(h.acknowledged, isFalse);

    final acked = TripHalt.fromJson(haltJson(ack: 'BREAKDOWN'));
    expect(acked.ackReason, HaltReason.breakdown);
    expect(acked.acknowledged, isTrue);
  });

  FleetVehicle truck(String lr, Map<String, dynamic>? halt) =>
      FleetVehicle.fromJson({
        'lr_id': lr,
        'lr_number': 'LR/PUN/26-27/$lr',
        'signal': 'live',
        'halt': halt,
      });

  test('the "Halted 5h+" chip counts only ongoing halts of 5 h or more', () {
    final all = [
      truck('1', haltJson(hours: 12)),
      truck('2', haltJson(hours: 4)), // recorded, not yet alerted
      truck('3', null),
    ];
    expect(fleetScopeCounts(all, null)[FleetScope.halted], 1);
    expect(
      filterFleet(
        all,
        const FleetFilter(scope: FleetScope.halted),
      ).map((v) => v.lrId),
      ['1'],
    );
    // A halted truck is still on the road: it stays in "Live now" too.
    expect(fleetScopeCounts(all, null)[FleetScope.live], 3);
    expect(FleetScope.halted.label, 'Halted 5h+');
  });

  test(
    'a trip knows the halt it is in now, and an older server sends none',
    () {
      final t = LrTracking.fromJson({
        'lr_id': 'x',
        'halts': [haltJson(ongoing: false, hours: 3), haltJson(hours: 11)],
      });
      expect(t.halts, hasLength(2));
      expect(t.currentHalt?.hours, 11);
      expect(t.haltsSupported, isTrue);
      final old = LrTracking.fromJson({'lr_id': 'x'});
      expect(old.halts, isEmpty);
      expect(old.haltsSupported, isFalse);
      expect(
        FleetVehicle.fromJson({'lr_id': 'y', 'lr_number': 'L'}).halt,
        isNull,
      );
    },
  );
}
