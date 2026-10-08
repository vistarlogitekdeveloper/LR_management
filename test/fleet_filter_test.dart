import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/tracking/data/fleet_filter.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';
import 'package:lr_management/features/tracking/widgets/fleet_view.dart';

// "Active trips" listed LRs whose last position was 30-40 days old. Only trips
// actually reporting are active now; the stale ones get their own filter.
void main() {
  final now = DateTime(2026, 10, 8, 12);
  DateTime ago(int h) => now.subtract(Duration(hours: h));

  FleetVehicle v(
    String number, {
    FleetSignal signal = FleetSignal.live,
    DateTime? fixAt,
    String? consent = 'ALLOWED',
    String? state = 'RUNNING',
    String region = 'PUN',
    String? driver,
  }) => FleetVehicle(
    lrId: number,
    lrNumber: number,
    signal: signal,
    consentStatus: consent,
    trackingState: state,
    regionCode: region,
    driverName: driver,
    location: fixAt == null ? null : TrackPoint(lat: 1, lng: 1, at: fixAt),
  );

  group('fleetSignalOf', () {
    test('a fix within 24 h is live, older is no signal', () {
      expect(fleetSignalOf(lastFixAt: ago(2), now: now), FleetSignal.live);
      expect(
        fleetSignalOf(lastFixAt: ago(39 * 24), now: now),
        FleetSignal.noSignal,
      );
    });

    test('no fix: awaiting while young, no signal after a day', () {
      expect(
        fleetSignalOf(trackingSince: ago(3), now: now),
        FleetSignal.awaiting,
      );
      expect(
        fleetSignalOf(trackingSince: ago(30), now: now),
        FleetSignal.noSignal,
      );
      // Old server: nothing to judge by, so the trip is not hidden.
      expect(fleetSignalOf(now: now), FleetSignal.awaiting);
    });
  });

  group('FleetVehicle.fromJson', () {
    test('reads the server signal and region', () {
      final f = FleetVehicle.fromJson({
        'lr_id': 'a',
        'lr_number': 'LR/PUN/26-27/01278',
        'signal': 'no_signal',
        'region_code': 'sbn',
      });
      expect(f.signal, FleetSignal.noSignal);
      expect(f.regionCode, 'SBN');
    });

    test('older server: region from the LR number, signal from the fix', () {
      final f = FleetVehicle.fromJson({
        'lr_id': 'a',
        'lr_number': 'LR/pun/26-27/01278',
        'location': {
          'lat': 1,
          'lng': 2,
          'recorded_at': DateTime.now()
              .subtract(const Duration(days: 37))
              .toUtc()
              .toIso8601String(),
        },
      });
      expect(f.regionCode, 'PUN');
      expect(f.signal, FleetSignal.noSignal);
    });
  });

  group('filterFleet', () {
    final all = [
      v('L1', fixAt: ago(5)),
      v('L2', fixAt: ago(1)),
      v('L3', signal: FleetSignal.awaiting, consent: 'PENDING'),
      v('L4', signal: FleetSignal.noSignal, fixAt: ago(39 * 24)),
      v('L5', fixAt: ago(1), state: 'ENDED'),
      v('L6', fixAt: ago(3), region: 'SBN', driver: 'Ramesh'),
    ];
    List<String> ids(FleetFilter f) =>
        filterFleet(all, f).map((x) => x.lrNumber).toList();

    test('defaults to live trips, newest fix first, never ended ones', () {
      expect(ids(const FleetFilter()), ['L2', 'L6', 'L1', 'L3']);
    });

    test('scopes', () {
      expect(ids(const FleetFilter(scope: FleetScope.noSignal)), ['L4']);
      expect(ids(const FleetFilter(scope: FleetScope.consentPending)), ['L3']);
      expect(ids(const FleetFilter(scope: FleetScope.all)), [
        'L2',
        'L6',
        'L1',
        'L4',
        'L3',
      ]);
    });

    test('region and search', () {
      expect(ids(const FleetFilter(region: 'SBN')), ['L6']);
      expect(ids(const FleetFilter(query: 'rames')), ['L6']);
    });

    test('counts per scope within a region', () {
      final c = fleetScopeCounts(all, null);
      expect(c[FleetScope.live], 4);
      expect(c[FleetScope.noSignal], 1);
      expect(c[FleetScope.consentPending], 1);
      expect(c[FleetScope.all], 5);
      expect(fleetScopeCounts(all, 'SBN')[FleetScope.all], 1);
      expect(fleetRegions(all), ['PUN', 'SBN']);
    });
  });

  test('staleFor says how long', () {
    expect(
      staleFor(
        v('L4', signal: FleetSignal.noSignal, fixAt: ago(39 * 24)),
        now: now,
      ),
      'No signal for 39 days',
    );
  });
}
