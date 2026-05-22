import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/mock_data.dart';
import '../../../shared/models/consignee.dart';
import '../../../shared/models/consignor.dart';
import '../../../shared/models/driver.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/models/vehicle.dart';

class ConsignorsNotifier extends StateNotifier<List<Consignor>> {
  ConsignorsNotifier() : super(List.of(MockData.consignors));

  void add(Consignor c) => state = [...state, c];
  void update(Consignor c) =>
      state = [for (final x in state) x.id == c.id ? c : x];
  void remove(String id) => state = state.where((x) => x.id != id).toList();
}

class ConsigneesNotifier extends StateNotifier<List<Consignee>> {
  ConsigneesNotifier() : super(List.of(MockData.consignees));

  void add(Consignee c) => state = [...state, c];
  void update(Consignee c) =>
      state = [for (final x in state) x.id == c.id ? c : x];
  void remove(String id) => state = state.where((x) => x.id != id).toList();
}

class VehiclesNotifier extends StateNotifier<List<Vehicle>> {
  VehiclesNotifier() : super(List.of(MockData.vehicles));

  void add(Vehicle v) => state = [...state, v];
  void update(Vehicle v) =>
      state = [for (final x in state) x.id == v.id ? v : x];
  void remove(String id) => state = state.where((x) => x.id != id).toList();
}

class TransportersNotifier extends StateNotifier<List<Transporter>> {
  TransportersNotifier() : super(List.of(MockData.transporters));

  void add(Transporter t) => state = [...state, t];
  void update(Transporter t) =>
      state = [for (final x in state) x.id == t.id ? t : x];
  void remove(String id) => state = state.where((x) => x.id != id).toList();
}

class DriversNotifier extends StateNotifier<List<Driver>> {
  DriversNotifier() : super(List.of(MockData.drivers));

  void add(Driver d) => state = [...state, d];
  void update(Driver d) =>
      state = [for (final x in state) x.id == d.id ? d : x];
  void remove(String id) => state = state.where((x) => x.id != id).toList();
}

class RoutesNotifier extends StateNotifier<List<RouteMaster>> {
  RoutesNotifier() : super(List.of(MockData.routeMasters));

  void add(RouteMaster r) => state = [...state, r];
  void update(RouteMaster r) =>
      state = [for (final x in state) x.id == r.id ? r : x];
  void remove(String id) => state = state.where((x) => x.id != id).toList();
}

final consignorsProvider =
    StateNotifierProvider<ConsignorsNotifier, List<Consignor>>(
        (ref) => ConsignorsNotifier());

final consigneesProvider =
    StateNotifierProvider<ConsigneesNotifier, List<Consignee>>(
        (ref) => ConsigneesNotifier());

final vehiclesProvider =
    StateNotifierProvider<VehiclesNotifier, List<Vehicle>>(
        (ref) => VehiclesNotifier());

final transportersProvider =
    StateNotifierProvider<TransportersNotifier, List<Transporter>>(
        (ref) => TransportersNotifier());

final driversProvider =
    StateNotifierProvider<DriversNotifier, List<Driver>>(
        (ref) => DriversNotifier());

final routesProvider =
    StateNotifierProvider<RoutesNotifier, List<RouteMaster>>(
        (ref) => RoutesNotifier());
