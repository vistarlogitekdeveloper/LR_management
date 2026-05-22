import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/mock_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/consignee.dart';
import '../../../shared/models/consignor.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../admin/providers/audit_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../masters/providers/master_providers.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';

class CreateLrScreen extends ConsumerStatefulWidget {
  final String? editId;
  const CreateLrScreen({super.key, this.editId});

  @override
  ConsumerState<CreateLrScreen> createState() => _CreateLrScreenState();
}

class _CreateLrScreenState extends ConsumerState<CreateLrScreen> {
  final _formKey = GlobalKey<FormState>();

  Consignor? _consignor;
  Consignee? _consignee;
  Vehicle? _vehicle;
  Transporter? _transporter;
  String? _route;
  PayType _payType = PayType.tbb;
  DeliveryType _deliveryType = DeliveryType.doorDelivery;
  LrStatus _status = LrStatus.booked;

  final _invoiceCtrl = TextEditingController();
  final _asnCtrl = TextEditingController();
  final _partsCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '50');
  final _weightCtrl = TextEditingController(text: '1200');
  final _valueCtrl = TextEditingController(text: '250000');
  final _packagesCtrl = TextEditingController(text: '12');
  String _packageType = 'Pallet';
  final _natureCtrl = TextEditingController(text: 'Industrial Goods');

  final _freightCtrl = TextEditingController(text: '8000');
  final _doorCtrl = TextEditingController(text: '0');
  final _handlingCtrl = TextEditingController(text: '300');
  final _insuranceCtrl = TextEditingController(text: '0');
  final _advanceCtrl = TextEditingController(text: '0');
  final _mathadiCtrl = TextEditingController(text: '0');
  final _marginCtrl = TextEditingController(text: '1500');

  final _ewbCtrl = TextEditingController();
  String _ewbLoad = 'Full Load';
  String _advancePaidBy = 'Vistar';
  String _tripLeadBy = 'Operations';

  bool _isEdit = false;
  LorryReceipt? _editing;

  @override
  void initState() {
    super.initState();
    if (widget.editId != null) {
      _isEdit = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  void _hydrate() {
    final consignors = ref.read(consignorsProvider);
    final consignees = ref.read(consigneesProvider);
    final vehicles = ref.read(vehiclesProvider);
    final transporters = ref.read(transportersProvider);

    if (_isEdit) {
      final lr = ref.read(lrByIdProvider(widget.editId!));
      if (lr == null) return;
      _editing = lr;
      setState(() {
        _consignor = consignors.firstWhere(
          (c) => c.id == lr.consignor.id,
          orElse: () => lr.consignor,
        );
        _consignee = consignees.firstWhere(
          (c) => c.id == lr.consignee.id,
          orElse: () => lr.consignee,
        );
        _vehicle = vehicles.firstWhere(
          (v) => v.id == lr.vehicle.id,
          orElse: () => lr.vehicle,
        );
        _transporter = transporters.firstWhere(
          (t) => t.id == lr.transporter.id,
          orElse: () => lr.transporter,
        );
        _route = lr.route;
        _payType = lr.payType;
        _deliveryType = lr.deliveryType;
        _status = lr.status;
        if (lr.items.isNotEmpty) {
          final i = lr.items.first;
          _invoiceCtrl.text = i.invoiceNo;
          _asnCtrl.text = i.asn;
          _partsCtrl.text = i.partDescription;
          _qtyCtrl.text = '${i.quantity}';
          _weightCtrl.text = i.weight.toStringAsFixed(0);
          _valueCtrl.text = i.grossValue.toStringAsFixed(0);
          _packagesCtrl.text = '${i.packages}';
          _packageType = i.packageType;
          _natureCtrl.text = i.natureOfGoods;
        }
        _freightCtrl.text = lr.freight.freight.toStringAsFixed(0);
        _doorCtrl.text = lr.freight.doorDelivery.toStringAsFixed(0);
        _handlingCtrl.text = lr.freight.handling.toStringAsFixed(0);
        _insuranceCtrl.text = lr.freight.insurance.toStringAsFixed(0);
        _advanceCtrl.text = lr.freight.advance.toStringAsFixed(0);
        _mathadiCtrl.text = lr.freight.mathadi.toStringAsFixed(0);
        _marginCtrl.text = lr.freight.vistarMargin.toStringAsFixed(0);
        _advancePaidBy = lr.freight.advancePaidBy;
        _tripLeadBy = lr.freight.tripLeadBy;
        _ewbCtrl.text = lr.ewb?.number ?? '';
        _ewbLoad = lr.ewb?.loadType ?? 'Full Load';
      });
    } else {
      setState(() {
        _consignor = consignors.isNotEmpty ? consignors.first : null;
        _consignee = consignees.isNotEmpty ? consignees.first : null;
        _vehicle = vehicles.isNotEmpty ? vehicles.first : null;
        _transporter = transporters.isNotEmpty ? transporters.first : null;
        _route = MockData.routes.first;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _invoiceCtrl,
      _asnCtrl,
      _partsCtrl,
      _qtyCtrl,
      _weightCtrl,
      _valueCtrl,
      _packagesCtrl,
      _natureCtrl,
      _freightCtrl,
      _doorCtrl,
      _handlingCtrl,
      _insuranceCtrl,
      _advanceCtrl,
      _mathadiCtrl,
      _marginCtrl,
      _ewbCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _toDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;
  int _toInt(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  double get _gst {
    final base = _toDouble(_freightCtrl) +
        _toDouble(_doorCtrl) +
        _toDouble(_handlingCtrl);
    return (base * 0.12).roundToDouble();
  }

  double get _total =>
      _toDouble(_freightCtrl) +
      _toDouble(_doorCtrl) +
      _toDouble(_handlingCtrl) +
      _toDouble(_insuranceCtrl) +
      _gst;

  double get _balance => _total - _toDouble(_advanceCtrl);

  String? _validateEwb(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length != 12) return 'EWB must be 12 digits';
    if (!RegExp(r'^\d{12}$').hasMatch(v)) return 'Digits only';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_consignor == null ||
        _consignee == null ||
        _vehicle == null ||
        _transporter == null ||
        _route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill required master fields')),
      );
      return;
    }
    final user = ref.read(currentUserProvider);
    final now = DateTime.now();
    final parts = _route!.split(' → ');

    final freight = FreightDetails(
      freight: _toDouble(_freightCtrl),
      doorDelivery: _toDouble(_doorCtrl),
      handling: _toDouble(_handlingCtrl),
      insurance: _toDouble(_insuranceCtrl),
      gst: _gst,
      advance: _toDouble(_advanceCtrl),
      mathadi: _toDouble(_mathadiCtrl),
      vistarMargin: _toDouble(_marginCtrl),
      advancePaidBy: _advancePaidBy,
      tripLeadBy: _tripLeadBy,
    );

    final ewb = _ewbCtrl.text.trim().isNotEmpty
        ? EwayBill(
            number: _ewbCtrl.text.trim(),
            expiry: now.add(const Duration(days: 7)),
            loadType: _ewbLoad,
          )
        : null;

    final item = InvoiceItem(
      invoiceNo: _invoiceCtrl.text.isEmpty
          ? 'INV/${now.millisecondsSinceEpoch % 10000}'
          : _invoiceCtrl.text,
      invoiceDate: _isEdit ? (_editing!.items.first.invoiceDate) : now,
      asn: _asnCtrl.text,
      partDescription: _partsCtrl.text,
      quantity: _toInt(_qtyCtrl),
      weight: _toDouble(_weightCtrl),
      grossValue: _toDouble(_valueCtrl),
      packages: _toInt(_packagesCtrl),
      packageType: _packageType,
      natureOfGoods: _natureCtrl.text,
    );

    if (_isEdit && _editing != null) {
      final updated = _editing!.copyWith(
        freight: freight,
        ewb: ewb,
        payType: _payType,
        deliveryType: _deliveryType,
        status: _status,
      );
      final withItems = LorryReceipt(
        id: updated.id,
        number: updated.number,
        date: updated.date,
        enteredBy: updated.enteredBy,
        consignor: _consignor!,
        consignee: _consignee!,
        vehicle: _vehicle!,
        transporter: _transporter!,
        route: _route!,
        fromCity: parts[0],
        toCity: parts.length > 1 ? parts[1] : parts[0],
        items: [item],
        freight: freight,
        ewb: ewb,
        payType: _payType,
        deliveryType: _deliveryType,
        status: _status,
        remarks: updated.remarks,
      );
      ref.read(lrListProvider.notifier).update(withItems);
      ref.read(auditProvider.notifier).log(
            user: user?.username ?? 'system',
            action: 'UPDATE',
            entity: 'LR',
            entityRef: withItems.number,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LR ${withItems.number} updated')),
      );
      context.go('/lrs/${withItems.id}');
    } else {
      final lrs = ref.read(lrListProvider);
      final next = (lrs.length + 56).toString().padLeft(5, '0');
      final number =
          'VLL/${now.year.toString().substring(2)}/${now.month.toString().padLeft(2, '0')}/$next';
      final lr = LorryReceipt(
        id: 'LR${DateTime.now().millisecondsSinceEpoch}',
        number: number,
        date: now,
        enteredBy: user?.username ?? 'system',
        consignor: _consignor!,
        consignee: _consignee!,
        vehicle: _vehicle!,
        transporter: _transporter!,
        route: _route!,
        fromCity: parts[0],
        toCity: parts.length > 1 ? parts[1] : parts[0],
        items: [item],
        freight: freight,
        ewb: ewb,
        payType: _payType,
        deliveryType: _deliveryType,
        status: _status,
      );
      ref.read(lrListProvider.notifier).add(lr);
      ref.read(auditProvider.notifier).log(
            user: user?.username ?? 'system',
            action: 'CREATE',
            entity: 'LR',
            entityRef: lr.number,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LR ${lr.number} created')),
      );
      context.go('/lrs/${lr.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final consignors = ref.watch(consignorsProvider);
    final consignees = ref.watch(consigneesProvider);
    final vehicles = ref.watch(vehiclesProvider);
    final transporters = ref.watch(transportersProvider);
    final routes = ref.watch(routesProvider);
    final routeNames = routes.isEmpty
        ? MockData.routes
        : routes.map((r) => r.name).toList();

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
                  : 'Number will be auto-generated on save',
              actions: [
                AppButton(
                  label: 'Cancel',
                  kind: BtnKind.ghost,
                  onPressed: () =>
                      context.go(_isEdit ? '/lrs/${widget.editId}' : '/lrs'),
                ),
                AppButton(
                  label: _isEdit ? 'Save Changes' : 'Save LR',
                  icon: Icons.save_outlined,
                  onPressed: _save,
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                              label: 'Consignor',
                              required: true,
                              child: DropdownButtonFormField<Consignor>(
                                initialValue: _consignor,
                                isExpanded: true,
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
                              label: 'Consignee',
                              required: true,
                              child: DropdownButtonFormField<Consignee>(
                                initialValue: _consignee,
                                isExpanded: true,
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
                          const SectionTitle(
                            icon: Icons.local_shipping_outlined,
                            title: 'Vehicle & Route',
                          ),
                          _grid(2, [
                            LabeledField(
                              label: 'Vehicle',
                              required: true,
                              child: DropdownButtonFormField<Vehicle>(
                                initialValue: _vehicle,
                                isExpanded: true,
                                items: [
                                  for (final v in vehicles)
                                    DropdownMenuItem(
                                      value: v,
                                      child: Text('${v.number} · ${v.type}'),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _vehicle = v),
                              ),
                            ),
                            LabeledField(
                              label: 'Transporter',
                              child: DropdownButtonFormField<Transporter>(
                                initialValue: _transporter,
                                isExpanded: true,
                                items: [
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
                              required: true,
                              child: DropdownButtonFormField<String>(
                                initialValue: _route,
                                isExpanded: true,
                                items: [
                                  for (final r in routeNames)
                                    DropdownMenuItem(value: r, child: Text(r)),
                                ],
                                onChanged: (v) => setState(() => _route = v),
                              ),
                            ),
                            LabeledField(
                              label: 'Delivery Type',
                              child: DropdownButtonFormField<DeliveryType>(
                                initialValue: _deliveryType,
                                isExpanded: true,
                                items: [
                                  for (final d in DeliveryType.values)
                                    DropdownMenuItem(
                                        value: d, child: Text(d.label)),
                                ],
                                onChanged: (v) => setState(
                                    () => _deliveryType = v ?? _deliveryType),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionTitle(
                            icon: Icons.inventory_2_outlined,
                            title: 'Invoice & Goods',
                          ),
                          _grid(3, [
                            LabeledField(
                              label: 'Invoice No',
                              child: TextFormField(controller: _invoiceCtrl),
                            ),
                            LabeledField(
                              label: 'ASN',
                              child: TextFormField(controller: _asnCtrl),
                            ),
                            LabeledField(
                              label: 'Nature of Goods',
                              child: TextFormField(controller: _natureCtrl),
                            ),
                            LabeledField(
                              label: 'No of Packages',
                              child: TextFormField(
                                controller: _packagesCtrl,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            LabeledField(
                              label: 'Package Type',
                              child: DropdownButtonFormField<String>(
                                initialValue: _packageType,
                                isExpanded: true,
                                items: [
                                  for (final p in MockData.packageTypes)
                                    DropdownMenuItem(value: p, child: Text(p)),
                                ],
                                onChanged: (v) => setState(
                                    () => _packageType = v ?? _packageType),
                              ),
                            ),
                            LabeledField(
                              label: 'Quantity',
                              child: TextFormField(
                                controller: _qtyCtrl,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            LabeledField(
                              label: 'Weight (kg)',
                              child: TextFormField(
                                controller: _weightCtrl,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            LabeledField(
                              label: 'Gross Value',
                              child: TextFormField(
                                controller: _valueCtrl,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            LabeledField(
                              label: 'Part Description',
                              child: TextFormField(controller: _partsCtrl),
                            ),
                          ]),
                        ],
                      ),
                    ),
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
                              child: DropdownButtonFormField<String>(
                                initialValue: _ewbLoad,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Full Load',
                                      child: Text('Full Load')),
                                  DropdownMenuItem(
                                      value: 'Part Load',
                                      child: Text('Part Load')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _ewbLoad = v ?? _ewbLoad),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
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
                              label: 'Vistar Margin',
                              child: TextFormField(
                                controller: _marginCtrl,
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
                              child: DropdownButtonFormField<String>(
                                initialValue: _advancePaidBy,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Vistar', child: Text('Vistar')),
                                  DropdownMenuItem(
                                      value: 'Customer',
                                      child: Text('Customer')),
                                ],
                                onChanged: (v) => setState(
                                    () => _advancePaidBy = v ?? _advancePaidBy),
                              ),
                            ),
                            LabeledField(
                              label: 'Trip Lead By',
                              child: DropdownButtonFormField<String>(
                                initialValue: _tripLeadBy,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Operations',
                                      child: Text('Operations')),
                                  DropdownMenuItem(
                                      value: 'Sales', child: Text('Sales')),
                                ],
                                onChanged: (v) => setState(
                                    () => _tripLeadBy = v ?? _tripLeadBy),
                              ),
                            ),
                            LabeledField(
                              label: 'Pay Type',
                              child: DropdownButtonFormField<PayType>(
                                initialValue: _payType,
                                isExpanded: true,
                                items: [
                                  for (final p in PayType.values)
                                    DropdownMenuItem(
                                        value: p, child: Text(p.label)),
                                ],
                                onChanged: (v) =>
                                    setState(() => _payType = v ?? _payType),
                              ),
                            ),
                            if (_isEdit)
                              LabeledField(
                                label: 'Status',
                                child: DropdownButtonFormField<LrStatus>(
                                  initialValue: _status,
                                  isExpanded: true,
                                  items: [
                                    for (final s in LrStatus.values)
                                      DropdownMenuItem(
                                          value: s, child: Text(s.label)),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _status = v ?? _status),
                                ),
                              ),
                          ]),
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
                width:
                    (c.maxWidth - spacing * (actualCols - 1)) / actualCols,
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
