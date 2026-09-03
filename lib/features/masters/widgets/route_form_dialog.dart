import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../auth/providers/auth_provider.dart';
import '../../lookups/data/lookup_value.dart';
import '../../lookups/providers/lookups_provider.dart';
import '../../maps/widgets/location_picker_field.dart';
import '../providers/master_providers.dart';
import 'master_actions.dart';

/// Route create/edit form. Has its own dialog (not the generic MasterFormDialog)
/// because From / To can be picked on a map (Google Places) to capture
/// coordinates, not just typed.
class RouteFormDialog extends ConsumerStatefulWidget {
  final RouteMaster? existing;
  const RouteFormDialog({super.key, this.existing});

  /// Returns the saved route (created or updated), or null if the form was
  /// dismissed — so a caller can select it straight away.
  static Future<RouteMaster?> show(BuildContext context,
      {RouteMaster? existing}) {
    return showDialog<RouteMaster>(
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
  String? _vehicleTypeId;
  String? _capacityId;
  bool _saving = false;
  // Set once the user tries to save, so the "pick on map" errors only appear
  // after an attempt (not on a fresh form).
  bool _triedSave = false;

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
    _vehicleTypeId = r?.vehicleTypeId;
    _capacityId = r?.capacityId;
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
    final formOk = _formKey.currentState!.validate();
    // From/To map coordinates are mandatory: SIM tracking needs origin +
    // destination points, and a route saved with only city labels fails to
    // start a trip ("Insufficient Data"). Enforce the pin here at the source.
    final locOk = _fromLoc != null && _toLoc != null;
    if (!formOk || !locOk) {
      if (!locOk) {
        setState(() => _triedSave = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please pick both the From and To locations on the map — this is required for vehicle tracking.',
            ),
          ),
        );
      }
      return;
    }
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
        vehicleTypeId: _vehicleTypeId,
        capacityId: _capacityId,
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
      final RouteMaster saved;
      if (_existing == null) {
        // The create response carries the backend-assigned id, so hand that
        // copy back (a caller may select it) rather than the local one.
        saved = await n.add(route);
      } else {
        await n.update(route);
        saved = route;
      }
      if (!mounted) return;
      navigator.pop(saved);
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
    final vehicleTypes =
        lookupList(ref.watch(lookupsMapProvider), 'VEHICLE_TYPE');
    final capacities =
        lookupList(ref.watch(lookupsMapProvider), 'VEHICLE_CAPACITY');
    // Visibility perms (migration 072): hide the rate inputs the user may not
    // see. Controllers stay initialised — only the fields are dropped — and the
    // backend strips any redacted value on save.
    final user = ref.watch(currentUserProvider);
    final canViewTransporterRate = user?.canViewTransporterRate ?? false;
    final canViewCustomerRate = user?.canViewCustomerRate ?? false;
    // Resolve the selected option from the loaded lookups by id; fall back to a
    // synthetic value (from the edited route) while lookups are still loading.
    LookupValue? selectedVt =
        vehicleTypes.where((v) => v.id == _vehicleTypeId).firstOrNull;
    if (selectedVt == null && (_vehicleTypeId ?? '').isNotEmpty) {
      selectedVt = LookupValue(
        id: _vehicleTypeId!,
        category: 'VEHICLE_TYPE',
        code: _existing?.vehicleTypeCode ?? '',
        label: _existing?.vehicleTypeLabel ?? '',
      );
    }
    LookupValue? selectedCap =
        capacities.where((v) => v.id == _capacityId).firstOrNull;
    if (selectedCap == null && (_capacityId ?? '').isNotEmpty) {
      selectedCap = LookupValue(
        id: _capacityId!,
        category: 'VEHICLE_CAPACITY',
        code: _existing?.capacityCode ?? '',
        label: _existing?.capacityLabel ?? '',
      );
    }
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
                          required: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocationPickerField(
                                value: _fromLoc,
                                hintText: 'Pick the pickup location on the map',
                                onPicked: (loc) => setState(() {
                                  _fromLoc = loc;
                                  if (_fromCity.text.trim().isEmpty) {
                                    _fromCity.text = _shortLabel(loc.address);
                                  }
                                }),
                              ),
                              if (_triedSave && _fromLoc == null)
                                _pickError('Pick the pickup location on the map.'),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth,
                        child: LabeledField(
                          label: 'To Location (map)',
                          required: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocationPickerField(
                                value: _toLoc,
                                hintText: 'Pick the delivery location on the map',
                                onPicked: (loc) => setState(() {
                                  _toLoc = loc;
                                  if (_toCity.text.trim().isEmpty) {
                                    _toCity.text = _shortLabel(loc.address);
                                  }
                                }),
                              ),
                              if (_triedSave && _toLoc == null)
                                _pickError('Pick the delivery location on the map.'),
                            ],
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
                      if (canViewTransporterRate)
                        SizedBox(
                          width: half,
                          child: _text(
                            _baseRate,
                            'Transporter Rate (₹)',
                            required: true,
                            number: true,
                          ),
                        ),
                      if (canViewCustomerRate)
                        SizedBox(
                          width: half,
                          child: _text(
                            _customerRate,
                            'Customer Rate (₹)',
                            required: true,
                            number: true,
                            hint: 'Used for Vistar margin',
                          ),
                        ),
                      SizedBox(
                        width: half,
                        child: LabeledField(
                          label: 'Vehicle Type',
                          child: SearchableField<LookupValue>(
                            value: selectedVt,
                            options: vehicleTypes,
                            labelOf: (v) => v.label,
                            hintText: 'Select vehicle type',
                            dialogTitle: 'Select Vehicle Type',
                            clearable: true,
                            onChanged: (v) =>
                                setState(() => _vehicleTypeId = v?.id),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: half,
                        child: LabeledField(
                          label: 'Vehicle Capacity',
                          child: SearchableField<LookupValue>(
                            value: selectedCap,
                            options: capacities,
                            labelOf: (v) => v.label,
                            hintText: 'Select vehicle capacity',
                            dialogTitle: 'Select Vehicle Capacity',
                            clearable: true,
                            onChanged: (v) =>
                                setState(() => _capacityId = v?.id),
                          ),
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

  // Inline validation message for the map pickers (they are not FormFields, so
  // they can't hook into the Form validator — we render the error ourselves).
  Widget _pickError(String msg) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 2),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            msg,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
          ),
        ),
      ],
    ),
  );

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
