import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mime_types.dart';
import '../../../shared/models/attachment.dart';
import '../../../shared/models/consignee.dart';
import '../../../shared/models/consignor.dart';
import '../../../shared/models/driver.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/lr_template.dart';
import '../../../shared/models/route_master.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/form_field_spec.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/master_form_dialog.dart';
import '../../../shared/widgets/section_title.dart';
import '../../lookups/data/lookup_value.dart';
import '../../lookups/providers/lookups_provider.dart';
import '../../masters/providers/master_providers.dart';
import '../../masters/widgets/master_actions.dart';
import '../../shell/widgets/app_topbar.dart';
import '../data/lr_repository.dart';
import '../providers/lr_providers.dart';
import '../providers/templates_provider.dart';

class CreateLrScreen extends ConsumerStatefulWidget {
  final String? editId;
  const CreateLrScreen({super.key, this.editId});

  @override
  ConsumerState<CreateLrScreen> createState() => _CreateLrScreenState();
}

/// One part/line within an invoice. Each maps to a backend invoice_item.
class _PartLineForm {
  final partDescription = TextEditingController();
  final nature = TextEditingController();
  final packages = TextEditingController(text: '0');
  final quantity = TextEditingController(text: '0');
  final weight = TextEditingController(text: '0');
  final value = TextEditingController(text: '0');
  LookupValue? packageType;

  void dispose() {
    partDescription.dispose();
    nature.dispose();
    packages.dispose();
    quantity.dispose();
    weight.dispose();
    value.dispose();
  }
}

/// One invoice (number + optional ASN) that can carry many part lines.
class _InvoiceForm {
  final invoiceNo = TextEditingController();
  final asn = TextEditingController();
  final List<_PartLineForm> parts = [_PartLineForm()];

  void dispose() {
    invoiceNo.dispose();
    asn.dispose();
    for (final p in parts) {
      p.dispose();
    }
  }
}

class _CreateLrScreenState extends ConsumerState<CreateLrScreen> {
  final _formKey = GlobalKey<FormState>();

  Consignor? _consignor;
  Consignee? _consignee;
  Vehicle? _vehicle;
  Transporter? _transporter;
  Driver? _driver;
  RouteMaster? _route;

  LookupValue? _payType;
  LookupValue? _deliveryType;
  LookupValue? _advancePaidBy;
  LookupValue? _tripLeadBy;
  LookupValue? _ewbLoad;

  final _customerCtrl = TextEditingController();

  // Invoice & Goods: one or more invoices, each with one or more part lines.
  final List<_InvoiceForm> _invoices = [_InvoiceForm()];

  final _freightCtrl = TextEditingController(text: '0');
  final _doorCtrl = TextEditingController(text: '0');
  final _handlingCtrl = TextEditingController(text: '0');
  final _insuranceCtrl = TextEditingController(text: '0');
  final _advanceCtrl = TextEditingController(text: '0');
  final _mathadiCtrl = TextEditingController(text: '0');
  final _remarksCtrl = TextEditingController();
  final _ewbCtrl = TextEditingController();

  bool _isEdit = false;
  bool _saving = false;
  bool _loading = true;
  LorryReceipt? _editing;

  // Stable per-form idempotency key: re-submitting the same new LR can never
  // create a duplicate (the server dedupes on this key).
  final String _idempotencyKey = const Uuid().v4();

  LrTemplate? _appliedTemplate;

  List<Attachment> _existingAttachments = [];
  final List<PlatformFile> _newFiles = [];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.editId != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Map<String, List<LookupValue>> get _lookups => ref.read(lookupsMapProvider);

  LookupValue? _firstLookup(String category) {
    final list = _lookups[category] ?? const [];
    return list.isEmpty ? null : list.first;
  }

  Future<void> _hydrate() async {
    final consignors = ref.read(consignorsProvider);
    final consignees = ref.read(consigneesProvider);
    final vehicles = ref.read(vehiclesProvider);
    final transporters = ref.read(transportersProvider);
    final drivers = ref.read(driversProvider);
    final routes = ref.read(routesProvider);

    if (_isEdit) {
      try {
        final lr = await ref.read(lrRepositoryProvider).getById(widget.editId!);
        _editing = lr;
        T? pick<T>(List<T> list, bool Function(T) test) {
          for (final e in list) {
            if (test(e)) return e;
          }
          return null;
        }

        _consignor =
            pick(consignors, (c) => c.id == lr.consignor.id) ?? lr.consignor;
        _consignee =
            pick(consignees, (c) => c.id == lr.consignee.id) ?? lr.consignee;
        _vehicle = pick(vehicles, (v) => v.id == lr.vehicle.id) ??
            (lr.vehicle.id.isNotEmpty ? lr.vehicle : null);
        _transporter = pick(transporters, (t) => t.id == lr.transporter.id) ??
            (lr.transporter.id.isNotEmpty ? lr.transporter : null);
        _driver = pick(drivers, (d) => d.id == lr.driverId);
        _route = pick(routes, (r) => r.id == lr.routeId);

        _payType = _byCode('PAY_TYPE', lr.payType.code);
        _deliveryType = _byCode('DELIVERY_TYPE', lr.deliveryType.code);
        _advancePaidBy =
            lookupById(_lookups, 'ADVANCE_PAID_BY', lr.freight.advancePaidById);
        _tripLeadBy =
            lookupById(_lookups, 'TRIP_LEAD_BY', lr.freight.tripLeadById);
        _ewbLoad = lookupById(_lookups, 'EWB_LOAD_TYPE', lr.ewb?.loadTypeId);

        _rebuildInvoicesFromItems(lr.items);

        _freightCtrl.text = lr.freight.freight.toStringAsFixed(0);
        _doorCtrl.text = lr.freight.doorDelivery.toStringAsFixed(0);
        _handlingCtrl.text = lr.freight.handling.toStringAsFixed(0);
        _insuranceCtrl.text = lr.freight.insurance.toStringAsFixed(0);
        _advanceCtrl.text = lr.freight.advance.toStringAsFixed(0);
        _mathadiCtrl.text = lr.freight.mathadi.toStringAsFixed(0);
        _remarksCtrl.text = lr.remarks ?? '';
        _customerCtrl.text = lr.customerName;
        _ewbCtrl.text = lr.ewb?.number ?? '';
        _existingAttachments = List.of(lr.attachments);
      } catch (e) {
        if (mounted) MasterActions.showError(context, e);
      }
    } else {
      // New LR: start completely blank so the operator consciously picks each
      // value. (Use an LR Template at the top of the form to pre-fill defaults.)
      _consignor = null;
      _consignee = null;
      _vehicle = null;
      _transporter = null;
      _driver = null;
      _route = null;
      _payType = null;
      _deliveryType = null;
      _advancePaidBy = null;
      _tripLeadBy = null;
      _ewbLoad = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  LookupValue? _byCode(String category, String code) {
    for (final v in _lookups[category] ?? const <LookupValue>[]) {
      if (v.code == code) return v;
    }
    return _firstLookup(category);
  }

  @override
  void dispose() {
    for (final c in [
      _customerCtrl,
      _freightCtrl,
      _doorCtrl,
      _handlingCtrl,
      _insuranceCtrl,
      _advanceCtrl,
      _mathadiCtrl,
      _remarksCtrl,
      _ewbCtrl,
    ]) {
      c.dispose();
    }
    for (final inv in _invoices) {
      inv.dispose();
    }
    super.dispose();
  }

  // Rebuild the invoice/part structure from an existing LR's items (edit mode),
  // grouping line items by (invoice_no + asn).
  void _rebuildInvoicesFromItems(List<InvoiceItem> items) {
    if (items.isEmpty) return; // keep the default empty invoice
    for (final inv in _invoices) {
      inv.dispose();
    }
    _invoices.clear();
    final byKey = <String, _InvoiceForm>{};
    final order = <String>[];
    for (final it in items) {
      final key = '${it.invoiceNo}${it.asn}';
      var f = byKey[key];
      if (f == null) {
        f = _InvoiceForm();
        for (final pp in f.parts) {
          pp.dispose();
        }
        f.parts.clear();
        f.invoiceNo.text = it.invoiceNo;
        f.asn.text = it.asn;
        byKey[key] = f;
        order.add(key);
      }
      final pl = _PartLineForm();
      pl.partDescription.text = it.partDescription;
      pl.nature.text = it.natureOfGoods;
      pl.packages.text = '${it.packages}';
      pl.quantity.text = '${it.quantity}';
      pl.weight.text = it.weight.toStringAsFixed(0);
      pl.value.text = it.grossValue.toStringAsFixed(0);
      pl.packageType = lookupById(_lookups, 'PACKAGE_TYPE', it.packageTypeId);
      f.parts.add(pl);
    }
    for (final key in order) {
      _invoices.add(byKey[key]!);
    }
  }

  // Rebuild the invoice/part structure from a saved template snapshot.
  void _applyInvoicesSnapshot(dynamic invList) {
    if (invList is! List || invList.isEmpty) return;
    for (final inv in _invoices) {
      inv.dispose();
    }
    _invoices.clear();
    for (final invMap in invList) {
      if (invMap is! Map) continue;
      final f = _InvoiceForm();
      for (final pp in f.parts) {
        pp.dispose();
      }
      f.parts.clear();
      f.invoiceNo.text = (invMap['invoice_no'] ?? '').toString();
      f.asn.text = (invMap['asn'] ?? '').toString();
      final parts = invMap['parts'];
      if (parts is List) {
        for (final pm in parts) {
          if (pm is! Map) continue;
          final pl = _PartLineForm();
          pl.partDescription.text = (pm['part_description'] ?? '').toString();
          pl.nature.text = (pm['nature_of_goods'] ?? '').toString();
          pl.packages.text = (pm['packages'] ?? '0').toString();
          pl.quantity.text = (pm['quantity'] ?? '0').toString();
          pl.weight.text = (pm['weight_kg'] ?? '0').toString();
          pl.value.text = (pm['gross_value'] ?? '0').toString();
          pl.packageType =
              lookupById(_lookups, 'PACKAGE_TYPE', pm['package_type_id'] as String?);
          f.parts.add(pl);
        }
      }
      if (f.parts.isEmpty) f.parts.add(_PartLineForm());
      _invoices.add(f);
    }
    if (_invoices.isEmpty) _invoices.add(_InvoiceForm());
  }

  double _toDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  double get _gst {
    final base =
        _toDouble(_freightCtrl) + _toDouble(_doorCtrl) + _toDouble(_handlingCtrl);
    return (base * 0.12).roundToDouble();
  }

  double get _total =>
      _toDouble(_freightCtrl) +
      _toDouble(_doorCtrl) +
      _toDouble(_handlingCtrl) +
      _toDouble(_insuranceCtrl) +
      _gst;

  double get _balance => _total - _toDouble(_advanceCtrl);

  /// Auto-calculated Vistar margin = route customer rate − freight.
  /// (Zero when the selected route has no customer rate set.)
  double get _vistarMargin {
    final cr = _route?.customerRate ?? 0;
    if (cr <= 0) return 0;
    return cr - _toDouble(_freightCtrl);
  }

  Future<void> _pickInvoices() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic',
        'xls', 'xlsx', 'doc', 'docx', 'csv',
      ],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() => _newFiles.addAll(picked.files));
  }

  Future<void> _removeExistingAttachment(Attachment a) async {
    try {
      await ref
          .read(lrRepositoryProvider)
          .deleteAttachment(_editing!.id, a.id);
      setState(() =>
          _existingAttachments = _existingAttachments.where((x) => x.id != a.id).toList());
    } catch (e) {
      if (mounted) MasterActions.showError(context, e);
    }
  }

  Future<void> _viewExisting(Attachment a) async {
    try {
      final bytes = await ref
          .read(lrRepositoryProvider)
          .downloadAttachmentBytes(_editing!.id, a.id);
      openFileInBrowser(bytes, a.mimeType ?? mimeForName(a.name), a.name);
    } catch (e) {
      if (mounted) MasterActions.showError(context, e);
    }
  }

  void _viewPicked(PlatformFile f) {
    final bytes = f.bytes;
    if (bytes == null) return;
    try {
      openFileInBrowser(bytes, mimeForName(f.name), f.name);
    } catch (e) {
      if (mounted) MasterActions.showError(context, e);
    }
  }

  String? _validateEwb(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length != 12) return 'EWB must be 12 digits';
    if (!RegExp(r'^\d{12}$').hasMatch(v)) return 'Digits only';
    return null;
  }

  Map<String, dynamic> _buildPayload(DateTime date) {
    return {
      'lr_date': date.toIso8601String().substring(0, 10),
      'customer_name': _customerCtrl.text.trim(),
      'consignor_id': _consignor!.id,
      'consignee_id': _consignee!.id,
      if (_vehicle != null) 'vehicle_id': _vehicle!.id,
      if (_transporter != null) 'transporter_id': _transporter!.id,
      if (_driver != null) 'driver_id': _driver!.id,
      if (_route != null) 'route_id': _route!.id,
      if (_route != null) 'from_city': _route!.fromCity,
      if (_route != null) 'to_city': _route!.toCity,
      'pay_type_id': _payType!.id,
      'delivery_type_id': _deliveryType!.id,
      'freight': _toDouble(_freightCtrl),
      'door_delivery': _toDouble(_doorCtrl),
      'handling': _toDouble(_handlingCtrl),
      'insurance': _toDouble(_insuranceCtrl),
      'advance': _toDouble(_advanceCtrl),
      'mathadi': _toDouble(_mathadiCtrl),
      'vistar_margin': _vistarMargin,
      if (_advancePaidBy != null) 'advance_paid_by_id': _advancePaidBy!.id,
      if (_tripLeadBy != null) 'trip_lead_by_id': _tripLeadBy!.id,
      if (_remarksCtrl.text.trim().isNotEmpty) 'remarks': _remarksCtrl.text.trim(),
      'invoice_items': _buildInvoiceItems(date),
    };
  }

  // Flatten invoices → part lines into the backend invoice_items array. Each
  // part line becomes one item carrying its parent invoice's number/ASN.
  List<Map<String, dynamic>> _buildInvoiceItems(DateTime date) {
    final items = <Map<String, dynamic>>[];
    final isoDate = date.toIso8601String();
    int parseInt(String s) => int.tryParse(s.trim()) ?? 0;
    double parseDbl(String s) => double.tryParse(s.trim()) ?? 0;
    for (final inv in _invoices) {
      final invNo = inv.invoiceNo.text.trim();
      final asn = inv.asn.text.trim();
      for (final p in inv.parts) {
        final desc = p.partDescription.text.trim();
        final nature = p.nature.text.trim();
        final packages = parseInt(p.packages.text);
        final qty = parseInt(p.quantity.text);
        final weight = parseDbl(p.weight.text);
        final value = parseDbl(p.value.text);
        final hasData = invNo.isNotEmpty ||
            asn.isNotEmpty ||
            desc.isNotEmpty ||
            nature.isNotEmpty ||
            packages > 0 ||
            qty > 0 ||
            weight > 0 ||
            value > 0 ||
            p.packageType != null;
        if (!hasData) continue;
        items.add({
          if (invNo.isNotEmpty) 'invoice_no': invNo,
          'invoice_date': isoDate,
          if (asn.isNotEmpty) 'asn': asn,
          if (desc.isNotEmpty) 'part_description': desc,
          'quantity': qty,
          'weight_kg': weight,
          'gross_value': value,
          'packages': packages,
          if (p.packageType != null) 'package_type_id': p.packageType!.id,
          if (nature.isNotEmpty) 'nature_of_goods': nature,
        });
      }
    }
    return items;
  }

  EwbInput? _buildEwb() {
    final number = _ewbCtrl.text.trim();
    if (number.isEmpty) return null;
    return EwbInput(
      number: number,
      expiryAt: DateTime.now().add(const Duration(days: 15)),
      loadTypeId: _ewbLoad?.id,
    );
  }

  Future<void> _uploadNewFiles(String lrId) async {
    if (_newFiles.isEmpty) return;
    final repo = ref.read(lrRepositoryProvider);
    for (final f in _newFiles) {
      await repo.uploadAttachment(
        lrId,
        fileName: f.name,
        bytes: f.bytes,
        // On web `path` is unavailable (and throws); we always have bytes there.
        filePath: f.bytes == null ? f.path : null,
      );
    }
  }

  // ---- Templates -----------------------------------------------------------

  /// A full snapshot of the current form, stored as a template payload.
  Map<String, dynamic> _formSnapshot() => {
        'customer_name': _customerCtrl.text,
        'consignor_id': _consignor?.id,
        'consignee_id': _consignee?.id,
        'vehicle_id': _vehicle?.id,
        'driver_id': _driver?.id,
        'transporter_id': _transporter?.id,
        'route_id': _route?.id,
        'pay_type_id': _payType?.id,
        'delivery_type_id': _deliveryType?.id,
        'advance_paid_by_id': _advancePaidBy?.id,
        'trip_lead_by_id': _tripLeadBy?.id,
        'ewb_load_type_id': _ewbLoad?.id,
        'ewb_number': _ewbCtrl.text,
        'invoices': [
          for (final inv in _invoices)
            {
              'invoice_no': inv.invoiceNo.text,
              'asn': inv.asn.text,
              'parts': [
                for (final p in inv.parts)
                  {
                    'part_description': p.partDescription.text,
                    'nature_of_goods': p.nature.text,
                    'packages': p.packages.text,
                    'quantity': p.quantity.text,
                    'weight_kg': p.weight.text,
                    'gross_value': p.value.text,
                    'package_type_id': p.packageType?.id,
                  }
              ],
            }
        ],
        'freight': _freightCtrl.text,
        'door_delivery': _doorCtrl.text,
        'handling': _handlingCtrl.text,
        'insurance': _insuranceCtrl.text,
        'advance': _advanceCtrl.text,
        'mathadi': _mathadiCtrl.text,
        'remarks': _remarksCtrl.text,
      };

  T? _byId<T>(List<T> list, dynamic id, String Function(T) idOf) {
    if (id == null) return null;
    for (final e in list) {
      if (idOf(e) == id) return e;
    }
    return null;
  }

  // ---- Vehicle selection / inline add --------------------------------------

  /// Selecting a vehicle auto-fills the driver + transporter it's linked to.
  /// (Call inside setState.)
  void _onVehicleSelected(Vehicle? v) {
    _vehicle = v;
    if (v == null) return;
    final drivers = ref.read(driversProvider);
    final transporters = ref.read(transportersProvider);
    final routes = ref.read(routesProvider);
    if (v.currentDriverId != null && v.currentDriverId!.isNotEmpty) {
      final d = _byId(drivers, v.currentDriverId, (x) => x.id);
      if (d != null) _driver = d;
    }
    if (v.transporterId != null && v.transporterId!.isNotEmpty) {
      final t = _byId(transporters, v.transporterId, (x) => x.id);
      if (t != null) _transporter = t;
    }
    if (v.routeId != null && v.routeId!.isNotEmpty) {
      final r = _byId(routes, v.routeId, (x) => x.id);
      if (r != null) _selectRoute(r);
    }
  }

  /// Selecting a route pre-fills Freight from the route's base rate (the
  /// operator can still edit it afterward). (Call inside setState.)
  void _selectRoute(RouteMaster? r) {
    _route = r;
    if (r != null && r.baseRate > 0) {
      _freightCtrl.text = r.baseRate.toStringAsFixed(0);
    }
  }

  Future<void> _addVehicleInline() async {
    const none = '(None)';
    final vehicleTypes = lookupList(_lookups, 'VEHICLE_TYPE');
    final drivers = ref.read(driversProvider);
    final transporters = ref.read(transportersProvider);

    await MasterFormDialog.show(
      context: context,
      title: 'New Vehicle',
      subtitle: 'Adds to your fleet and selects it on this LR',
      fields: [
        const FormFieldSpec(
            name: 'number',
            label: 'Vehicle Number',
            required: true,
            uppercase: true),
        FormFieldSpec(
          name: 'type',
          label: 'Vehicle Type',
          type: FieldType.dropdown,
          required: true,
          options: vehicleTypes.map((e) => e.label).toList(),
        ),
        const FormFieldSpec(
            name: 'capacity', label: 'Capacity (MT)', type: FieldType.number),
        FormFieldSpec(
          name: 'driver',
          label: 'Assigned Driver',
          type: FieldType.dropdown,
          options: [none, ...drivers.map((d) => d.name)],
          initialValue: none,
        ),
        FormFieldSpec(
          name: 'transporter',
          label: 'Transporter',
          type: FieldType.dropdown,
          options: [none, ...transporters.map((t) => t.name)],
          initialValue: none,
        ),
      ],
      onSave: (values) async {
        try {
          final typeLabel = values['type'] ?? '';
          final typeId = vehicleTypes
              .where((e) => e.label == typeLabel)
              .map((e) => e.id)
              .cast<String?>()
              .firstWhere((_) => true, orElse: () => null);
          final dName = values['driver'];
          final driver = (dName == null || dName == none)
              ? null
              : drivers
                  .where((d) => d.name == dName)
                  .cast<Driver?>()
                  .firstWhere((_) => true, orElse: () => null);
          final tName = values['transporter'];
          final transporter = (tName == null || tName == none)
              ? null
              : transporters
                  .where((t) => t.name == tName)
                  .cast<Transporter?>()
                  .firstWhere((_) => true, orElse: () => null);
          final created =
              await ref.read(vehiclesProvider.notifier).add(Vehicle(
                    id: const Uuid().v4(),
                    number: values['number'] ?? '',
                    typeId: typeId ?? '',
                    type: typeLabel,
                    capacityMt: double.tryParse(values['capacity'] ?? '') ?? 0,
                    transporterId: transporter?.id,
                    transporterName: transporter?.name ?? '',
                    currentDriverId: driver?.id,
                    driver: driver?.name ?? '',
                    driverMobile: driver?.mobile ?? '',
                  ));
          // Re-fetch so the new vehicle carries its nested type/driver/transporter.
          await ref.read(vehiclesProvider.notifier).refresh();
          final full = _byId(
                  ref.read(vehiclesProvider), created.id, (x) => x.id) ??
              created;
          setState(() => _onVehicleSelected(full));
          return true;
        } catch (e) {
          MasterActions.showError(context, e);
          return false;
        }
      },
    );
  }

  void _applyTemplate(LrTemplate t) {
    final p = t.payload;
    final consignors = ref.read(consignorsProvider);
    final consignees = ref.read(consigneesProvider);
    final vehicles = ref.read(vehiclesProvider);
    final transporters = ref.read(transportersProvider);
    final drivers = ref.read(driversProvider);
    final routes = ref.read(routesProvider);
    final lk = _lookups;
    String text(String key) => (p[key] ?? '').toString();

    setState(() {
      _appliedTemplate = t;
      _customerCtrl.text = text('customer_name');
      _consignor =
          _byId(consignors, p['consignor_id'], (c) => c.id) ?? _consignor;
      _consignee =
          _byId(consignees, p['consignee_id'], (c) => c.id) ?? _consignee;
      _vehicle = _byId(vehicles, p['vehicle_id'], (v) => v.id);
      _driver = _byId(drivers, p['driver_id'], (d) => d.id);
      _transporter = _byId(transporters, p['transporter_id'], (t) => t.id);
      _route = _byId(routes, p['route_id'], (r) => r.id);
      _payType = lookupById(lk, 'PAY_TYPE', p['pay_type_id'] as String?) ??
          _payType;
      _deliveryType =
          lookupById(lk, 'DELIVERY_TYPE', p['delivery_type_id'] as String?) ??
              _deliveryType;
      _advancePaidBy = lookupById(
              lk, 'ADVANCE_PAID_BY', p['advance_paid_by_id'] as String?) ??
          _advancePaidBy;
      _tripLeadBy =
          lookupById(lk, 'TRIP_LEAD_BY', p['trip_lead_by_id'] as String?) ??
              _tripLeadBy;
      _ewbLoad =
          lookupById(lk, 'EWB_LOAD_TYPE', p['ewb_load_type_id'] as String?) ??
              _ewbLoad;
      _ewbCtrl.text = text('ewb_number');
      _applyInvoicesSnapshot(p['invoices']);
      _freightCtrl.text = text('freight');
      _doorCtrl.text = text('door_delivery');
      _handlingCtrl.text = text('handling');
      _insuranceCtrl.text = text('insurance');
      _advanceCtrl.text = text('advance');
      _mathadiCtrl.text = text('mathadi');
      _remarksCtrl.text = text('remarks');
    });
    _showResult('Template "${t.title}" applied');
  }

  Future<void> _saveAsTemplate() async {
    final ctrl = TextEditingController(text: _appliedTemplate?.title ?? '');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as template'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Template title',
              hintText: 'e.g. Pune → Chakan · TBB'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    try {
      await ref
          .read(templatesProvider.notifier)
          .create(title, _formSnapshot());
      _showResult('Template "$title" saved');
    } catch (e) {
      if (mounted) MasterActions.showError(context, e);
    }
  }

  Future<void> _manageTemplates() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final templates = dialogRef.watch(templatesProvider);
          return AlertDialog(
            title: const Text('Manage templates'),
            content: SizedBox(
              width: 420,
              child: templates.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No templates yet. Use “Save as template”.'),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final t in templates)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.title),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rename',
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 18),
                                  onPressed: () => _renameTemplate(t),
                                ),
                                IconButton(
                                  tooltip: 'Update with current form',
                                  icon: const Icon(Icons.sync_outlined,
                                      size: 18),
                                  onPressed: () async {
                                    try {
                                      await dialogRef
                                          .read(templatesProvider.notifier)
                                          .update(t.id,
                                              payload: _formSnapshot());
                                      _showResult(
                                          'Template "${t.title}" updated');
                                    } catch (e) {
                                      if (mounted) {
                                        MasterActions.showError(context, e);
                                      }
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: AppColors.danger),
                                  onPressed: () async {
                                    try {
                                      await dialogRef
                                          .read(templatesProvider.notifier)
                                          .remove(t.id);
                                    } catch (e) {
                                      if (mounted) {
                                        MasterActions.showError(context, e);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _renameTemplate(LrTemplate t) async {
    final ctrl = TextEditingController(text: t.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename template'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null) return;
    try {
      await ref.read(templatesProvider.notifier).update(t.id, title: title);
    } catch (e) {
      if (mounted) MasterActions.showError(context, e);
    }
  }

  void _showResult(String message, {bool warning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            warning ? Colors.orange.shade800 : Colors.green.shade700,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(
              warning
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_consignor == null || _consignee == null) {
      MasterActions.showError(
        context,
        'Select a consignor and consignee (add them in Masters first).',
      );
      return;
    }
    if (_payType == null || _deliveryType == null) {
      MasterActions.showError(
        context,
        'Pay type and delivery type are required (lookups not loaded).',
      );
      return;
    }

    setState(() => _saving = true);
    final notifier = ref.read(lrListProvider.notifier);
    final ewb = _buildEwb();

    // 1) Save the LR itself. A failure here is fatal — stay on the form.
    LorryReceipt result;
    try {
      if (_isEdit && _editing != null) {
        result = await notifier.updateLr(
          _editing!.id,
          _editing!.version,
          _buildPayload(_editing!.date),
          ewb: ewb,
          existingEwbId: _editing!.ewb?.id,
          existingEwbVersion: 0,
        );
      } else {
        result = await notifier.create(
          _buildPayload(DateTime.now()),
          ewb: ewb,
          idempotencyKey: _idempotencyKey,
        );
      }
    } catch (e) {
      if (mounted) {
        MasterActions.showError(context, e);
        setState(() => _saving = false);
      }
      return;
    }

    // 2) Upload attachments — best-effort. Never re-create the LR over this.
    String? attachError;
    try {
      await _uploadNewFiles(result.id);
    } catch (e) {
      attachError = MasterActions.messageFor(e);
    }

    if (!mounted) return;
    final verb = _isEdit ? 'updated' : 'created';
    final aboveBase = _route != null &&
        _route!.baseRate > 0 &&
        _toDouble(_freightCtrl) > _route!.baseRate;
    final note =
        aboveBase ? ' · Freight above base rate — supervisor alerted' : '';
    if (attachError == null) {
      _showResult('LR ${result.number} $verb successfully$note',
          warning: aboveBase);
    } else {
      _showResult(
          'LR ${result.number} $verb, but an attachment failed: $attachError',
          warning: true);
    }
    context.go('/lrs/${result.id}');
  }

  @override
  Widget build(BuildContext context) {
    final consignors = ref.watch(consignorsProvider);
    final consignees = ref.watch(consigneesProvider);
    final vehicles = ref.watch(vehiclesProvider);
    final transporters = ref.watch(transportersProvider);
    final drivers = ref.watch(driversProvider);
    final routes = ref.watch(routesProvider);
    final lookups = ref.watch(lookupsMapProvider);

    final payTypes = lookupList(lookups, 'PAY_TYPE');
    final deliveryTypes = lookupList(lookups, 'DELIVERY_TYPE');
    final packageTypes = lookupList(lookups, 'PACKAGE_TYPE');
    final advancePaidByList = lookupList(lookups, 'ADVANCE_PAID_BY');
    final tripLeadByList = lookupList(lookups, 'TRIP_LEAD_BY');
    final ewbLoadList = lookupList(lookups, 'EWB_LOAD_TYPE');

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            AppTopbar(
              title: _isEdit
                  ? 'Edit LR ${_editing?.number ?? ''}'
                  : 'Create Lorry Receipt',
              subtitle: _isEdit
                  ? 'Updating existing LR'
                  : 'Number is auto-generated by the server on save',
              actions: [
                AppButton(
                  label: 'Cancel',
                  kind: BtnKind.ghost,
                  onPressed: () =>
                      context.go(_isEdit ? '/lrs/${widget.editId}' : '/lrs'),
                ),
                AppButton(
                  label: _saving
                      ? 'Saving…'
                      : (_isEdit ? 'Save Changes' : 'Save LR'),
                  icon: Icons.save_outlined,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _templateBar(),
                      const SizedBox(height: 20),
                      _customerCard(),
                      const SizedBox(height: 20),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionTitle(
                              icon: Icons.swap_horiz_rounded,
                              title: 'Parties',
                            ),
                            _grid(2, [
                              LabeledField(
                                label: 'Consignor/Sender',
                                required: true,
                                child: DropdownButtonFormField<Consignor>(
                                  initialValue: _consignor,
                                  isExpanded: true,
                                  hint: const Text('Select consignor'),
                                  items: [
                                    for (final c in consignors)
                                      DropdownMenuItem(
                                          value: c, child: Text(c.name)),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _consignor = v),
                                ),
                              ),
                              LabeledField(
                                label: 'Consignee/Receiver',
                                required: true,
                                child: DropdownButtonFormField<Consignee>(
                                  initialValue: _consignee,
                                  isExpanded: true,
                                  hint: const Text('Select consignee'),
                                  items: [
                                    for (final c in consignees)
                                      DropdownMenuItem(
                                          value: c, child: Text(c.name)),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _consignee = v),
                                ),
                              ),
                            ]),
                            if (_consignor != null) ...[
                              const SizedBox(height: 8),
                              _autoFillStrip(
                                '${_consignor!.address} · GST: ${_consignor!.gst}',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(
                              icon: Icons.local_shipping_outlined,
                              title: 'Vehicle & Route',
                              trailing: AppButton(
                                label: 'Add Vehicle',
                                icon: Icons.add_rounded,
                                kind: BtnKind.soft,
                                small: true,
                                onPressed: _addVehicleInline,
                              ),
                            ),
                            _grid(2, [
                              LabeledField(
                                label: 'Vehicle',
                                child: DropdownButtonFormField<Vehicle?>(
                                  initialValue: _vehicle,
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(
                                        value: null, child: Text('—')),
                                    for (final v in vehicles)
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text(v.type.isEmpty
                                            ? v.number
                                            : '${v.number} · ${v.type}'),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _onVehicleSelected(v)),
                                ),
                              ),
                              LabeledField(
                                label: 'Driver',
                                child: DropdownButtonFormField<Driver?>(
                                  initialValue: _driver,
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(
                                        value: null, child: Text('—')),
                                    for (final d in drivers)
                                      DropdownMenuItem(
                                          value: d, child: Text(d.name)),
                                  ],
                                  onChanged: (v) => setState(() => _driver = v),
                                ),
                              ),
                              LabeledField(
                                label: 'Transporter',
                                child: DropdownButtonFormField<Transporter?>(
                                  initialValue: _transporter,
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(
                                        value: null, child: Text('—')),
                                    for (final t in transporters)
                                      DropdownMenuItem(
                                          value: t, child: Text(t.name)),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _transporter = v),
                                ),
                              ),
                              LabeledField(
                                label: 'Route',
                                child: DropdownButtonFormField<RouteMaster?>(
                                  initialValue: _route,
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(
                                        value: null, child: Text('—')),
                                    for (final r in routes)
                                      DropdownMenuItem(
                                          value: r, child: Text(r.name)),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _selectRoute(v)),
                                ),
                              ),
                              LabeledField(
                                label: 'Delivery Type',
                                child: _lookupDropdown(
                                  value: _deliveryType,
                                  options: deliveryTypes,
                                  onChanged: (v) =>
                                      setState(() => _deliveryType = v),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _invoiceGoodsCard(packageTypes),
                      const SizedBox(height: 20),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionTitle(
                              icon: Icons.qr_code_2_rounded,
                              title: 'E-Way Bill',
                            ),
                            _grid(2, [
                              LabeledField(
                                label: 'EWB Number (12 digits)',
                                child: TextFormField(
                                  controller: _ewbCtrl,
                                  keyboardType: TextInputType.number,
                                  maxLength: 12,
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    hintText: 'Optional',
                                  ),
                                  validator: _validateEwb,
                                ),
                              ),
                              LabeledField(
                                label: 'Load Type',
                                child: _lookupDropdown(
                                  value: _ewbLoad,
                                  options: ewbLoadList,
                                  onChanged: (v) => setState(() => _ewbLoad = v),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _attachmentsCard(),
                      const SizedBox(height: 20),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionTitle(
                              icon: Icons.calculate_outlined,
                              title: 'Freight & Payment',
                            ),
                            _grid(3, [
                              LabeledField(
                                label: 'Freight',
                                child: TextFormField(
                                  controller: _freightCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Door Delivery',
                                child: TextFormField(
                                  controller: _doorCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Handling',
                                child: TextFormField(
                                  controller: _handlingCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Insurance',
                                child: TextFormField(
                                  controller: _insuranceCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Mathadi',
                                child: TextFormField(
                                  controller: _mathadiCtrl,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              LabeledField(
                                label: 'Advance',
                                child: TextFormField(
                                  controller: _advanceCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Advance Paid By',
                                child: _lookupDropdown(
                                  value: _advancePaidBy,
                                  options: advancePaidByList,
                                  onChanged: (v) =>
                                      setState(() => _advancePaidBy = v),
                                ),
                              ),
                              LabeledField(
                                label: 'Trip Lead By',
                                child: _lookupDropdown(
                                  value: _tripLeadBy,
                                  options: tripLeadByList,
                                  onChanged: (v) =>
                                      setState(() => _tripLeadBy = v),
                                ),
                              ),
                              LabeledField(
                                label: 'Pay Type',
                                required: true,
                                child: _lookupDropdown(
                                  value: _payType,
                                  options: payTypes,
                                  onChanged: (v) => setState(() => _payType = v),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            LabeledField(
                              label: 'Remarks',
                              child: TextFormField(
                                controller: _remarksCtrl,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    hintText: 'Optional notes'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.plum.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _summaryRow('GST (12%)', inr(_gst)),
                                  _summaryRow('Vistar Margin (auto)',
                                      inr(_vistarMargin)),
                                  _summaryRow('Total', inr(_total),
                                      emphasis: true),
                                  _summaryRow('Balance', inr(_balance),
                                      emphasis: true, color: AppColors.red),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _customerCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.person_outline, title: 'Customer'),
          LabeledField(
            label: 'Customer Name',
            child: TextFormField(
              controller: _customerCtrl,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(hintText: 'Billing / customer name'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateBar() {
    final templates = ref.watch(templatesProvider);
    LrTemplate? selected;
    if (_appliedTemplate != null) {
      for (final t in templates) {
        if (t.id == _appliedTemplate!.id) selected = t;
      }
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.bookmark_outline,
            title: 'LR Templates',
          ),
          LayoutBuilder(
            builder: (context, c) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: c.maxWidth >= 620 ? 340 : c.maxWidth,
                    child: DropdownButtonFormField<LrTemplate>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select a template to pre-fill',
                        prefixIcon:
                            Icon(Icons.bookmark_added_outlined, size: 18),
                      ),
                      hint: const Text('Select a template'),
                      items: [
                        for (final t in templates)
                          DropdownMenuItem(
                            value: t,
                            child:
                                Text(t.title, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (t) {
                        if (t != null) _applyTemplate(t);
                      },
                    ),
                  ),
                  AppButton(
                    label: 'Save as Template',
                    icon: Icons.save_alt_outlined,
                    kind: BtnKind.soft,
                    small: true,
                    onPressed: _saveAsTemplate,
                  ),
                  AppButton(
                    label: 'Manage',
                    icon: Icons.settings_outlined,
                    kind: BtnKind.ghost,
                    small: true,
                    onPressed: _manageTemplates,
                  ),
                ],
              );
            },
          ),
          if (templates.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'No templates yet — fill the form and tap “Save as Template” to reuse it later.',
              style: TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lookupDropdown({
    required LookupValue? value,
    required List<LookupValue> options,
    required ValueChanged<LookupValue?> onChanged,
  }) {
    return DropdownButtonFormField<LookupValue>(
      initialValue: value,
      isExpanded: true,
      hint: const Text('Select'),
      items: [
        for (final v in options)
          DropdownMenuItem(value: v, child: Text(v.label)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _invoiceGoodsCard(List<LookupValue> packageTypes) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.inventory_2_outlined,
            title: 'Invoice & Goods',
            trailing: AppButton(
              label: 'Add Invoice',
              icon: Icons.add_rounded,
              kind: BtnKind.soft,
              small: true,
              onPressed: () => setState(() => _invoices.add(_InvoiceForm())),
            ),
          ),
          for (int i = 0; i < _invoices.length; i++)
            _invoiceBlock(i, packageTypes),
        ],
      ),
    );
  }

  Widget _invoiceBlock(int i, List<LookupValue> packageTypes) {
    final inv = _invoices[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Invoice ${i + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.ink)),
              const Spacer(),
              if (_invoices.length > 1)
                IconButton(
                  tooltip: 'Remove invoice',
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppColors.danger),
                  onPressed: () => setState(() {
                    _invoices[i].dispose();
                    _invoices.removeAt(i);
                  }),
                ),
            ],
          ),
          _grid(2, [
            LabeledField(
              label: 'Invoice No',
              child: TextFormField(controller: inv.invoiceNo),
            ),
            LabeledField(
              label: 'ASN (optional)',
              child: TextFormField(controller: inv.asn),
            ),
          ]),
          const SizedBox(height: 10),
          for (int j = 0; j < inv.parts.length; j++)
            _partBlock(inv, j, packageTypes),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add Part Description',
              icon: Icons.add_rounded,
              kind: BtnKind.ghost,
              small: true,
              onPressed: () => setState(() => inv.parts.add(_PartLineForm())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _partBlock(_InvoiceForm inv, int j, List<LookupValue> packageTypes) {
    final p = inv.parts[j];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Part ${j + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate,
                      fontSize: 12.5)),
              const Spacer(),
              if (inv.parts.length > 1)
                IconButton(
                  tooltip: 'Remove part',
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.slate),
                  onPressed: () => setState(() {
                    inv.parts[j].dispose();
                    inv.parts.removeAt(j);
                  }),
                ),
            ],
          ),
          _grid(3, [
            LabeledField(
              label: 'Part Description',
              child: TextFormField(controller: p.partDescription),
            ),
            LabeledField(
              label: 'Nature of Goods',
              child: TextFormField(controller: p.nature),
            ),
            LabeledField(
              label: 'Package Type',
              child: _lookupDropdown(
                value: p.packageType,
                options: packageTypes,
                onChanged: (v) => setState(() => p.packageType = v),
              ),
            ),
            LabeledField(
              label: 'No of Packages',
              child: TextFormField(
                controller: p.packages,
                keyboardType: TextInputType.number,
              ),
            ),
            LabeledField(
              label: 'Quantity',
              child: TextFormField(
                controller: p.quantity,
                keyboardType: TextInputType.number,
              ),
            ),
            LabeledField(
              label: 'Weight (kg)',
              child: TextFormField(
                controller: p.weight,
                keyboardType: TextInputType.number,
              ),
            ),
            LabeledField(
              label: 'Gross Value',
              child: TextFormField(
                controller: p.value,
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _attachmentsCard() {
    final hasAny = _existingAttachments.isNotEmpty || _newFiles.isNotEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: Icons.attach_file_rounded,
            title: 'Invoice Attachments',
            trailing: AppButton(
              label: 'Upload',
              icon: Icons.upload_file_outlined,
              kind: BtnKind.soft,
              small: true,
              onPressed: _pickInvoices,
            ),
          ),
          if (!hasAny)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.mist,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      color: AppColors.slate, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'PDF, JPG, PNG or Excel. Files upload to the server when you save.',
                      style: TextStyle(color: AppColors.slate, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (final a in _existingAttachments)
                  _fileRow(
                    title: a.name,
                    subtitle: '${a.sizeLabel} · uploaded',
                    onView: () => _viewExisting(a),
                    onRemove: () => _removeExistingAttachment(a),
                  ),
                for (final f in _newFiles)
                  _fileRow(
                    title: f.name,
                    subtitle:
                        '${(f.size / 1024).toStringAsFixed(1)} KB · pending upload',
                    onView: f.bytes != null ? () => _viewPicked(f) : null,
                    onRemove: () => setState(() => _newFiles.remove(f)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _fileRow({
    required String title,
    required String subtitle,
    VoidCallback? onView,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              size: 18, color: AppColors.plum),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.slate, fontSize: 11.5)),
              ],
            ),
          ),
          if (onView != null)
            IconButton(
              tooltip: 'View',
              icon: const Icon(Icons.visibility_outlined,
                  size: 18, color: AppColors.plum),
              onPressed: onView,
            ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.slate),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _autoFillStrip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: AppColors.plum),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.plum,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(int cols, List<Widget> children) {
    return LayoutBuilder(
      builder: (context, c) {
        final actualCols =
            c.maxWidth >= 700 ? cols : (c.maxWidth >= 480 ? 2 : 1);
        const spacing = 14.0;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: [
            for (final child in children)
              SizedBox(
                width: (c.maxWidth - spacing * (actualCols - 1)) / actualCols,
                child: child,
              ),
          ],
        );
      },
    );
  }

  Widget _summaryRow(String label, String value,
      {bool emphasis = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.slate,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppColors.ink,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
