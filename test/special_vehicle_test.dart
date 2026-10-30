// Special vehicles and the tracking improvements (2026-10-30, backend
// migration 254): the flag on the LR, the fleet "Special vehicles" scope,
// halts alerted from 1 h for them, signal freshness tiers, the ETA, the halt
// timeline, the Create LR switch and the print band.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/lr/widgets/lr_slip_pdf.dart';
import 'package:lr_management/features/lr/widgets/special_vehicle_toggle.dart';
import 'package:lr_management/features/tracking/data/fleet_filter.dart';
import 'package:lr_management/features/tracking/data/signal_freshness.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';
import 'package:lr_management/features/tracking/data/trip_eta.dart';
import 'package:lr_management/features/tracking/widgets/halt_timeline.dart';
import 'package:lr_management/shared/models/lr_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> halt({
    double hours = 1.2,
    double alertHours = 1,
    bool alerted = true,
  }) => {
    'id': 'h1',
    'started_at': '2026-10-30T04:30:00.000Z',
    'ended_at': null,
    'ongoing': true,
    'hours': hours,
    'lat': 18.75,
    'lng': 73.86,
    'city': 'Chakan',
    'address': 'MIDC Phase 2',
    'alerted': alerted,
    'alerted_at': alerted ? '2026-10-30T05:40:00.000Z' : null,
    'alert_hours': alertHours,
  };

  test('the LR reads the special flag; single LRs are not special', () {
    expect(
      LorryReceipt.fromJson({
        'id': 'l',
        'number': 'X',
        'is_special_vehicle': true,
      }).isSpecialVehicle,
      isTrue,
    );
    expect(
      LorryReceipt.fromJson({'id': 'l', 'number': 'X'}).isSpecialVehicle,
      isFalse,
    );
  });

  test('a special vehicle halt is alerted from its own 1 h limit', () {
    final h = TripHalt.fromJson(halt());
    expect(h.alertHours, 1);
    expect(h.overAlertLimit, isTrue);
    expect(h.durationLabel, '1 h 12 m');
    expect(
      TripHalt.fromJson(halt(hours: 0.75, alerted: false)).durationLabel,
      '45 m',
    );
    // An older server sends no alert_hours: the 5 h default.
    final old = TripHalt.fromJson(
      {...halt(hours: 3, alerted: false)}..remove('alert_hours'),
    );
    expect(old.overAlertLimit, isFalse);
  });

  test(
    'fleet: a Special vehicles scope, and halted counts the 1 h special halt',
    () {
      FleetVehicle v(
        String id, {
        bool special = false,
        Map<String, dynamic>? h,
      }) => FleetVehicle.fromJson({
        'lr_id': id,
        'lr_number': 'LR/PUN/26-27/$id',
        'signal': 'live',
        'is_special_vehicle': special,
        'halt': h,
      });
      final all = [
        v('1', special: true, h: halt()),
        v('2'),
        v('3', special: true),
      ];
      final counts = fleetScopeCounts(all, null);
      expect(counts[FleetScope.special], 2);
      expect(counts[FleetScope.halted], 1);
      expect(
        filterFleet(
          all,
          const FleetFilter(scope: FleetScope.special),
        ).map((x) => x.lrId),
        ['1', '3'],
      );
      expect(FleetScope.special.label, 'Special vehicles');
    },
  );

  test('signal freshness tiers', () {
    final now = DateTime(2026, 10, 30, 12);
    expect(
      freshnessOf(now.subtract(const Duration(minutes: 30)), now: now),
      Freshness.live,
    );
    expect(
      freshnessOf(now.subtract(const Duration(hours: 3)), now: now),
      Freshness.delayed,
    );
    expect(
      freshnessOf(now.subtract(const Duration(hours: 10)), now: now),
      Freshness.lost,
    );
    expect(
      freshnessOf(now.subtract(const Duration(days: 2)), now: now),
      Freshness.noSignal,
    );
    expect(freshnessOf(null, now: now), Freshness.awaiting);
  });

  test('ETA reads, and says when the trip is late', () {
    final eta = TripEta.fromJson({
      'eta_at': '2026-10-30T13:00:00.000Z',
      'remaining_km': 120.5,
      'remaining_min': 140,
      'planned_arrival_at': '2026-10-30T09:00:00.000Z',
      'late_by_min': 180,
    })!;
    expect(eta.late, isTrue);
    expect(minutesLabel(eta.lateByMin), '3 h');
    expect(minutesLabel(140), '2 h 20 m');
    expect(TripEta.fromJson(null), isNull);
    expect(TripEta.fromJson({'eta_at': null}), isNull);
  });

  testWidgets('the halt timeline: numbered, start → now, place, alerted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HaltTimeline(
              halts: [TripHalt.fromJson(halt())],
              recordedFrom: '1 h',
            ),
          ),
        ),
      ),
    );
    expect(find.text('H1'), findsOneWidget);
    expect(find.text('STANDING NOW'), findsOneWidget);
    expect(find.text('ALERTED'), findsOneWidget);
    expect(find.textContaining('Chakan — MIDC Phase 2'), findsOneWidget);
    expect(find.textContaining('→  now'), findsOneWidget);
    expect(find.textContaining('1 halt'), findsOneWidget);
  });

  testWidgets('the Create LR switch turns special on and off', (tester) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, set) => SpecialVehicleToggle(
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('special-vehicle')));
    await tester.pump();
    expect(value, isTrue);
    await tester.tap(find.text('Special vehicle'));
    await tester.pump();
    expect(value, isFalse);
  });

  test('the print of a special vehicle LR builds', () async {
    final lr = LorryReceipt.fromJson({
      'id': 'lr1',
      'number': 'LR/PUN/26-27/00042',
      'lr_date': '2026-10-30',
      'is_special_vehicle': true,
    });
    final bytes = await buildLrSlipPdf(
      lr: lr,
      company: const LrSlipCompany(
        name: 'Vistar',
        tagline: '',
        address: '',
        gstin: '',
      ),
    );
    expect(bytes.length, greaterThan(1000));
  });
}
