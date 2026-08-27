import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../shell/widgets/app_topbar.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/tracking_repository.dart';
import '../providers/tracking_providers.dart';

/// Fleet live map — every actively-tracked vehicle on one page. Tapping a
/// vehicle (marker or list tile) opens its individual trail at /tracking/lr/:id.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  static const _india = LatLng(22.9734, 78.6569);
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    // Light auto-refresh so the fleet map stays current without user action.
    _auto = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) ref.invalidate(activeVehiclesProvider);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeVehiclesProvider);
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Live Tracking',
            subtitle: 'All active vehicles',
            actions: [
              AppButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                kind: BtnKind.ghost,
                small: true,
                onPressed: () => ref.invalidate(activeVehiclesProvider),
              ),
            ],
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorBox(
                message: 'Could not load tracking.\n$e',
                onRetry: () => ref.invalidate(activeVehiclesProvider),
              ),
              data: (vehicles) => _FleetBody(vehicles: vehicles, india: _india),
            ),
          ),
        ],
      ),
    );
  }
}

class _FleetBody extends StatelessWidget {
  final List<FleetVehicle> vehicles;
  final LatLng india;
  const _FleetBody({required this.vehicles, required this.india});

  @override
  Widget build(BuildContext context) {
    final located = vehicles.where((v) => v.location != null).toList();
    final points = located
        .map((v) => LatLng(v.location!.lat, v.location!.lng))
        .toList();

    final map = _FleetMap(vehicles: located, points: points, india: india);
    final list = _FleetList(vehicles: vehicles);

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
                        message:
                            '${v.lrNumber}${v.truckNumber != null ? ' · ${v.truckNumber}' : ''}',
                        child: const _TruckPin(),
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
              child: Text('© OpenStreetMap',
                  style: TextStyle(fontSize: 9, color: AppColors.slate)),
            ),
          ),
        ),
        if (points.isEmpty)
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: _Pill('No location fixes yet')),
          ),
      ],
    );
  }
}

class _TruckPin extends StatelessWidget {
  const _TruckPin();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.plum,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
    );
  }
}

class _FleetList extends StatelessWidget {
  final List<FleetVehicle> vehicles;
  const _FleetList({required this.vehicles});

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No active tracked vehicles.\nTracking starts when an LR is created for a driver whose SIM consent is approved.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.slate),
          ),
        ),
      );
    }
    // Located vehicles first, then the rest (awaiting first fix / consent).
    final sorted = [...vehicles]..sort((a, b) {
        final al = a.location != null ? 0 : 1;
        final bl = b.location != null ? 0 : 1;
        return al.compareTo(bl);
      });
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
                    style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    loc != null ? Icons.place_rounded : Icons.location_disabled_rounded,
                    size: 13,
                    color: loc != null ? AppColors.plum : AppColors.slate,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      loc != null
                          ? '${loc.city ?? 'Located'} · ${relTime(loc.at)}'
                          : 'Awaiting first fix',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.slate),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Consent status chip, shared with the per-LR screen.
class ConsentBadge extends StatelessWidget {
  final String? status;
  const ConsentBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = (status ?? '').toUpperCase();
    late Color bg;
    late Color fg;
    late String label;
    if (s == 'ALLOWED') {
      bg = AppColors.ok.withValues(alpha: 0.14);
      fg = AppColors.ok;
      label = 'Consent OK';
    } else if (s.contains('PENDING') || s.contains('NOT')) {
      bg = AppColors.warn.withValues(alpha: 0.16);
      fg = AppColors.warn;
      label = 'Consent pending';
    } else if (s.isEmpty) {
      bg = AppColors.line;
      fg = AppColors.slate;
      label = '—';
    } else {
      bg = AppColors.danger.withValues(alpha: 0.14);
      fg = AppColors.danger;
      label = status!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

String relTime(DateTime? t) {
  if (t == null) return 'no time';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: AppColors.slate)),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.slate)),
          const SizedBox(height: 12),
          AppButton(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
        ],
      ),
    );
  }
}
