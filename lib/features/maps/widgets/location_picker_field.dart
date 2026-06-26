import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/maps_repository.dart';

/// A form-field-styled control that opens a free OpenStreetMap picker (place
/// search + move-the-map centre pin) and returns a [PickedLocation]
/// (place_id, lat/lng, address). No API key required.
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
    final has = value != null && value!.address.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final result = await showDialog<PickedLocation>(
          context: context,
          builder: (_) => _MapPickerDialog(initial: value),
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
        child: Text(
          has ? value!.address : hintText,
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

  final _mapCtrl = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _reverseDebounce;
  List<MapsSuggestion> _suggestions = [];
  bool _searching = false;

  late LatLng _center;
  String _address = '';
  String _placeId = '';

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _center = (i != null && i.lat != 0 && i.lng != 0)
        ? LatLng(i.lat, i.lng)
        : _default;
    _address = i?.address ?? '';
    _placeId = i?.placeId ?? '';
    _searchCtrl.text = _address;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final s = await ref.read(mapsRepositoryProvider).autocomplete(q);
        if (mounted) setState(() => _suggestions = s);
      } catch (_) {
        // surfaced if the user searches again / confirms
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _selectSuggestion(MapsSuggestion s) {
    FocusScope.of(context).unfocus();
    final c = LatLng(s.lat, s.lng);
    setState(() {
      _center = c;
      _address = s.text;
      _placeId = s.placeId;
      _suggestions = [];
      _searchCtrl.text = s.text;
    });
    _mapCtrl.move(c, 15);
  }

  // Reverse-geocode the map centre after the user pans (debounced).
  void _scheduleReverse() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (mounted) {
        setState(() => _placeId = ''); // panned off the searched place
      }
      try {
        final addr = await ref
            .read(mapsRepositoryProvider)
            .reverse(_center.latitude, _center.longitude);
        if (mounted && addr.isNotEmpty) {
          setState(() {
            _address = addr;
            _searchCtrl.text = addr;
          });
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
                      hintText: 'Search address / place…',
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
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 13,
                      onPositionChanged: (camera, hasGesture) {
                        _center = camera.center;
                        if (hasGesture) _scheduleReverse();
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.vistar.lr_management',
                      ),
                    ],
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
                                  leading: const Icon(
                                    Icons.place_outlined,
                                    size: 18,
                                    color: AppColors.plum,
                                  ),
                                  title: Text(
                                    s.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  onTap: () => _selectSuggestion(s),
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
              child: Row(
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
                      ),
                    ),
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
