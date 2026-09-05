// The Route form fills Distance (km) from the two map pins, but only when the
// field is empty — the value doubles as a commercially agreed distance next to
// the negotiated rates, so it is never overwritten silently. These tests pin
// that rule, the disabled state of the Recalculate action, and the silent
// fallback when routing is unavailable.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_providers.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/maps/data/maps_repository.dart';
import 'package:lr_management/features/masters/widgets/route_form_dialog.dart';
import 'package:lr_management/shared/models/route_master.dart';

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage() : super(const FlutterSecureStorage());
  @override
  Future<String?> readAccess() async => null;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> write({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

// `implements` (not `extends`): MapsRepository's only private member is its
// ApiClient field, which is not part of the interface outside its library, so
// there is nothing to construct here.
class _FakeMapsRepository implements MapsRepository {
  _FakeMapsRepository(this.result);

  final RoadDistance? result;
  int calls = 0;

  @override
  Future<RoadDistance?> roadDistance({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    calls++;
    return result;
  }

  @override
  Future<List<MapsSuggestion>> autocomplete(String query) async => const [];

  @override
  Future<String> reverse(double lat, double lng) async => '';
}

// A saved route with both pins set — the state in which Recalculate is live.
RouteMaster _pinnedRoute({required double distanceKm}) => RouteMaster(
  id: 'r1',
  fromCity: 'VLL - Pune',
  toCity: 'TATA - Chakan',
  distanceKm: distanceKm,
  baseRate: 12000,
  fromPlaceId: 'p1',
  fromLat: 18.5204,
  fromLng: 73.8567,
  fromAddress: 'Pune, Maharashtra, India',
  toPlaceId: 'p2',
  toLat: 18.7606,
  toLng: 73.8636,
  toAddress: 'Chakan, Maharashtra, India',
);

Future<void> _pump(
  WidgetTester tester,
  _FakeMapsRepository maps, {
  RouteMaster? existing,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
        mapsRepositoryProvider.overrideWithValue(maps),
      ],
      child: MaterialApp(
        home: Scaffold(body: RouteFormDialog(existing: existing)),
      ),
    ),
  );
  await tester.pump();
}

// The Recalculate action, identified by its icon (the header's close button is
// the form's other IconButton).
Finder get _recalculate =>
    find.widgetWithIcon(IconButton, Icons.route_outlined);

// The Distance field is the only one carrying the Recalculate icon, which is
// what identifies it without depending on the label's position.
String _distanceText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.widgetWithIcon(TextFormField, Icons.route_outlined),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  testWidgets('Recalculate is disabled on a fresh form (no pins picked)', (
    tester,
  ) async {
    final maps = _FakeMapsRepository(
      const RoadDistance(distanceKm: 128, durationMin: 185),
    );
    await _pump(tester, maps);

    expect(_recalculate, findsOneWidget);
    expect(tester.widget<IconButton>(_recalculate).onPressed, isNull);
    expect(maps.calls, 0);
  });

  testWidgets('an existing distance is never overwritten on open', (
    tester,
  ) async {
    final maps = _FakeMapsRepository(
      const RoadDistance(distanceKm: 128, durationMin: 185),
    );
    await _pump(tester, maps, existing: _pinnedRoute(distanceKm: 96));

    // Nothing is requested just by opening the form: the auto-fill runs only
    // from a pin being picked.
    expect(maps.calls, 0);
    expect(_distanceText(tester), '96');
    // Both pins are present, so the manual override is available.
    expect(tester.widget<IconButton>(_recalculate).onPressed, isNotNull);
  });

  testWidgets('routing unavailable leaves the distance untouched', (
    tester,
  ) async {
    final maps = _FakeMapsRepository(null);
    await _pump(tester, maps, existing: _pinnedRoute(distanceKm: 96));

    await tester.tap(_recalculate);
    await tester.pump(); // request in flight
    await tester.pump(); // result landed
    await tester.pump(const Duration(milliseconds: 400)); // snackbar in

    expect(maps.calls, 1);
    expect(_distanceText(tester), '96');
    expect(
      find.text(
        "Couldn't reach the routing service. Enter the distance manually.",
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recalculate overwrites the distance and reports the drive', (
    tester,
  ) async {
    final maps = _FakeMapsRepository(
      const RoadDistance(distanceKm: 128.4, durationMin: 185),
    );
    await _pump(tester, maps, existing: _pinnedRoute(distanceKm: 96));

    await tester.tap(_recalculate);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(maps.calls, 1);
    expect(_distanceText(tester), '128');
    expect(find.text('Road distance: 128 km (~3 h 5 min)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
