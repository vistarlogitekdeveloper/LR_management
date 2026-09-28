// Covers the four states of the tracking History tab (loading / error / empty /
// content) plus the search → empty → clear-filters round trip.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/tracking/providers/tracking_providers.dart';
import 'package:lr_management/features/tracking/widgets/tracking_common.dart';
import 'package:lr_management/features/tracking/widgets/trip_history_view.dart';
import 'package:lr_management/shared/models/consignee.dart';
import 'package:lr_management/shared/models/consignor.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/models/transporter.dart';
import 'package:lr_management/shared/models/vehicle.dart';
import 'package:lr_management/shared/widgets/loading_shimmer.dart';

LorryReceipt _lr({
  required String id,
  required String number,
  required String truck,
  LrStatus status = LrStatus.delivered,
}) => LorryReceipt(
  id: id,
  number: number,
  date: DateTime(2026, 9, 10),
  enteredBy: 'u1',
  consignor: const Consignor(
    id: 'c1',
    name: 'RAPL',
    gst: '',
    city: '',
    address: '',
    contact: '',
    mobile: '',
    email: '',
  ),
  consignee: const Consignee(
    id: 'c2',
    name: 'SMVL',
    gst: '',
    location: '',
    address: '',
    contact: '',
    mobile: '',
  ),
  vehicle: Vehicle(id: 'v1', number: truck, driver: 'SALMAN'),
  transporter: const Transporter(id: 't1', name: '', pan: '', tds: 'No'),
  route: 'CHAKAN → DEWAS',
  fromCity: 'CHAKAN',
  toCity: 'DEWAS',
  items: const [],
  freight: const FreightDetails(),
  payType: PayType.tbb,
  deliveryType: DeliveryType.doorDelivery,
  status: status,
);

/// Pumps the History tab with the LR source stubbed out. [source] returns the
/// rows, throws for the error case, or never completes for the loading case.
Future<void> _pump(
  WidgetTester tester,
  Future<List<LorryReceipt>> Function() source,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripHistorySourceProvider.overrideWith((ref) => source()),
        activeVehiclesProvider.overrideWith((ref) async => []),
      ],
      child: const MaterialApp(home: Scaffold(body: TripHistoryView())),
    ),
  );
}

void main() {
  testWidgets('shows a skeleton while the first load is in flight', (
    tester,
  ) async {
    await _pump(tester, () => Completer<List<LorryReceipt>>().future);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShimmerCards), findsOneWidget);
  });

  testWidgets('shows a retryable error, not an empty list, on failure', (
    tester,
  ) async {
    await _pump(tester, () => Future.error(Exception('offline')));
    await tester.pumpAndSettle();

    expect(find.byType(TrackingErrorBox), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No finished trips yet'), findsNothing);
  });

  testWidgets('shows the designed empty state when nothing has finished', (
    tester,
  ) async {
    await _pump(tester, () async => []);
    await tester.pumpAndSettle();

    expect(find.text('No finished trips yet'), findsOneWidget);
  });

  testWidgets('lists finished trips with their outcome and count', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => [
        _lr(id: '1', number: 'LR/PUN/26-27/00902', truck: 'MH18BG5730'),
        _lr(
          id: '2',
          number: 'LR/SBN/26-27/01590',
          truck: 'MH20GC7189',
          status: LrStatus.cancelled,
        ),
        // Still running — belongs on the Active tab, never here.
        _lr(
          id: '3',
          number: 'LR/PUN/26-27/00831',
          truck: 'MP09ZY0323',
          status: LrStatus.inTransit,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('LR/PUN/26-27/00902'), findsOneWidget);
    expect(find.text('LR/SBN/26-27/01590'), findsOneWidget);
    expect(find.text('LR/PUN/26-27/00831'), findsNothing);
    expect(find.text('2 finished trips'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('search narrows the list, and Clear filters restores it', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => [
        _lr(id: '1', number: 'LR/PUN/26-27/00902', truck: 'MH18BG5730'),
        _lr(id: '2', number: 'LR/SBN/26-27/01590', truck: 'MH20GC7189'),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'MH20GC');
    await tester.pumpAndSettle();
    expect(find.text('LR/SBN/26-27/01590'), findsOneWidget);
    expect(find.text('LR/PUN/26-27/00902'), findsNothing);

    // A query that matches nothing must read as "no match", not "none yet".
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No trips match these filters'), findsOneWidget);
    expect(find.text('No finished trips yet'), findsNothing);

    await tester.tap(find.text('Clear filters').first);
    await tester.pumpAndSettle();
    expect(find.text('LR/PUN/26-27/00902'), findsOneWidget);
    expect(find.text('LR/SBN/26-27/01590'), findsOneWidget);
    // The reset also has to reach the search box it did not come from.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });
}
