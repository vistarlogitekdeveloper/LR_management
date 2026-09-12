import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../utils/maps_config.dart';

/// The map surface inside the location picker — Google where this build can
/// draw one, OpenStreetMap everywhere else.
///
/// Why both: the browser key is restricted to the web domains, so a Google map
/// is only available on web (see [MapsConfig.googleMapsEnabled]). Mobile, local
/// dev without a key, and a web build whose key was refused all fall back to the
/// OSM tiles the picker has always used. The picker above does not care which it
/// got — it sees one controller and one camera callback either way — so there is
/// exactly one copy of the search, pin and reverse-geocode logic.
///
/// What this widget deliberately does NOT own: the centre pin. It is a Flutter
/// overlay drawn by the picker on top of this widget, not a map marker, so it
/// looks and behaves identically on both maps and needs no marker API.

/// Imperative handle for moving the camera.
///
/// Created and disposed by the picker; bound by whichever map ends up being
/// built. Calls made before a map is attached are dropped rather than queued —
/// the picker only moves the camera in response to a user action, by which time
/// the map exists.
class PickerMapController {
  void Function(LatLng target, double zoom)? _moveImpl;

  void move(LatLng target, double zoom) => _moveImpl?.call(target, zoom);

  void dispose() => _moveImpl = null;
}

class PickerMap extends StatefulWidget {
  final PickerMapController controller;
  final LatLng initialCenter;
  final double initialZoom;

  /// Fired as the camera moves. [hasGesture] is true only when the USER moved
  /// the map — the picker uses it to decide that the pin has stopped being the
  /// searched place and become a hand-dropped one, so a false positive would
  /// throw away the place id it just resolved.
  final void Function(LatLng center, bool hasGesture) onCameraMove;

  const PickerMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.onCameraMove,
  });

  @override
  State<PickerMap> createState() => _PickerMapState();
}

class _PickerMapState extends State<PickerMap> {
  // Resolved once, in initState, and not re-read on rebuild: the answer depends
  // on a compile-time constant and on a script that either loaded before the app
  // started or did not. Re-checking per frame could only ever return the same
  // value, and swapping map implementations mid-dialog would lose the camera.
  late final bool _useGoogle;

  // flutter_map path
  fm.MapController? _osmCtrl;

  // Google path
  gm.GoogleMapController? _gmapCtrl;

  // True while a camera move WE asked for is still running. Google reports
  // every camera change the same way whether the user or the app caused it, so
  // the distinction has to be tracked here; without it, calling move() after a
  // search would look like a drag and immediately discard the place id that
  // search just produced.
  bool _programmaticMove = false;

  @override
  void initState() {
    super.initState();
    _useGoogle = MapsConfig.googleMapsEnabled;
    if (_useGoogle) {
      widget.controller._moveImpl = _moveGoogle;
    } else {
      _osmCtrl = fm.MapController();
      widget.controller._moveImpl = _moveOsm;
    }
  }

  @override
  void dispose() {
    // Unbind first: disposing the underlying controller while the picker could
    // still call move() would throw on a disposed object.
    widget.controller._moveImpl = null;
    _osmCtrl?.dispose();
    _gmapCtrl?.dispose();
    super.dispose();
  }

  void _moveOsm(LatLng target, double zoom) {
    _osmCtrl?.move(target, zoom);
  }

  void _moveGoogle(LatLng target, double zoom) {
    final c = _gmapCtrl;
    if (c == null) return;
    _programmaticMove = true;
    c.animateCamera(
      gm.CameraUpdate.newCameraPosition(
        gm.CameraPosition(
          target: gm.LatLng(target.latitude, target.longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_useGoogle) return _buildGoogle();
    return _buildOsm();
  }

  Widget _buildGoogle() {
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(
        target: gm.LatLng(
          widget.initialCenter.latitude,
          widget.initialCenter.longitude,
        ),
        zoom: widget.initialZoom,
      ),
      onMapCreated: (c) => _gmapCtrl = c,
      onCameraMove: (pos) {
        widget.onCameraMove(
          LatLng(pos.target.latitude, pos.target.longitude),
          !_programmaticMove,
        );
      },
      // animateCamera always settles into idle, which is where a move we
      // started stops being ours. If the user grabs the map mid-animation we
      // miss that one gesture — they are still dragging, so the next frame
      // reports it correctly.
      onCameraIdle: () => _programmaticMove = false,
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
      mapType: gm.MapType.normal,
    );
  }

  Widget _buildOsm() {
    return fm.FlutterMap(
      mapController: _osmCtrl,
      options: fm.MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        onPositionChanged: (camera, hasGesture) =>
            widget.onCameraMove(camera.center, hasGesture),
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
