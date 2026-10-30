import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pills.dart';
import '../data/tracking_repository.dart';
import '../data/signal_freshness.dart';
import 'halt_widgets.dart';
import 'tracking_common.dart';

/// Fleet map + the side list of every actively-tracked vehicle. Tapping either
/// a marker or a tile opens that vehicle's trail at /tracking/lr/:id.
class FleetView extends StatelessWidget {
  static const _india = LatLng(22.9734, 78.6569);

  final List<FleetVehicle> vehicles;

  /// What the list shows when [vehicles] is empty (a default otherwise).
  final Widget? empty;
  const FleetView({super.key, required this.vehicles, this.empty});

  @override
  Widget build(BuildContext context) {
    final located = vehicles.where((v) => v.location != null).toList();
    final points = located
        .map((v) => LatLng(v.location!.lat, v.location!.lng))
        .toList();

    final map = RepaintBoundary(
      child: _FleetMap(vehicles: located, points: points, india: _india),
    );
    final list = _FleetList(vehicles: vehicles, empty: empty);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return Row(
            children: [
              Expanded(child: map),
              Container(width: 1, color: AppColors.line),
              SizedBox(width: 340, child: list),
            ],
          );
        }
        return Column(
          children: [
            Expanded(flex: 3, child: map),
            Container(height: 1, color: AppColors.line),
            Expanded(flex: 2, child: list),
          ],
        );
      },
    );
  }
}

class _FleetMap extends StatelessWidget {
  final List<FleetVehicle> vehicles; // only ones with a location
  final List<LatLng> points;
  final LatLng india;
  const _FleetMap({
    required this.vehicles,
    required this.points,
    required this.india,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: points.isNotEmpty ? points.first : india,
            initialZoom: points.isEmpty ? 5 : 7,
            initialCameraFit: points.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(48),
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.vistar.lr_management',
              // A tile that fails (dropped network, OSM throttling) shows as blank
              // instead of throwing: one scrolled off-screen while still loading has no
              // listener left, and its error reached telemetry as an app crash.
              tileProvider: NetworkTileProvider(silenceExceptions: true),
            ),
            MarkerLayer(
              markers: [
                for (final v in vehicles)
                  Marker(
                    point: LatLng(v.location!.lat, v.location!.lng),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => context.go('/tracking/lr/${v.lrId}'),
                      child: Tooltip(
                        message: [
                          '${v.isSpecial ? '★ SPECIAL · ' : ''}${v.lrNumber}${v.truckNumber != null ? ' · ${v.truckNumber}' : ''}',
                          if (v.location?.city != null) v.location!.city!,
                          if (v.location?.at != null)
                            'Last fix ${relTime(v.location!.at)}',
                          if (v.halt != null && v.halt!.ongoing)
                            haltSummary(v.halt!),
                        ].join('\n'),
                        child: _TruckPin(
                          consent: v.consentStatus,
                          freshness: freshnessOf(v.location?.at),
                          halted: v.haltAlert,
                          special: v.isSpecial,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const Positioned(
          bottom: 2,
          right: 2,
          child: ColoredBox(
            color: Color(0xCCFFFFFF),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: AppColors.slate),
              ),
            ),
          ),
        ),
        if (points.isEmpty)
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: TrackingPill('No location fixes yet')),
          ),
      ],
    );
  }
}

class _TruckPin extends StatelessWidget {
  final String? consent;

  /// How old the last fix is: live plum, delayed amber, lost orange, a day+
  /// grey — not drawn as a moving truck.
  final Freshness freshness;

  /// Halted past its alert limit: drawn red, so it stands out.
  final bool halted;

  /// A special vehicle: a star badge on the pin.
  final bool special;
  const _TruckPin({
    this.consent,
    this.freshness = Freshness.live,
    this.halted = false,
    this.special = false,
  });

  @override
  Widget build(BuildContext context) {
    // Ring colour reflects consent so the fleet map reads at a glance: green =
    // consent granted (fixes flow), red = refused, amber = pending / unknown.
    // (It used to go green for anything containing "ALLOW", NOT_ALLOWED too.)
    final ring = switch (consentKind(consent)) {
      ConsentKind.granted => AppColors.ok,
      ConsentKind.refused => AppColors.danger,
      ConsentKind.pending || ConsentKind.unknown => AppColors.warn,
    };
    final fill = halted
        ? AppColors.danger
        : switch (freshness) {
            Freshness.live || Freshness.awaiting => AppColors.plum,
            Freshness.delayed => AppColors.warn,
            Freshness.lost => AppColors.orange,
            Freshness.noSignal => AppColors.slate,
          };
    final pin = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.local_shipping_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
    if (!special) return pin;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        pin,
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: const BoxDecoration(
              color: SpecialVehiclePill.color,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _FleetList extends StatelessWidget {
  final List<FleetVehicle> vehicles;
  final Widget? empty;
  const _FleetList({required this.vehicles, this.empty});

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      return empty ??
          const TrackingEmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No vehicles on the road',
            message:
                'Tracking starts when an LR is created for a driver whose SIM '
                'consent is approved. Finished trips are on the History tab.',
          );
    }
    // Located vehicles first, then the rest (awaiting first fix / consent).
    // A stable sort, so the newest-fix-first order filterFleet gave survives.
    final sorted = [
      ...vehicles.where((v) => v.location != null),
      ...vehicles.where((v) => v.location == null),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _VehicleTile(v: sorted[i]),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  final FleetVehicle v;
  const _VehicleTile({required this.v});

  @override
  Widget build(BuildContext context) {
    final loc = v.location;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/tracking/lr/${v.lrId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      v.lrNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (v.isSpecial) ...[
                    const SpecialVehiclePill(compact: true),
                    const SizedBox(width: 6),
                  ],
                  ConsentBadge(status: v.consentStatus),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (v.truckNumber != null && v.truckNumber!.isNotEmpty)
                    v.truckNumber,
                  if (v.driverName != null && v.driverName!.isNotEmpty)
                    v.driverName,
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.slate),
                overflow: TextOverflow.ellipsis,
              ),
              if ((v.fromCity ?? '').isNotEmpty || (v.toCity ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${v.fromCity ?? '?'} → ${v.toCity ?? '?'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.slate,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    loc != null
                        ? Icons.place_rounded
                        : Icons.location_disabled_rounded,
                    size: 13,
                    color: loc != null ? AppColors.plum : AppColors.slate,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      loc != null
                          ? '${loc.city ?? 'Located'} · ${relTime(loc.at)}'
                          : 'Awaiting first fix',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.slate,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (loc != null) FreshnessTag(freshnessOf(loc.at)),
                ],
              ),
              if (v.signal == FleetSignal.noSignal)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${staleFor(v)} — mark the LR Delivered to stop '
                    'tracking.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              if (v.halt != null && v.halt!.ongoing)
                HaltLine(lrId: v.lrId, halt: v.halt!),
            ],
          ),
        ),
      ),
    );
  }
}

/// "No signal for 39 days" / "No location for 2 days" — from the last fix, else
/// from when tracking began.
String staleFor(FleetVehicle v, {DateTime? now}) {
  final since = v.location?.at ?? v.trackingSince;
  final what = v.location != null ? 'No signal' : 'No location';
  if (since == null) return '$what for over a day';
  final d = (now ?? DateTime.now()).difference(since);
  final days = d.inDays;
  return days >= 1
      ? '$what for $days day${days == 1 ? '' : 's'}'
      : '$what for ${d.inHours} h';
}
