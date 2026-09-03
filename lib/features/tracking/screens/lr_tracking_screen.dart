import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../shell/widgets/app_topbar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../data/route_planner.dart';
import '../data/tracking_repository.dart';
import '../providers/tracking_providers.dart';
import 'live_tracking_screen.dart' show ConsentBadge, relTime;

/// Individual LR trail + SIM consent controls.
class LrTrackingScreen extends ConsumerStatefulWidget {
  final String id;
  const LrTrackingScreen({super.key, required this.id});

  @override
  ConsumerState<LrTrackingScreen> createState() => _LrTrackingScreenState();
}

class _LrTrackingScreenState extends ConsumerState<LrTrackingScreen> {
  bool _rechecking = false;
  bool _starting = false;
  bool _sharing = false;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    // SIM fixes land only every ~15-20 min, so poll the backend on a gentle
    // cadence — each load re-ingests the latest fix from SCT — so the map keeps
    // itself current without the user pressing Refresh.
    _autoRefresh = Timer.periodic(const Duration(seconds: 90), (_) {
      if (mounted) ref.invalidate(lrTrackingProvider(widget.id));
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _recheck() async {
    setState(() => _rechecking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ref
          .read(trackingRepositoryProvider)
          .recheckConsent(widget.id);
      ref.invalidate(lrTrackingProvider(widget.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Consent: ${r.status ?? 'unknown'}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Recheck failed: $e')));
    } finally {
      if (mounted) setState(() => _rechecking = false);
    }
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(trackingRepositoryProvider).startTracking(widget.id);
      ref.invalidate(lrTrackingProvider(widget.id));
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Tracking started — location appears as the driver pings in.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not start tracking: $e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Reuse the link the backend already cached (returned on /route) when we
      // have it; otherwise ask the backend to generate one now.
      final cached = ref
          .read(lrTrackingProvider(widget.id))
          .asData
          ?.value
          .publicLink;
      final link = (cached != null && cached.isNotEmpty)
          ? cached
          : await ref.read(trackingRepositoryProvider).publicLink(widget.id);
      if (link.isEmpty) throw 'No link returned';
      if (!mounted) return;
      await _showShareDialog(link);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create link: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _showShareDialog(String link) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Live tracking link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anyone with this link can watch the truck live — no login needed. '
              'Share it with the customer or consignee.',
              style: TextStyle(fontSize: 13, color: AppColors.slate),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: SelectableText(
                link,
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Link copied')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lrTrackingProvider(widget.id));
    // Reloading in the background (auto-refresh / manual) while data is shown.
    final refreshing = async.isLoading && async.hasValue;
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Track LR',
            subtitle: async.asData?.value.lrNumber,
            actions: [
              if (refreshing)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Updating…',
                        style: TextStyle(fontSize: 12, color: AppColors.slate),
                      ),
                    ],
                  ),
                ),
              AppButton(
                label: 'All vehicles',
                icon: Icons.arrow_back_rounded,
                kind: BtnKind.ghost,
                small: true,
                onPressed: () => context.go('/tracking'),
              ),
              AppButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                kind: BtnKind.ghost,
                small: true,
                onPressed: () => ref.invalidate(lrTrackingProvider(widget.id)),
              ),
            ],
          ),
          Expanded(
            // Keep the map/panel on screen during background reloads instead of
            // flashing a spinner (fixes only change every ~15-20 min).
            child: async.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load tracking.\n$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate),
                ),
              ),
              data: (t) => _Body(
                t: t,
                rechecking: _rechecking,
                onRecheck: _recheck,
                starting: _starting,
                onStart: _start,
                sharing: _sharing,
                onShare: _share,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final LrTracking t;
  final bool rechecking;
  final VoidCallback onRecheck;
  final bool starting;
  final VoidCallback onStart;
  final bool sharing;
  final VoidCallback onShare;
  const _Body({
    required this.t,
    required this.rechecking,
    required this.onRecheck,
    required this.starting,
    required this.onStart,
    required this.sharing,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final map = _TrailMap(t: t);
    final panel = _Panel(
      t: t,
      rechecking: rechecking,
      onRecheck: onRecheck,
      starting: starting,
      onStart: onStart,
      sharing: sharing,
      onShare: onShare,
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return Row(
            children: [
              Expanded(child: map),
              Container(width: 1, color: AppColors.line),
              SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: panel,
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: 320, child: map),
              Padding(padding: const EdgeInsets.all(14), child: panel),
            ],
          ),
        );
      },
    );
  }
}

class _TrailMap extends StatelessWidget {
  final LrTracking t;
  const _TrailMap({required this.t});

  static const routeBlue = Color(0xFF2563EB);

  // A coordinate is usable only if it's a real WGS-84 lat/lng and not the
  // null-island (0,0). Bad route masters can store out-of-range values (e.g.
  // projected metres); those must never reach flutter_map or it asserts.
  static bool _inRange(double lat, double lng) =>
      lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);

  static LatLng? _coord(double? a, double? b) =>
      (a != null && b != null && _inRange(a, b)) ? LatLng(a, b) : null;

  // Hover label for the truck: reg number, the reverse-geocoded place name of
  // the latest fix (city, else address, else coords), and how long ago it was.
  static String _truckLabel(TrackPoint? p, LrTracking t) {
    final truck = (t.truckNumber ?? '').isNotEmpty ? t.truckNumber! : 'Vehicle';
    if (p == null) return truck;
    final where = (p.city != null && p.city!.isNotEmpty)
        ? p.city!
        : ((p.address != null && p.address!.isNotEmpty)
              ? p.address!
              : '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}');
    return '$truck\n$where\n${relTime(p.at)}';
  }

  @override
  Widget build(BuildContext context) {
    const india = LatLng(22.9734, 78.6569);

    final history = t.history
        .where((p) => _inRange(p.lat, p.lng))
        .map((p) => LatLng(p.lat, p.lng))
        .toList();
    final src = _coord(t.fromLat, t.fromLng);
    final dest = _coord(t.toLat, t.toLng);

    // Fastest + shortest road routes, computed server-side and delivered in the
    // tracking response (no browser routing dependency).
    final options = t.routeOptions;
    RouteOption? fastestOpt;
    RouteOption? shortestOpt;
    for (final o in options) {
      if (o.kind == 'fastest') fastestOpt = o;
      if (o.kind == 'shortest') shortestOpt = o;
    }
    final fastest = fastestOpt;
    final shortest = shortestOpt;
    // Remaining road route from the truck's current position → destination.
    final remaining = t.remainingRoute;

    // Fallback: a straight origin→destination line only when no road route
    // options came back (e.g. OSRM unreachable).
    List<LatLng> planned = const [];
    if (options.isEmpty && src != null && dest != null) planned = [src, dest];

    // The latest fix (for both the truck marker position and its hover label).
    final curFix =
        (t.current != null && _inRange(t.current!.lat, t.current!.lng))
        ? t.current
        : (t.history.isNotEmpty ? t.history.last : null);
    final cur = (curFix != null && _inRange(curFix.lat, curFix.lng))
        ? LatLng(curFix.lat, curFix.lng)
        : null;

    final all = <LatLng>[
      ...planned,
      for (final o in options) ...o.points,
      if (remaining != null) ...remaining.points,
      ...history,
      ?src,
      ?dest,
      ?cur,
    ];
    final hasAny = all.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: cur ?? (hasAny ? all.first : india),
            initialZoom: hasAny ? 9 : 5,
            initialCameraFit: all.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(all),
                    padding: const EdgeInsets.all(48),
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.vistar.lr_management',
            ),
            // Direct line only when no road route is available — dashed blue so
            // it reads clearly as an approximation, not an actual road.
            if (planned.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: planned,
                    strokeWidth: 4,
                    color: routeBlue.withValues(alpha: 0.7),
                    pattern: StrokePattern.dashed(segments: const [12, 8]),
                  ),
                ],
              ),
            // Shortest route (amber) — drawn under the fastest, white casing.
            if (shortest != null && !identical(shortest, fastest))
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: shortest.points,
                    strokeWidth: 6,
                    color: AppColors.orange,
                    borderStrokeWidth: 3,
                    borderColor: Colors.white,
                  ),
                ],
              ),
            // Fastest route (blue) with white casing for contrast on the map.
            if (fastest != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: fastest.points,
                    strokeWidth: 6,
                    color: routeBlue,
                    borderStrokeWidth: 3,
                    borderColor: Colors.white,
                  ),
                ],
              ),
            // Remaining route from the truck to the destination — green, above
            // the planned routes so it stands out as "the way still to go".
            if (remaining != null && remaining.points.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: remaining.points,
                    strokeWidth: 5,
                    color: AppColors.ok,
                    borderStrokeWidth: 3,
                    borderColor: Colors.white,
                  ),
                ],
              ),
            // Actual traveled trail — solid plum, on top of the planned routes.
            if (history.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: history,
                    strokeWidth: 5,
                    color: AppColors.plum,
                    borderStrokeWidth: 2,
                    borderColor: Colors.white,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (src != null)
                  Marker(
                    point: src,
                    width: 30,
                    height: 30,
                    child: const _DotPin(color: AppColors.ok, label: 'S'),
                  ),
                if (dest != null)
                  Marker(
                    point: dest,
                    width: 30,
                    height: 30,
                    child: const _DotPin(color: AppColors.red, label: 'D'),
                  ),
                if (cur != null)
                  Marker(
                    point: cur,
                    width: 56,
                    height: 56,
                    child: Tooltip(
                      message: _truckLabel(curFix, t),
                      preferBelow: false,
                      textAlign: TextAlign.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      child: const _PulsingTruck(),
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
        if (fastest != null || remaining != null || history.length > 1)
          Positioned(
            top: 8,
            left: 8,
            child: _RouteLegend(
              fastest: fastest,
              shortest: (shortest != null && !identical(shortest, fastest))
                  ? shortest
                  : null,
              remaining: remaining,
              hasTrail: history.length > 1,
            ),
          ),
        if (!hasAny)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No location fixes yet — the first fix appears once SIM consent is approved.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.slate),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact map legend for the route options + traveled trail.
class _RouteLegend extends StatelessWidget {
  final RouteOption? fastest;
  final RouteOption? shortest;
  final RouteOption? remaining;
  final bool hasTrail;
  const _RouteLegend({
    this.fastest,
    this.shortest,
    this.remaining,
    this.hasTrail = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final f = fastest;
    final s = shortest;
    final r = remaining;
    if (f != null) {
      rows.add(
        _row(
          _TrailMap.routeBlue,
          'Fastest',
          '${f.distanceKm.toStringAsFixed(0)} km · ${f.durationMin} min',
        ),
      );
    }
    if (s != null) {
      rows.add(
        _row(
          AppColors.orange,
          'Shortest',
          '${s.distanceKm.toStringAsFixed(0)} km · ${s.durationMin} min',
        ),
      );
    }
    if (r != null) {
      rows.add(
        _row(
          AppColors.ok,
          'To destination',
          '${r.distanceKm.toStringAsFixed(0)} km · ${r.durationMin} min left',
        ),
      );
    }
    if (hasTrail) rows.add(_row(AppColors.plum, 'Traveled', 'so far'));
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _row(Color c, String label, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          detail,
          style: const TextStyle(fontSize: 11, color: AppColors.slate),
        ),
      ],
    ),
  );
}

/// The live vehicle marker: a truck badge with a soft pulsing halo so it reads
/// as "live" on the map.
class _PulsingTruck extends StatefulWidget {
  const _PulsingTruck();

  @override
  State<_PulsingTruck> createState() => _PulsingTruckState();
}

class _PulsingTruckState extends State<_PulsingTruck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value; // 0 → 1
        return Stack(
          alignment: Alignment.center,
          children: [
            // Expanding, fading halo.
            Container(
              width: 24 + v * 30,
              height: 24 + v * 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.plum.withValues(alpha: (1 - v) * 0.30),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.plum,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(
          Icons.local_shipping_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

/// Small labelled circular pin for the route's start (S) and destination (D).
class _DotPin extends StatelessWidget {
  final Color color;
  final String label;
  const _DotPin({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final LrTracking t;
  final bool rechecking;
  final VoidCallback onRecheck;
  final bool starting;
  final VoidCallback onStart;
  final bool sharing;
  final VoidCallback onShare;
  const _Panel({
    required this.t,
    required this.rechecking,
    required this.onRecheck,
    required this.starting,
    required this.onStart,
    required this.sharing,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final cur = t.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Consent card.
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: SectionTitle(
                      icon: Icons.sim_card_outlined,
                      title: 'SIM consent',
                    ),
                  ),
                  ConsentBadge(status: t.consentStatus),
                ],
              ),
              const SizedBox(height: 8),
              if ((t.consentSuggestion ?? '').isNotEmpty) ...[
                Text(
                  'Ask the driver to:',
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.consentSuggestion!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: t.consentSuggestion!),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Consent must be approved by the driver before location fixes arrive.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate),
                  ),
                ),
              // No SCT trip yet (driver assigned after the LR was created) —
              // let the user start tracking on demand.
              if (t.trackingState == null) ...[
                AppButton(
                  label: 'Start tracking',
                  icon: Icons.play_arrow_rounded,
                  kind: BtnKind.primary,
                  small: true,
                  loading: starting,
                  onPressed: starting ? null : onStart,
                ),
                const SizedBox(height: 8),
              ],
              AppButton(
                label: 'Recheck consent',
                icon: Icons.refresh_rounded,
                kind: BtnKind.soft,
                small: true,
                loading: rechecking,
                onPressed: rechecking ? null : onRecheck,
              ),
              // Share a public live-tracking link once a trip exists, so a
              // customer/consignee can watch the truck without an app login.
              if (t.trackingState != null) ...[
                const SizedBox(height: 8),
                AppButton(
                  label: 'Share live link',
                  icon: Icons.share_rounded,
                  kind: BtnKind.soft,
                  small: true,
                  loading: sharing,
                  onPressed: sharing ? null : onShare,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Trip meta.
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                icon: Icons.info_outline_rounded,
                title: 'Details',
              ),
              const SizedBox(height: 8),
              _kv('LR', t.lrNumber ?? '—'),
              _kv('Route', '${t.fromCity ?? '?'} → ${t.toCity ?? '?'}'),
              if ((t.truckNumber ?? '').isNotEmpty)
                _kv('Vehicle', t.truckNumber!),
              if ((t.driverName ?? '').isNotEmpty) _kv('Driver', t.driverName!),
              _kv('Tracking', t.trackingState ?? '—'),
              _kv(
                'Last fix',
                cur != null ? (cur.city ?? cur.address ?? 'Located') : '—',
              ),
              if (cur != null) _freshness(cur.at),
              if (t.remainingRoute != null)
                _kv(
                  'To destination',
                  '${t.remainingRoute!.distanceKm.toStringAsFixed(0)} km · ~${t.remainingRoute!.durationMin} min',
                ),
              if (cur?.source != null)
                _kv('Source', cur!.source!.toUpperCase()),
              _kv('Fixes', '${t.history.length}'),
              const SizedBox(height: 10),
              // Set expectations: SIM fixes are periodic, not real-time GPS — so a
              // gap between updates is normal, not a stall.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 13,
                    color: AppColors.slate,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'SIM location updates about every 15–20 min. This map refreshes on its own.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.slate,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Colour-coded freshness of the latest fix so a stale position is obvious.
  Widget _freshness(DateTime? at) {
    Color c = AppColors.slate;
    String label = 'time unknown';
    if (at != null) {
      final mins = DateTime.now().difference(at).inMinutes;
      c = mins < 25
          ? AppColors.ok
          : (mins < 60 ? AppColors.warn : AppColors.slate);
      label = 'Updated ${relTime(at)}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const SizedBox(width: 74),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: c,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(
            k,
            style: const TextStyle(fontSize: 12, color: AppColors.slate),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
