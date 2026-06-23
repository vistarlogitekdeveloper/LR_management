import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../../shared/models/consignee.dart';
import '../../../shared/models/consignor.dart';
import '../../../shared/models/driver.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/models/vehicle.dart';
import '../data/consignees_repository.dart';
import '../data/consignors_repository.dart';
import '../data/drivers_repository.dart';
import '../data/routes_repository.dart';
import '../data/transporters_repository.dart';
import '../data/vehicles_repository.dart';

// All masters are API-backed. Each notifier exposes `List<T>` so existing
// screens keep working; state is empty until refresh() resolves, and the CRUD
// methods are async — callers await them to surface errors.

class ConsignorsNotifier extends StateNotifier<List<Consignor>> {
  ConsignorsNotifier(this._repo) : super(const []) {
    refresh();
  }
  final ConsignorsRepository _repo;

  Future<void> refresh() async {
    state = await _repo.list();
  }

  Future<void> add(Consignor c) async {
    final created = await _repo.create(c);
    state = [...state, created];
  }

  Future<void> update(Consignor c) async {
    final updated = await _repo.update(c);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}

class ConsigneesNotifier extends StateNotifier<List<Consignee>> {
  ConsigneesNotifier(this._repo) : super(const []) {
    refresh();
  }
  final ConsigneesRepository _repo;

  Future<void> refresh() async {
    state = await _repo.list();
  }

  Future<void> add(Consignee c) async {
    final created = await _repo.create(c);
    state = [...state, created];
  }

  Future<void> update(Consignee c) async {
    final updated = await _repo.update(c);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}

class VehiclesNotifier extends StateNotifier<List<Vehicle>> {
  VehiclesNotifier(this._repo) : super(const []) {
    refresh();
  }
  final VehiclesRepository _repo;

  Future<void> refresh() async {
    state = await _repo.list();
  }

  Future<void> add(Vehicle v) async {
    final created = await _repo.create(v);
    state = [...state, created];
  }

  Future<void> update(Vehicle v) async {
    final updated = await _repo.update(v);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}

class TransportersNotifier extends StateNotifier<List<Transporter>> {
  TransportersNotifier(this._repo) : super(const []) {
    refresh();
  }
  final TransportersRepository _repo;

  Future<void> refresh() async {
    state = await _repo.list();
  }

  Future<void> add(Transporter t) async {
    final created = await _repo.create(t);
    state = [...state, created];
  }

  Future<void> update(Transporter t) async {
    final updated = await _repo.update(t);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}

class DriversNotifier extends StateNotifier<List<Driver>> {
  DriversNotifier(this._repo) : super(const []) {
    refresh();
  }
  final DriversRepository _repo;

  Future<void> refresh() async {
    state = await _repo.list();
  }

  Future<void> add(Driver d) async {
    final created = await _repo.create(d);
    state = [...state, created];
  }

  Future<void> update(Driver d) async {
    final updated = await _repo.update(d);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}

class RoutesNotifier extends StateNotifier<List<RouteMaster>> {
  RoutesNotifier(this._repo) : super(const []) {
    refresh();
  }
  final RoutesRepository _repo;

  Future<void> refresh() async {
    state = await _repo.list();
  }

  Future<void> add(RouteMaster r) async {
    final created = await _repo.create(r);
    state = [...state, created];
  }

  Future<void> update(RouteMaster r) async {
    final updated = await _repo.update(r);
    state = [for (final x in state) x.id == updated.id ? updated : x];
  }

  Future<void> remove(String id) async {
    await _repo.remove(id);
    state = state.where((x) => x.id != id).toList();
  }
}

// ---- Repository providers ----
final consignorsRepositoryProvider = Provider<ConsignorsRepository>(
    (ref) => ConsignorsRepository(ref.watch(apiClientProvider)));
final consigneesRepositoryProvider = Provider<ConsigneesRepository>(
    (ref) => ConsigneesRepository(ref.watch(apiClientProvider)));
final vehiclesRepositoryProvider = Provider<VehiclesRepository>(
    (ref) => VehiclesRepository(ref.watch(apiClientProvider)));
final transportersRepositoryProvider = Provider<TransportersRepository>(
    (ref) => TransportersRepository(ref.watch(apiClientProvider)));
final driversRepositoryProvider = Provider<DriversRepository>(
    (ref) => DriversRepository(ref.watch(apiClientProvider)));
final routesRepositoryProvider = Provider<RoutesRepository>(
    (ref) => RoutesRepository(ref.watch(apiClientProvider)));

// ---- State notifier providers ----
final consignorsProvider =
    StateNotifierProvider<ConsignorsNotifier, List<Consignor>>(
        (ref) => ConsignorsNotifier(ref.watch(consignorsRepositoryProvider)));

final consigneesProvider =
    StateNotifierProvider<ConsigneesNotifier, List<Consignee>>(
        (ref) => ConsigneesNotifier(ref.watch(consigneesRepositoryProvider)));

final vehiclesProvider =
    StateNotifierProvider<VehiclesNotifier, List<Vehicle>>(
        (ref) => VehiclesNotifier(ref.watch(vehiclesRepositoryProvider)));

final transportersProvider =
    StateNotifierProvider<TransportersNotifier, List<Transporter>>(
        (ref) => TransportersNotifier(ref.watch(transportersRepositoryProvider)));

final driversProvider = StateNotifierProvider<DriversNotifier, List<Driver>>(
    (ref) => DriversNotifier(ref.watch(driversRepositoryProvider)));

final routesProvider =
    StateNotifierProvider<RoutesNotifier, List<RouteMaster>>(
        (ref) => RoutesNotifier(ref.watch(routesRepositoryProvider)));
