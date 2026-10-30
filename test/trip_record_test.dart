// The History tab reads finished trips from the server (GET /tracking/history,
// 2026-10-30) with their halts / driver changes / fixes, and the fleet list
// shows an estimated ETA with a "Running late" scope.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/tracking/data/fleet_filter.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';
import 'package:lr_management/features/tracking/data/trip_record.dart';
import 'package:lr_management/features/tracking/providers/tracking_providers.dart';
import 'package:lr_management/features/tracking/widgets/trip_history_view.dart';
import 'package:lr_management/shared/models/lr_models.dart';

Map<String, dynamic> _row({
  String id = 'lr1',
  String number = 'LR/PUN/26-27/00042',
  String outcome = 'DELIVERED',
  bool special = true,
  int halts = 2,
}) => {
  'lr_id': id,
  'lr_number': number,
  'lr_date': '2026-10-28',
  'outcome': outcome,
  'is_special_vehicle': special,
  'truck_number': 'MH12AB1234',
  'driver_name': 'RAJU',
  'from_city': 'Pune',
  'to_city': 'Chakan',
  'consignor_name': 'BAJAJ',
  'started_at': '2026-10-28T04:00:00Z',
  'ended_at': '2026-10-29T10:00:00Z',
  'trip_hours': 30,
  'route_km': '245.5',
  'halts': halts,
  'halt_hours': 3.3,
  'longest_halt_hours': 2.5,
  'halt_alerted': true,
  'driver_changes': 1,
  'fixes': 88,
  'tracked': true,
};

void main() {
  test('a server trip reads its outcome and numbers', () {
    final t = TripRecord.fromJson(_row(outcome: 'CANCELLED'));
    expect(t.outcome, LrStatus.cancelled);
    expect(t.isSpecial, isTrue);
    expect(t.routeKm, 245.5);
    expect(t.halts, 2);
    expect(t.haltAlerted, isTrue);
    expect(t.driverChanges, 1);
    expect(t.hasMetrics, isTrue);
    expect(t.shownDate, t.endedAt);
  });

  test('search over server rows, and the Active-tab exclusion', () {
    final all = [
      TripRecord.fromJson(_row()),
      TripRecord.fromJson(_row(id: 'lr2', number: 'LR/PUN/26-27/00043')),
    ];
    expect(filterTripRecords(all, query: '00043').map((t) => t.lrId), ['lr2']);
    expect(filterTripRecords(all, query: 'raju').length, 2);
    expect(filterTripRecords(all, excludeLrIds: {'lr1'}).map((t) => t.lrId), [
      'lr2',
    ]);
  });

  test('fleet: an ETA estimate and the Running late scope', () {
    FleetVehicle v(String id, int lateBy) => FleetVehicle.fromJson({
      'lr_id': id,
      'lr_number': 'LR/PUN/26-27/$id',
      'signal': 'live',
      'eta': {
        'eta_at': '2026-10-30T13:00:00Z',
        'remaining_km': 80,
        'late_by_min': lateBy,
        'estimate': true,
      },
    });
    final all = [v('1', 0), v('2', 150)];
    expect(all[1].late, isTrue);
    expect(all[1].eta!.remainingKm, 80);
    expect(fleetScopeCounts(all, null)[FleetScope.late], 1);
    expect(FleetScope.late.label, 'Running late');
  });

  testWidgets('History shows the server trips with their numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripServerHistoryProvider.overrideWith(
            (ref) async => [TripRecord.fromJson(_row())],
          ),
          activeVehiclesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: Scaffold(body: TripHistoryView())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LR/PUN/26-27/00042'), findsOneWidget);
    expect(find.text('SPECIAL'), findsOneWidget);
    expect(find.textContaining('2 halts'), findsOneWidget);
    expect(find.textContaining('1 driver change'), findsOneWidget);
    expect(find.text('246 km'), findsOneWidget);
    expect(find.textContaining('Ended'), findsOneWidget);
    expect(find.text('1 finished trip'), findsOneWidget);
  });
}
