// The Route picker lists many rows with the SAME "From → To" — the same
// origin-destination pair exists once per vehicle type and capacity, because
// each is a separately negotiated rate. specLine is what tells them apart, and
// the picker searches it as well as showing it, so "12 MT" is a usable query.
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/shared/models/route_master.dart';

RouteMaster _route({
  double distanceKm = 0,
  String? vehicleTypeLabel,
  String? capacityLabel,
}) => RouteMaster(
  id: 'r1',
  fromCity: 'PUNE',
  toCity: 'NARSAPURA',
  distanceKm: distanceKm,
  baseRate: 0,
  vehicleTypeLabel: vehicleTypeLabel,
  capacityLabel: capacityLabel,
);

void main() {
  test('all three parts read distance, then vehicle type, then capacity', () {
    expect(
      _route(
        distanceKm: 128,
        vehicleTypeLabel: 'Pick Up',
        capacityLabel: '12 MT',
      ).specLine,
      '128 km · Pick Up · 12 MT',
    );
  });

  test('distance prints as whole kilometres', () {
    expect(_route(distanceKm: 128.4).specLine, '128 km');
    expect(_route(distanceKm: 1.6).specLine, '2 km');
  });

  test('missing parts are dropped, not printed blank', () {
    expect(_route(distanceKm: 128).specLine, '128 km');
    expect(_route(vehicleTypeLabel: '407').specLine, '407');
    expect(_route(capacityLabel: '12 MT').specLine, '12 MT');
    expect(
      _route(distanceKm: 128, capacityLabel: '12 MT').specLine,
      '128 km · 12 MT',
    );
  });

  test('a zero distance is treated as unset rather than printed as 0 km', () {
    // distance_km is nullable server-side and lands here as 0.0, which is not a
    // real distance — printing "0 km" would read as a measured value.
    expect(_route(distanceKm: 0, capacityLabel: '12 MT').specLine, '12 MT');
  });

  test('whitespace-only labels count as absent', () {
    expect(
      _route(
        distanceKm: 128,
        vehicleTypeLabel: '   ',
        capacityLabel: '',
      ).specLine,
      '128 km',
    );
  });

  test('a route with nothing to say yields an empty line', () {
    // The picker reads '' as "no subtitle" and renders no second line at all,
    // so a bare route tile stays the same height as its neighbours.
    expect(_route().specLine, '');
  });
}
