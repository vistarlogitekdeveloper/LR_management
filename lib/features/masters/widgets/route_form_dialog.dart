import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../maps/widgets/location_picker_field.dart';
import '../providers/master_providers.dart';
import 'master_actions.dart';

/// Route create/edit form. Has its own dialog (not the generic MasterFormDialog)
/// because From / To can be picked on a map (Google Places) to capture
/// coordinates, not just typed.
class RouteFormDialog extends ConsumerStatefulWidget {
  final RouteMaster? existing;
  const RouteFormDialog({super.key, this.existing});

  static Future<bool?> show(BuildContext context, {RouteMaster? existing}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: RouteFormDialog(existing: existing),
        ),
      ),
    );
  }

  @override
  ConsumerState<RouteFormDialog> createState() => _RouteFormDialogState();
}

class _RouteFormDialogState extends ConsumerState<RouteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fromCity;
  late final TextEditingController _toCity;
  late final TextEditingController _distance;
  late final TextEditingController _baseRate;
  late final TextEditingController _customerRate;
  PickedLocation? _fromLoc;
  PickedLocation? _toLoc;
  bool _saving = false;

  RouteMaster? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final r = _existing;
    _fromCity = TextEditingController(text: r?.fromCity ?? '');
    _toCity = TextEditingController(text: r?.toCity ?? '');
    _distance = TextEditingController(
      text: (r != null && r.distanceKm > 0)
          ? r.distanceKm.toStringAsFixed(0)
          : '',
    );
    _baseRate = TextEditingController(
      text: (r != null && r.baseRate > 0) ? r.baseRate.toStringAsFixed(0) : '',
    );
    _customerRate = TextEditingController(
      text: (r != null && r.customerRate > 0)
          ? r.customerRate.toStringAsFixed(0)
          : '',
    );
    if (r != null && r.hasFromCoords) {
      _fromLoc = PickedLocation(
        placeId: r.fromPlaceId,
        lat: r.fromLat!,
        lng: r.fromLng!,
        address: r.fromAddress,
      );
    }
    if (r != null && r.hasToCoords) {
      _toLoc = PickedLocation(
        placeId: r.toPlaceId,
        lat: r.toLat!,
        lng: r.toLng!,
        address: r.toAddress,
      );
    }
  }

  @override
  void dispose() {
    for (final c in [_fromCity, _toCity, _distance, _baseRate, _customerRate]) {
      c.dispose();
    }
    super.dispose();
  }

  // Pull a short label out of an address (text before the first comma) — used
  // to pre-fill the From/To label only when the user hasn't typed one.
  String _shortLabel(String address) =>
      address.contains(',') ? address.split(',').first.trim() : address.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    double parse(TextEditingController c) =>
        double.tryParse(c.text.trim()) ?? 0;
    try {
      final n = ref.read(routesProvider.notifier);
      final route = RouteMaster(
        id: _existing?.id ?? const Uuid().v4(),
        fromCity: _fromCity.text.trim(),
        toCity: _toCity.text.trim(),
        distanceKm: parse(_distance),
        baseRate: parse(_baseRate),
        customerRate: parse(_customerRate),
        fromPlaceId: _fromLoc?.placeId ?? '',
        fromLat: _fromLoc?.lat,
        fromLng: _fromLoc?.lng,
        fromAddress: _fromLoc?.address ?? '',
        toPlaceId: _toLoc?.placeId ?? '',
        toLat: _toLoc?.lat,
        toLng: _toLoc?.lng,
        toAddress: _toLoc?.address ?? '',
        version: _existing?.version ?? 0,
      );
      if (_existing == null) {
        await n.add(route);
      } else {
        await n.update(route);
      }
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(MasterActions.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 560 ? 2 : 1;
                  const spacing = 14.0;
                  final half = (c.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: half,
                        child: _text(
                          _fromCity,
                          'From Label',
                          required: true,
                          hint: 'e.g. VLL - Pune',
                        ),
                      ),
                      SizedBox(
                        width: half,
                        child: _text(
                          _toCity,
                          'To Label',
                          required: true,
                          hint: 'e.g. TATA - Chakan',
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: LabeledField(
                          label: 'From Location (map)',
                          child: LocationPickerField(
                            value: _fromLoc,
                            hintText: 'Pick the pickup location on the map',
                            onPicked: (loc) => setState(() {
                              _fromLoc = loc;
                              if (_fromCity.text.trim().isEmpty) {
                                _fromCity.text = _shortLabel(loc.address);
                              }
                            }),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: LabeledField(
                          label: 'To Location (map)',
                          child: LocationPickerField(
                            value: _toLoc,
                            hintText: 'Pick the delivery location on the map',
                            onPicked: (loc) => setState(() {
                              _toLoc = loc;
                              if (_toCity.text.trim().isEmpty) {
                                _toCity.text = _shortLabel(loc.address);
                              }
                            }),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: half,
                        child: _text(
                          _distance,
                          'Distance (km)',
                          required: true,
                          number: true,
                        ),
                      ),
                      SizedBox(
                        width: half,
                        child: _text(
                          _baseRate,
                          'Transporter Rate (₹)',
                          required: true,
                          number: true,
                        ),
                      ),
                      SizedBox(
                        width: half,
                        child: _text(
                          _customerRate,
                          'Customer Rate (₹)',
                          number: true,
                          hint: 'Used for Vistar margin',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _existing == null ? 'New Route' : 'Edit Route',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: AppColors.slate),
        ),
      ],
    ),
  );

  Widget _text(
    TextEditingController c,
    String label, {
    bool required = false,
    bool number = false,
    String? hint,
  }) {
    return LabeledField(
      label: label,
      required: required,
      child: TextFormField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  Widget _footer() => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          label: 'Cancel',
          kind: BtnKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 10),
        AppButton(
          label: _saving ? 'Saving…' : 'Save',
          icon: Icons.save_outlined,
          onPressed: _saving ? null : _save,
        ),
      ],
    ),
  );
}
