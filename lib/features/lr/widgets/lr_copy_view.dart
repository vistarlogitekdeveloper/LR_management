import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/brand_logo.dart';

class LrCopyFormat {
  final String companyName;
  final String tagline;
  final String terms;
  final String footer;
  final bool showEwb;
  final bool showInsurance;
  final bool showMathadi;
  final bool showVistarMargin;

  const LrCopyFormat({
    required this.companyName,
    required this.tagline,
    required this.terms,
    required this.footer,
    required this.showEwb,
    required this.showInsurance,
    required this.showMathadi,
    required this.showVistarMargin,
  });
}

class LrCopyView extends StatelessWidget {
  final LorryReceipt lr;
  final String copyName;
  final LrCopyFormat format;

  const LrCopyView({
    super.key,
    required this.lr,
    required this.copyName,
    required this.format,
  });

  bool get _isInternalCopy =>
      copyName.toLowerCase().contains('office') ||
      copyName.toLowerCase().contains('lorry');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 794, // A4 width @ 96dpi
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 14),
          _parties(),
          const SizedBox(height: 10),
          _vehicleRow(),
          const SizedBox(height: 10),
          _goodsTable(),
          const SizedBox(height: 10),
          _freightBlock(),
          const SizedBox(height: 12),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandLogo(height: 38),
              const SizedBox(height: 4),
              Text(
                format.tagline,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.slate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.plum,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                copyName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'LR No: ${lr.number}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              'Date: ${formatDate(lr.date)}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.slate),
            ),
          ],
        ),
      ],
    );
  }

  Widget _parties() {
    return _bordered(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Consignor'),
                  Text(lr.consignor.name,
                      style:
                          const TextStyle(fontWeight: FontWeight.w800)),
                  Text(lr.consignor.address,
                      style: const TextStyle(fontSize: 11.5)),
                  Text('GST: ${lr.consignor.gst}',
                      style: const TextStyle(fontSize: 11.5)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 80, color: AppColors.ink),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Consignee'),
                  Text(lr.consignee.name,
                      style:
                          const TextStyle(fontWeight: FontWeight.w800)),
                  Text(lr.consignee.address,
                      style: const TextStyle(fontSize: 11.5)),
                  Text('GST: ${lr.consignee.gst}',
                      style: const TextStyle(fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleRow() {
    return _bordered(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 24,
          runSpacing: 6,
          children: [
            _kv('Vehicle No', lr.vehicle.number),
            _kv('Type', lr.vehicle.type),
            _kv('Capacity', lr.vehicle.capacity),
            _kv('Driver',
                '${lr.vehicle.driver} (${lr.vehicle.driverMobile})'),
            _kv('Route', lr.route),
            _kv('P-Mark', lr.vehicle.pmark),
            _kv('Delivery', lr.deliveryType.label),
          ],
        ),
      ),
    );
  }

  Widget _goodsTable() {
    return _bordered(
      child: Column(
        children: [
          _tableHeaderRow(),
          for (final item in lr.items) _tableDataRow(item),
        ],
      ),
    );
  }

  Widget _tableHeaderRow() {
    return Container(
      color: AppColors.plum.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Invoice', style: _hStyle)),
          Expanded(flex: 1, child: Text('ASN', style: _hStyle)),
          Expanded(flex: 3, child: Text('Description', style: _hStyle)),
          Expanded(flex: 1, child: Text('Pkg', style: _hStyle)),
          Expanded(flex: 1, child: Text('Qty', style: _hStyle)),
          Expanded(flex: 1, child: Text('Wt', style: _hStyle)),
          Expanded(flex: 2, child: Text('Value', style: _hStyle)),
        ],
      ),
    );
  }

  Widget _tableDataRow(InvoiceItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              flex: 2,
              child: Text(item.invoiceNo,
                  style: const TextStyle(fontSize: 11.5))),
          Expanded(
              flex: 1,
              child:
                  Text(item.asn, style: const TextStyle(fontSize: 11.5))),
          Expanded(
              flex: 3,
              child: Text(item.partDescription,
                  style: const TextStyle(fontSize: 11.5))),
          Expanded(
              flex: 1,
              child: Text('${item.packages} ${item.packageType}',
                  style: const TextStyle(fontSize: 11.5))),
          Expanded(
              flex: 1,
              child: Text('${item.quantity}',
                  style: const TextStyle(fontSize: 11.5))),
          Expanded(
              flex: 1,
              child: Text(item.weight.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 11.5))),
          Expanded(
              flex: 2,
              child: Text(inr(item.grossValue),
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _freightBlock() {
    return _bordered(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (format.showEwb) ...[
                    _label('E-Way Bill'),
                    Text(lr.ewb?.number ?? '—',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800)),
                    if (lr.ewb?.expiry != null)
                      Text('Expiry: ${formatDate(lr.ewb!.expiry!)}',
                          style: const TextStyle(fontSize: 11.5)),
                    const SizedBox(height: 10),
                  ],
                  _label('Pay Type'),
                  Text(lr.payType.label,
                      style:
                          const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          Container(width: 1, color: AppColors.ink),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _moneyRow('Freight', lr.freight.freight),
                  _moneyRow('Door Delivery', lr.freight.doorDelivery),
                  _moneyRow('Handling', lr.freight.handling),
                  if (format.showInsurance)
                    _moneyRow('Insurance', lr.freight.insurance),
                  if (format.showMathadi)
                    _moneyRow('Mathadi', lr.freight.mathadi),
                  _moneyRow('GST', lr.freight.gst),
                  const Divider(),
                  _moneyRow('Total', lr.freight.total, bold: true),
                  _moneyRow('Advance', lr.freight.advance),
                  _moneyRow('Balance', lr.freight.balance,
                      bold: true, color: AppColors.red),
                  if (format.showVistarMargin && _isInternalCopy) ...[
                    const Divider(),
                    _moneyRow(
                      'Vistar Margin',
                      lr.freight.vistarMargin,
                      bold: true,
                      color: AppColors.plum,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Terms & Conditions',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                format.terms,
                style: TextStyle(
                    fontSize: 10,
                    color: AppColors.slate.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(format.footer,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 28),
            Container(
                width: 160,
                height: 1,
                color: AppColors.ink.withValues(alpha: 0.4)),
            const SizedBox(height: 4),
            const Text('Authorised Signatory',
                style: TextStyle(fontSize: 11, color: AppColors.slate)),
          ],
        ),
      ],
    );
  }

  Widget _bordered({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ink),
      ),
      child: child,
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 0.6,
          color: AppColors.slate,
          fontWeight: FontWeight.w800,
        ),
      );

  Widget _kv(String k, String v) => SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(k),
            Text(v,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      );

  Widget _moneyRow(String k, double v,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: AppColors.slate)),
          ),
          Text(inr(v),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                  color: color ?? AppColors.ink)),
        ],
      ),
    );
  }
}

const _hStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 11,
  letterSpacing: 0.4,
);
