import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/consignee.dart';
import '../../../shared/models/consignor.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../lr/widgets/lr_copy_view.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/system_config_provider.dart';

class LrFormatScreen extends ConsumerStatefulWidget {
  const LrFormatScreen({super.key});

  @override
  ConsumerState<LrFormatScreen> createState() => _LrFormatScreenState();
}

class _LrFormatScreenState extends ConsumerState<LrFormatScreen> {
  late TextEditingController _companyCtrl;
  late TextEditingController _taglineCtrl;
  late TextEditingController _termsCtrl;
  late TextEditingController _footerCtrl;

  late bool _showMargin;
  late bool _showMathadi;
  late bool _showInsurance;
  late bool _showEwb;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(systemConfigProvider);
    _companyCtrl = TextEditingController(text: cfg.companyName);
    _taglineCtrl = TextEditingController(text: cfg.companyTagline);
    _termsCtrl = TextEditingController(text: cfg.termsText);
    _footerCtrl = TextEditingController(text: cfg.footerText);
    _showMargin = cfg.showVistarMargin;
    _showMathadi = cfg.showMathadi;
    _showInsurance = cfg.showInsurance;
    _showEwb = cfg.showEwb;
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _taglineCtrl.dispose();
    _termsCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cfg = ref.read(systemConfigProvider);
    final next = cfg.copyWith(
      companyName: _companyCtrl.text.trim(),
      companyTagline: _taglineCtrl.text.trim(),
      termsText: _termsCtrl.text.trim(),
      footerText: _footerCtrl.text.trim(),
      showVistarMargin: _showMargin,
      showMathadi: _showMathadi,
      showInsurance: _showInsurance,
      showEwb: _showEwb,
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(systemConfigProvider.notifier).saveFormat(next);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('LR format updated')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  void _reset() {
    const def = SystemConfig();
    ref.read(systemConfigProvider.notifier).update(def);
    setState(() {
      _companyCtrl.text = def.companyName;
      _taglineCtrl.text = def.companyTagline;
      _termsCtrl.text = def.termsText;
      _footerCtrl.text = def.footerText;
      _showMargin = def.showVistarMargin;
      _showMathadi = def.showMathadi;
      _showInsurance = def.showInsurance;
      _showEwb = def.showEwb;
    });
  }

  LorryReceipt _previewLr() {
    final now = DateTime.now();
    const consignor = Consignor(
      id: 'preview',
      name: 'LUMINAZ SAFETY GLASS',
      gst: '27AABCL1234M1Z5',
      city: 'Pune',
      address: 'Plot 14, MIDC Bhosari, Pune 411026',
      contact: 'R. Kale',
      mobile: '98220 11223',
      email: 'dispatch@luminaz.in',
    );
    const consignee = Consignee(
      id: 'preview',
      name: 'TATA AUTOCOMP SYSTEMS',
      gst: '27AAACT3456Q1Z2',
      location: 'Chakan, Pune',
      address: 'Gate 3, Chakan Industrial Area',
      contact: 'P. Joshi',
      mobile: '98900 12345',
    );
    const vehicle = Vehicle(
      id: 'preview',
      number: 'MH12 AB 4567',
      type: 'Truck',
      capacityMt: 10,
      driver: 'Ramesh Pawar',
      driverMobile: '90110 23344',
    );
    const transporter = Transporter(
        id: 'preview',
        name: 'Vistar Own Fleet',
        pan: 'AABCV1234M',
        tds: 'Yes');
    return LorryReceipt(
      id: 'preview',
      number: 'VLL/25/05/PREVIEW',
      date: now,
      enteredBy: 'admin',
      consignor: consignor,
      consignee: consignee,
      vehicle: vehicle,
      transporter: transporter,
      route: 'Pune → Chakan',
      fromCity: 'Pune',
      toCity: 'Chakan',
      items: [
        InvoiceItem(
          invoiceNo: 'INV/1001',
          invoiceDate: now,
          asn: 'ASN5001',
          partDescription: 'Sample part description',
          quantity: 50,
          weight: 1200,
          grossValue: 250000,
          packages: 12,
          packageType: 'Pallet',
          natureOfGoods: 'Industrial Goods',
        ),
      ],
      freight: const FreightDetails(
        freight: 8000,
        doorDelivery: 500,
        handling: 300,
        insurance: 150,
        gst: 1060,
        advance: 2000,
        mathadi: 350,
        vistarMargin: 1500,
      ),
      ewb: EwayBill(
        number: '481299112233',
        expiry: now.add(const Duration(days: 7)),
      ),
      payType: PayType.tbb,
      deliveryType: DeliveryType.doorDelivery,
      status: LrStatus.booked,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'LR Format',
            subtitle: 'Edit header, terms, footer & optional fields',
            actions: [
              AppButton(
                label: 'Reset defaults',
                kind: BtnKind.ghost,
                onPressed: _reset,
              ),
              AppButton(
                label: 'Save',
                icon: Icons.save_outlined,
                onPressed: _save,
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 1100;
                  final left = _buildEditor();
                  final right = _buildPreview();
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 20),
                        Expanded(flex: 7, child: right),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 20), right],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                icon: Icons.business_outlined,
                title: 'Header',
              ),
              LabeledField(
                label: 'Company Name',
                required: true,
                child: TextField(
                  controller: _companyCtrl,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: 'Tagline (printed below logo)',
                child: TextField(
                  controller: _taglineCtrl,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                icon: Icons.gavel_outlined,
                title: 'Terms & Footer',
              ),
              LabeledField(
                label: 'Terms & Conditions text',
                child: TextField(
                  controller: _termsCtrl,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: 'Footer (above signatory)',
                child: TextField(
                  controller: _footerCtrl,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                icon: Icons.tune_rounded,
                title: 'Optional fields on print',
              ),
              _toggle(
                'Show E-Way Bill block',
                _showEwb,
                (v) => setState(() => _showEwb = v),
              ),
              _toggle(
                'Show Insurance line',
                _showInsurance,
                (v) => setState(() => _showInsurance = v),
              ),
              _toggle(
                'Show Mathadi charge',
                _showMathadi,
                (v) => setState(() => _showMathadi = v),
              ),
              _toggle(
                'Show Vistar Margin (internal copies)',
                _showMargin,
                (v) => setState(() => _showMargin = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          icon: Icons.preview_outlined,
          title: 'Live preview',
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.mist,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 794),
            child: FittedBox(
              alignment: Alignment.topCenter,
              child: LrCopyView(
                lr: _previewLr(),
                copyName: 'Office Copy',
                format: LrCopyFormat(
                  companyName: _companyCtrl.text,
                  tagline: _taglineCtrl.text,
                  terms: _termsCtrl.text,
                  footer: _footerCtrl.text,
                  showEwb: _showEwb,
                  showInsurance: _showInsurance,
                  showMathadi: _showMathadi,
                  showVistarMargin: _showMargin,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Preview reflects current edits. Save to apply across all print copies.',
          style: TextStyle(color: AppColors.slate, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13.5)),
      activeThumbColor: AppColors.plum,
    );
  }
}

