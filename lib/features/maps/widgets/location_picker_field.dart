import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/maps_repository.dart';
import '../utils/google_maps_link.dart';
import 'picker_map.dart';

/// A form-field-styled control that opens a free OpenStreetMap picker (place
/// search + move-the-map centre pin) and returns a [PickedLocation]
/// (place_id, lat/lng, address, label). No API key required.
class LocationPickerField extends StatelessWidget {
  final PickedLocation? value;
  final ValueChanged<PickedLocation> onPicked;
  final String hintText;

  const LocationPickerField({
    super.key,
    required this.value,
    required this.onPicked,
    this.hintText = 'Pick location on map',
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    // A pin counts as set when it has usable COORDINATES, not an address.
    // Nominatim names very few plant gates, and /maps/reverse turns any upstream
    // failure into an empty string, so keying this off the address made a
    // perfectly good pasted-link pin render as the untouched grey hint.
    final has = v != null && RouteMaster.isUsableCoord(v.lat, v.lng);
    final label = has ? v.displayName : '';
    // Something real to show underneath even when the address came back empty.
    final detail = !has
        ? ''
        : (v.address.isNotEmpty
              ? v.address
              : '${v.lat.toStringAsFixed(5)}, ${v.lng.toStringAsFixed(5)}');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final result = await showDialog<PickedLocation>(
          context: context,
          builder: (_) => _MapPickerDialog(initial: v),
        );
        if (result != null) onPicked(result);
      },
      child: InputDecorator(
        isEmpty: !has,
        decoration: const InputDecoration(
          suffixIcon: Icon(
            Icons.place_outlined,
            color: AppColors.plum,
            size: 20,
          ),
        ),
        child: (has && label.isNotEmpty && label != detail)
            // The short label reads first; the full address stays as context.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.slate,
                    ),
                  ),
                ],
              )
            : Text(
                has ? detail : hintText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: has ? AppColors.ink : AppColors.slate,
                ),
              ),
      ),
    );
  }
}

class _MapPickerDialog extends ConsumerStatefulWidget {
  final PickedLocation? initial;
  const _MapPickerDialog({this.initial});

  @override
  ConsumerState<_MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends ConsumerState<_MapPickerDialog> {
  static const _default = LatLng(18.5204, 73.8567); // Pune

  final _mapCtrl = PickerMapController();
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _reverseDebounce;
  List<MapsSuggestion> _suggestions = [];
  bool _searching = false;
  // Once the user types their own label we stop overwriting it on every move.
  bool _nameEdited = false;
  // Shown under the search box rather than in a snackbar: the dialog is modal,
  // so a snackbar behind it is easy to miss.
  String _linkHint = '';
  // Every action that moves the pin takes a ticket. Reverse-geocodes are slow
  // and unordered, so without this an older pan's response lands after a newer
  // suggestion or pasted link and writes ITS address next to the new
  // coordinates — the saved from_address would then describe a different point
  // than from_lat/from_lng.
  int _pinSeq = 0;

  // Groups the keystrokes of ONE search with the details call that ends it.
  // Google bills that pair as a single session; without it every keystroke is
  // billed on its own. A fresh token is minted after each pick, because the
  // session is over the moment the user chooses — reusing it would silently
  // merge the next search into a session Google has already closed.
  //
  // Sending it is ALSO how this build tells the server it can handle a
  // suggestion that carries no coordinates. A client that sends no token is
  // served from the free provider instead, which is what keeps older deployed
  // builds working rather than dropping their pins at 0,0.
  String _sessionToken = const Uuid().v4();

  // A picked suggestion that has no pin yet has to be fetched before the map
  // can move. Held so the list can show which row is being resolved and refuse
  // a second tap while it is in flight.
  String _resolvingPlaceId = '';

  late LatLng _center;
  String _address = '';
  String _placeId = '';
  late PickedLocationSource _source;

  // Legacy rows hold projected metres (lat ~25,555,074) instead of degrees;
  // centring on one flies the map off the world, so it counts as "no initial".
  static bool _usableCoords(double lat, double lng) =>
      lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _center = (i != null && _usableCoords(i.lat, i.lng))
        ? LatLng(i.lat, i.lng)
        : _default;
    _address = i?.address ?? '';
    _placeId = i?.placeId ?? '';
    _source = i?.source ?? PickedLocationSource.stored;
    _searchCtrl.text = _address;
    _nameCtrl.text = i == null ? '' : i.displayName;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  // Keeps the label in step with the location until the user takes it over.
  void _prefillName(String address) {
    if (_nameEdited) return;
    final label = PickedLocation.shortLabel(address);
    if (label.isEmpty) return;
    _nameCtrl.text = label;
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final raw = q.trim();

    // A shortened link hides its coordinates behind a redirect we cannot follow
    // from the client, so ask for the expanded URL instead of failing silently.
    if (isShortGoogleMapsLink(raw)) {
      setState(() {
        _suggestions = [];
        _linkHint =
            "That's a shortened Google link. Open it once, then paste the "
            'full URL.';
      });
      return;
    }
    if (looksLikeGoogleMapsLink(raw)) {
      final link = parseGoogleMapsLink(raw);
      if (link == null) {
        setState(() {
          _suggestions = [];
          _linkHint = "Couldn't find coordinates in that link.";
        });
        return;
      }
      setState(() {
        _suggestions = [];
        _linkHint = '';
      });
      // Debounced like the search path. Typed rather than pasted, "18.5204,
      // 73.8567" matches as early as "18.5204,7" — applying on every keystroke
      // would fling the pin to Nigeria and burn a reverse-geocode per character
      // against Nominatim's 1 req/s policy.
      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) unawaited(_applyLink(link));
      });
      return;
    }

    if (_linkHint.isNotEmpty) {
      setState(() => _linkHint = '');
    }
    if (raw.length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final s = await ref
            .read(mapsRepositoryProvider)
            .autocomplete(
              q,
              sessionToken: _sessionToken,
              // Bias towards what the user is looking at, so "gate 2" finds the
              // one in this city rather than the highest-ranked one in India.
              lat: _center.latitude,
              lng: _center.longitude,
            );
        if (mounted) setState(() => _suggestions = s);
      } catch (_) {
        // surfaced if the user searches again / confirms
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  // Coordinates pasted as a Google Maps URL: the pin is exact, so it moves at
  // once and the address is filled in behind it, best-effort.
  Future<void> _applyLink(GoogleMapsLink link) async {
    _reverseDebounce?.cancel();
    final seq = ++_pinSeq;
    final c = LatLng(link.lat, link.lng);
    setState(() {
      _center = c;
      _placeId = ''; // a pasted link is not a Nominatim place
      _source = PickedLocationSource.googleLink;
      // Drop the old address with the old pin. Keeping it until the reverse
      // returns means a failed or empty lookup leaves the PREVIOUS location's
      // address sitting next to these coordinates, and "Use this" would save
      // that mismatched pair.
      _address = '';
    });
    _mapCtrl.move(c, 16);
    try {
      final addr = await ref
          .read(mapsRepositoryProvider)
          .reverse(c.latitude, c.longitude);
      if (!mounted || seq != _pinSeq) return;
      if (addr.isNotEmpty) {
        setState(() {
          _address = addr;
          _searchCtrl.text = addr;
        });
        _prefillName(addr);
      }
    } catch (_) {
      // keep the pasted coords even if reverse-geocode fails
    }
  }

  Future<void> _selectSuggestion(MapsSuggestion s) async {
    FocusScope.of(context).unfocus();
    // Panning does not clear the suggestion list, so a pan reverse-geocode can
    // still be pending (or in flight) when a suggestion is tapped. Take a fresh
    // ticket and cancel the pending one so the older answer cannot overwrite
    // this more authoritative pick.
    _reverseDebounce?.cancel();
    _searchDebounce?.cancel();
    final seq = ++_pinSeq;

    var address = s.text;
    var placeId = s.placeId;
    double lat;
    double lng;

    if (s.hasCoords) {
      // Already a pin: every saved gate and every Nominatim match. Free, and
      // instant — no round-trip before the map moves.
      lat = s.lat!;
      lng = s.lng!;
    } else {
      // Google returns no coordinates with a search result, so the pin has to be
      // fetched. Nothing moves until it arrives: moving first and correcting
      // afterwards would show the user a wrong location as if it were right.
      setState(() => _resolvingPlaceId = s.placeId);
      final place = await ref
          .read(mapsRepositoryProvider)
          .details(s, sessionToken: _sessionToken);
      if (!mounted) return;
      setState(() => _resolvingPlaceId = '');
      // A newer pick or pan happened while this was in flight — that one is
      // more recent and must win.
      if (seq != _pinSeq) return;
      if (place == null) {
        setState(
          () => _linkHint =
              "Couldn't get the exact location for that result. "
              'Try another one, or drop the pin yourself.',
        );
        return;
      }
      lat = place.lat;
      lng = place.lng;
      // Prefer the resolved address: the suggestion text is a display label
      // ("Vistar Logitek Pvt Ltd"), while details returns the full postal
      // address, which is what a driver needs.
      if (place.address.isNotEmpty) address = place.address;
      if (place.placeId.isNotEmpty) placeId = place.placeId;
    }

    // The session ends with the pick, whether or not it cost a details call.
    // The next search must open a new one.
    _sessionToken = const Uuid().v4();

    final c = LatLng(lat, lng);
    setState(() {
      _center = c;
      _address = address;
      _placeId = placeId;
      _suggestions = [];
      _linkHint = '';
      _source = PickedLocationSource.search;
      _searchCtrl.text = address;
    });
    _prefillName(address);
    _mapCtrl.move(c, 15);
  }

  // Reverse-geocode the map centre after the user pans (debounced). The pin's
  // identity is dropped by the gesture itself, in onPositionChanged — not here,
  // because confirming inside this 700 ms window would otherwise hand back the
  // searched place's id attached to the panned coordinates.
  void _scheduleReverse() {
    _reverseDebounce?.cancel();
    final seq = ++_pinSeq;
    _reverseDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final addr = await ref
            .read(mapsRepositoryProvider)
            .reverse(_center.latitude, _center.longitude);
        if (!mounted || seq != _pinSeq) return;
        if (addr.isNotEmpty) {
          setState(() {
            _address = addr;
            _searchCtrl.text = addr;
          });
          _prefillName(addr);
        }
      } catch (_) {
        // keep the panned coords even if reverse-geocode fails
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pick location',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search address / place, or paste a Maps link…',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.slate,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                  if (_linkHint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _linkHint,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  PickerMap(
                    controller: _mapCtrl,
                    initialCenter: _center,
                    initialZoom: 13,
                    onCameraMove: (center, hasGesture) {
                      _center = center;
                      if (!hasGesture) return;
                      // The place id belongs to where the pin WAS, so it has
                      // to go with the drag itself. Guarded so one setState
                      // runs per gesture, not one per frame.
                      if (_placeId.isNotEmpty ||
                          _source != PickedLocationSource.pin) {
                        setState(() {
                          _placeId = '';
                          _source = PickedLocationSource.pin;
                        });
                      }
                      _scheduleReverse();
                    },
                  ),
                  // Fixed centre pin — its tip marks the chosen point.
                  const IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 36),
                        child: Icon(
                          Icons.place,
                          size: 44,
                          color: AppColors.plum,
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: 2,
                    right: 2,
                    child: ColoredBox(
                      color: Color(0xCCFFFFFF),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          '© OpenStreetMap',
                          style: TextStyle(fontSize: 9, color: AppColors.slate),
                        ),
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Material(
                        elevation: 3,
                        child: Container(
                          color: AppColors.white,
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              for (final s in _suggestions)
                                ListTile(
                                  dense: true,
                                  // A saved gate is marked, because it is the
                                  // better answer: somebody already sent a
                                  // vehicle there and placed this pin by hand,
                                  // where a search engine drops it on the front
                                  // office or the postal centroid.
                                  leading: _resolvingPlaceId == s.placeId
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.plum,
                                          ),
                                        )
                                      : Icon(
                                          s.source == 'saved_place'
                                              ? Icons.bookmark_outline
                                              : Icons.place_outlined,
                                          size: 18,
                                          color: AppColors.plum,
                                        ),
                                  title: Text(
                                    s.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: s.source == 'saved_place'
                                      ? const Text(
                                          'Saved route location',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.slate,
                                          ),
                                        )
                                      : null,
                                  // One resolve at a time: a second tap while a
                                  // pin is being fetched would open a race whose
                                  // loser silently discards the user's choice.
                                  onTap: _resolvingPlaceId.isEmpty
                                      ? () => unawaited(_selectSuggestion(s))
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Name / label',
                      hintText: 'Short name for this point',
                    ),
                    onChanged: (_) => _nameEdited = true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _address.isEmpty
                              ? 'Search, or move the map to position the pin'
                              : _address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppButton(
                        label: 'Cancel',
                        kind: BtnKind.ghost,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Use this',
                        icon: Icons.check_rounded,
                        onPressed: () => Navigator.pop(
                          context,
                          PickedLocation(
                            placeId: _placeId,
                            lat: _center.latitude,
                            lng: _center.longitude,
                            address: _address,
                            name: _nameCtrl.text.trim(),
                            source: _source,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
