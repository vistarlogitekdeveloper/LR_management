import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../utils/maps_config.dart';
import '../utils/maps_loader.dart';

/// Which surface the picker ended up with. The dialog above needs this for two
/// things it cannot infer: whose attribution to print, and whether to explain a
/// fallback the user did not ask for.
enum PickerMapSurface { loading, google, osm }

/// Imperative handle for moving the camera.
///
/// Created and disposed by the picker; rebound whenever the surface changes, so
/// a swap from Google to OSM mid-session does not leave it pointing at a dead
/// map. Calls made before a map is attached are dropped rather than queued —
/// the picker only moves the camera in response to a user action, by which time
/// a map exists.
class PickerMapController {
  void Function(LatLng target, double zoom)? _moveImpl;

  // Where a move was asked for before any map existed. The SDK load is async,
  // so a user who pastes a link or picks a suggestion in that window used to
  // have their move dropped silently — the map then opened on the dialog's
  // original centre while the footer claimed the place they chose.
  LatLng? _pendingTarget;
  double? _pendingZoom;

  void move(LatLng target, double zoom) {
    final impl = _moveImpl;
    if (impl == null) {
      _pendingTarget = target;
      _pendingZoom = zoom;
      return;
    }
    impl(target, zoom);
  }

  void dispose() {
    _moveImpl = null;
    _pendingTarget = null;
    _pendingZoom = null;
  }
}

/// The map surface inside the location picker — Google where this build can
/// draw one, OpenStreetMap everywhere else.
///
/// The SDK is fetched at runtime (see maps_loader.dart), so which map appears is
/// decided asynchronously and can still change afterwards: Google reports a
/// refused key through `gm_authFailure` only once it tries to render. This
/// widget therefore owns a small state machine rather than a single boolean.
/// The picker above does not care which surface it got — it sees one controller
/// and one camera callback either way — so there is exactly one copy of the
/// search, pin and reverse-geocode logic.
///
/// What this widget deliberately does NOT own: the centre pin. It is a Flutter
/// overlay drawn by the picker on top of this widget, not a map marker, so it
/// looks and behaves identically on both maps and needs no marker API.
class PickerMap extends StatefulWidget {
  final PickerMapController controller;
  final LatLng initialCenter;
  final double initialZoom;

  /// Fired as the camera moves. [hasGesture] is true only when the USER moved
  /// the map — the picker uses it to decide that the pin has stopped being the
  /// searched place and become a hand-dropped one, so a false positive would
  /// throw away the place id it just resolved.
  final void Function(LatLng center, bool hasGesture) onCameraMove;

  /// Fired whenever the surface is decided or changes. `notice` is a
  /// user-facing sentence explaining an unexpected fallback, or empty when
  /// there is nothing to apologise for.
  final void Function(PickerMapSurface surface, String notice) onSurfaceChanged;

  const PickerMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.onCameraMove,
    required this.onSurfaceChanged,
  });

  @override
  State<PickerMap> createState() => _PickerMapState();
}

class _PickerMapState extends State<PickerMap> {
  PickerMapSurface _surface = PickerMapSurface.loading;

  fm.MapController? _osmCtrl;
  gm.GoogleMapController? _gmapCtrl;
  StreamSubscription<void>? _authSub;

  // Where a move WE issued is heading, or null when the camera is the user's.
  //
  // Google reports every camera change identically whether the user or the app
  // caused it, so provenance has to be tracked here. This used to be a bool
  // cleared on idle, which got it wrong in both directions: Google's own zoom
  // buttons and a container resize both report a "change" that is not a drag,
  // and a no-op move latched the flag on so real drags stopped registering.
  LatLng? _commandedTarget;

  // The move-start for our own command has not arrived yet. Any move-start
  // BEFORE it is the user grabbing the map mid-animation, which hands the
  // camera back to them.
  bool _awaitingCommandedStart = false;

  // A move arrived after the Google surface was chosen but before its
  // controller attached; replay it once onMapCreated fires.
  bool _replayOnCreate = false;

  // Where the camera is now, so a surface swap can hand the new map the view
  // the user was already looking at instead of flinging them back to Pune.
  late LatLng _center = widget.initialCenter;
  late double _zoom = widget.initialZoom;

  @override
  void initState() {
    super.initState();
    // A refusal can arrive long after the load succeeded — Google only checks
    // the key when it first tries to draw a map.
    _authSub = googleMapsAuthFailures.listen((_) {
      if (!mounted || _surface != PickerMapSurface.google) return;
      _settle(
        PickerMapSurface.osm,
        mapsFallbackMessage(MapsLoadResult.refused),
      );
    });
    if (!MapsConfig.googleMapsRequested) {
      // Nothing to wait for. Deferred only because onSurfaceChanged calls
      // setState on the parent, which is illegal during its build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settle(PickerMapSurface.osm, '');
      });
      return;
    }
    unawaited(_resolveSurface());
  }

  Future<void> _resolveSurface() async {
    final result = await loadGoogleMaps(MapsConfig.browserKey);
    if (!mounted) return;
    _settle(
      result == MapsLoadResult.loaded
          ? PickerMapSurface.google
          : PickerMapSurface.osm,
      mapsFallbackMessage(result),
    );
  }

  /// Adopt [surface], rebind the camera handle to whichever map is now live,
  /// and tell the dialog above.
  void _settle(PickerMapSurface surface, String notice) {
    if (_surface == surface) return;
    // Adopt anything the user asked for while the SDK was still loading, so the
    // map is BUILT at that place rather than panned there afterwards.
    final pending = widget.controller._pendingTarget;
    if (pending != null) {
      _center = pending;
      _zoom = widget.controller._pendingZoom ?? _zoom;
      widget.controller._pendingTarget = null;
      widget.controller._pendingZoom = null;
    }
    if (surface == PickerMapSurface.osm) {
      _osmCtrl ??= fm.MapController();
      widget.controller._moveImpl = _moveOsm;
      // The Google controller belongs to a widget that is about to leave the
      // tree; drop it so a late move() cannot reach a disposed platform view.
      _gmapCtrl = null;
    } else if (surface == PickerMapSurface.google) {
      widget.controller._moveImpl = _moveGoogle;
    }
    setState(() => _surface = surface);
    widget.onSurfaceChanged(surface, notice);
  }

  @override
  void dispose() {
    // Unbind first: disposing the underlying controller while the picker could
    // still call move() would throw on a disposed object.
    widget.controller._moveImpl = null;
    unawaited(_authSub?.cancel());
    _osmCtrl?.dispose();
    // _gmapCtrl is deliberately NOT disposed here. GoogleMap's own State owns
    // that controller and disposes it when the widget leaves the tree
    // (google_map.dart _disposeController), and because that runs as a deferred
    // microtask while this dispose is synchronous, disposing here won too and
    // the plugin's later call hit an already-removed map id — throwing on every
    // single picker close. _osmCtrl above is genuinely ours: flutter_map only
    // disposes a controller it created itself.
    _gmapCtrl = null;
    super.dispose();
  }

  void _moveOsm(LatLng target, double zoom) {
    _center = target;
    _zoom = zoom;
    _osmCtrl?.move(target, zoom);
  }

  void _moveGoogle(LatLng target, double zoom) {
    // Recorded BEFORE the controller guard: even if no map is attached yet, this
    // is where the pin now is, and it is what the next surface must be built at.
    _center = target;
    _zoom = zoom;
    _commandedTarget = target;
    final c = _gmapCtrl;
    if (c == null) {
      _replayOnCreate = true;
      return;
    }
    _awaitingCommandedStart = true;
    unawaited(
      c.animateCamera(
        gm.CameraUpdate.newCameraPosition(
          gm.CameraPosition(
            target: gm.LatLng(target.latitude, target.longitude),
            zoom: zoom,
          ),
        ),
      ),
    );
  }

  // Two camera reports can carry the same centre: a container resize (the
  // dialog's header grows when a hint appears, so the map shrinks) and Google's
  // own zoom buttons. Neither is a hand-drop. Reporting either as one wiped the
  // place id, address, search text and label the user had just resolved.
  static bool _samePoint(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-7 &&
      (a.longitude - b.longitude).abs() < 1e-7;

  void _report(LatLng center, bool platformSaysGesture) {
    final moved = !_samePoint(center, _center);
    _center = center;
    widget.onCameraMove(center, platformSaysGesture && moved);
  }

  @override
  Widget build(BuildContext context) => switch (_surface) {
    PickerMapSurface.loading => const _MapSkeleton(),
    PickerMapSurface.google => _GoogleSurface(
      initialCenter: _center,
      initialZoom: _zoom,
      onCreated: (c) {
        _gmapCtrl = c;
        if (!_replayOnCreate) return;
        // A search or pasted link resolved between this map being built and its
        // controller arriving. Without the replay the camera would sit at the
        // stale initialCameraPosition while the footer showed the new place.
        _replayOnCreate = false;
        _moveGoogle(_center, _zoom);
      },
      // The camera is ours only while a move we issued is still outstanding.
      onCameraMove: (center) => _report(center, _commandedTarget == null),
      onCameraMoveStarted: () {
        // The first move-start after we call animateCamera is our own. Any
        // move-start before that is the user grabbing the map — including mid
        // animation — which hands the camera straight back to them.
        if (_awaitingCommandedStart) {
          _awaitingCommandedStart = false;
          return;
        }
        _commandedTarget = null;
      },
      onCameraIdle: () {
        _commandedTarget = null;
        _awaitingCommandedStart = false;
      },
    ),
    PickerMapSurface.osm => _OsmSurface(
      controller: _osmCtrl,
      initialCenter: _center,
      initialZoom: _zoom,
      onPositionChanged: _report,
    ),
  };
}

class _GoogleSurface extends StatelessWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final ValueChanged<gm.GoogleMapController> onCreated;
  final ValueChanged<LatLng> onCameraMove;
  final VoidCallback onCameraMoveStarted;
  final VoidCallback onCameraIdle;

  const _GoogleSurface({
    required this.initialCenter,
    required this.initialZoom,
    required this.onCreated,
    required this.onCameraMove,
    required this.onCameraMoveStarted,
    required this.onCameraIdle,
  });

  @override
  Widget build(BuildContext context) {
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(
        target: gm.LatLng(initialCenter.latitude, initialCenter.longitude),
        zoom: initialZoom,
      ),
      onMapCreated: onCreated,
      onCameraMove: (pos) =>
          onCameraMove(LatLng(pos.target.latitude, pos.target.longitude)),
      onCameraMoveStarted: onCameraMoveStarted,
      onCameraIdle: onCameraIdle,
      // The picker draws its own centre pin and has its own confirm button, so
      // every Google chrome that would compete with them is off. Zoom controls
      // stay: this is a desktop-first screen and pinch-zoom is not available on
      // a mouse.
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      compassEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
    );
  }
}

class _OsmSurface extends StatelessWidget {
  final fm.MapController? controller;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(LatLng center, bool hasGesture) onPositionChanged;

  const _OsmSurface({
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.onPositionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return fm.FlutterMap(
      mapController: controller,
      options: fm.MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        onPositionChanged: (camera, hasGesture) =>
            onPositionChanged(camera.center, hasGesture),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vistar.lr_management',
        ),
      ],
    );
  }
}

/// Shown for the few hundred milliseconds the SDK takes to arrive. A bare
/// spinner in a 400 px box reads as a broken map; a sweeping shimmer over a
/// map-coloured ground reads as one that is on its way.
class _MapSkeleton extends StatefulWidget {
  const _MapSkeleton();

  @override
  State<_MapSkeleton> createState() => _MapSkeletonState();
}

class _MapSkeletonState extends State<_MapSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _shimmer.repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the OS "reduce motion" setting: a looping sweep is exactly the
    // kind of decoration it exists to switch off.
    final still = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: AppColors.line.withValues(alpha: 0.35),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!still)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1 - 2 * (1 - _shimmer.value), 0),
                      end: Alignment(1 + 2 * _shimmer.value, 0),
                      colors: [
                        Colors.transparent,
                        AppColors.white.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Center(
            child: Text(
              'Loading map…',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.slate.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
