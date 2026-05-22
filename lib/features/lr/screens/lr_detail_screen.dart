import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../admin/providers/audit_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';

class LrDetailScreen extends ConsumerWidget {
  final String id;
  const LrDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lr = ref.watch(lrByIdProvider(id));
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.canEdit ?? false;
    final canDelete = user?.role.canDelete ?? false;
    if (lr == null) {
      return Scaffold(
        backgroundColor: AppColors.mist,
        body: Column(
          children: [
            const AppTopbar(title: 'LR Detail'),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.slate),
                    const SizedBox(height: 12),
                    const Text('LR not found',
                        style: TextStyle(color: AppColors.slate)),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Back to list',
                      kind: BtnKind.ghost,
                      onPressed: () => context.go('/lrs'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: lr.number,
            subtitle: '${formatDate(lr.date)} · entered by ${lr.enteredBy}',
            actions: [
              AppButton(
                label: 'Back',
                kind: BtnKind.ghost,
                icon: Icons.arrow_back_rounded,
                onPressed: () => context.go('/lrs'),
              ),
              if (canEdit)
                AppButton(
                  label: 'Edit',
                  kind: BtnKind.soft,
                  icon: Icons.edit_outlined,
                  onPressed: () => context.go('/lrs/${lr.id}/edit'),
                ),
              if (canDelete)
                AppButton(
                  label: 'Delete',
                  kind: BtnKind.danger,
                  icon: Icons.delete_outline,
                  onPressed: () async {
                    final ok = await showConfirmDialog(
                      context: context,
                      title: 'Delete LR ${lr.number}?',
                      message:
                          'This cannot be undone. The LR record will be removed from the system.',
                      confirmLabel: 'Delete LR',
                    );
                    if (!ok) return;
                    if (!context.mounted) return;
                    ref.read(lrListProvider.notifier).remove(lr.id);
                    ref.read(auditProvider.notifier).log(
                          user: user?.username ?? 'system',
                          action: 'DELETE',
                          entity: 'LR',
                          entityRef: lr.number,
                        );
                    context.go('/lrs');
                  },
                ),
              AppButton(
                label: 'Print',
                icon: Icons.print_outlined,
                onPressed: () => context.go('/lrs/${lr.id}/print'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 1000;
                  final left = _LeftColumn(lr: lr);
                  final right = _RightColumn(lr: lr);
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: right),
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
}

class _LeftColumn extends StatelessWidget {
  final LorryReceipt lr;
  const _LeftColumn({required this.lr});

  @override
  Widget build(BuildContext context) {
    return Column(
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
              _KeyValueGrid(items: [
                ('Consignor', lr.consignor.name),
                ('GST', lr.consignor.gst),
                ('Address', lr.consignor.address),
                ('Consignee', lr.consignee.name),
                ('GST', lr.consignee.gst),
                ('Delivery', lr.consignee.location),
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
              for (final item in lr.items) _ItemRow(item: item),
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
              _KeyValueGrid(items: [
                ('Vehicle', '${lr.vehicle.number} · ${lr.vehicle.type}'),
                ('Driver', '${lr.vehicle.driver} (${lr.vehicle.driverMobile})'),
                ('Capacity', lr.vehicle.capacity),
                ('P-Mark', lr.vehicle.pmark),
                ('Route', lr.route),
                ('Transporter', lr.transporter.name),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  final LorryReceipt lr;
  const _RightColumn({required this.lr});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                icon: Icons.flag_outlined,
                title: 'Status',
              ),
              Row(
                children: [
                  StatusPill(status: lr.status),
                  const SizedBox(width: 8),
                  PayPill(pay: lr.payType),
                ],
              ),
              const SizedBox(height: 12),
              _KeyValueGrid(items: [
                ('Delivery Type', lr.deliveryType.label),
                if (lr.ewb != null) ('EWB', lr.ewb!.number),
                if (lr.ewb?.expiry != null)
                  ('EWB Expiry', formatDate(lr.ewb!.expiry!)),
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
                title: 'Freight',
              ),
              _FreightRow(label: 'Freight', value: lr.freight.freight),
              _FreightRow(
                  label: 'Door Delivery', value: lr.freight.doorDelivery),
              _FreightRow(label: 'Handling', value: lr.freight.handling),
              _FreightRow(label: 'Insurance', value: lr.freight.insurance),
              _FreightRow(label: 'GST', value: lr.freight.gst),
              const Divider(),
              _FreightRow(
                  label: 'Total', value: lr.freight.total, emphasis: true),
              _FreightRow(label: 'Advance', value: lr.freight.advance),
              _FreightRow(
                label: 'Balance',
                value: lr.freight.balance,
                emphasis: true,
                color: AppColors.red,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.plum, AppColors.plumDark],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Vistar Margin',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      inr(lr.freight.vistarMargin),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _KeyValueGrid(items: [
                ('Mathadi', inr(lr.freight.mathadi)),
                ('Advance Paid By', lr.freight.advancePaidBy),
                ('Trip Lead By', lr.freight.tripLeadBy),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyValueGrid extends StatelessWidget {
  final List<(String, String)> items;
  const _KeyValueGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 500 ? 2 : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: (c.maxWidth - 16 * (cols - 1)) / cols,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.$2,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InvoiceItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.invoiceNo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                formatDate(item.invoiceDate),
                style: const TextStyle(
                    color: AppColors.slate, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.partDescription,
            style: const TextStyle(color: AppColors.slate, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _miniInfo('Packages', '${item.packages} ${item.packageType}'),
              _miniInfo('Qty', '${item.quantity}'),
              _miniInfo('Weight', '${item.weight.toStringAsFixed(0)} kg'),
              _miniInfo('Value', inr(item.grossValue)),
              _miniInfo('ASN', item.asn),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style:
                const TextStyle(color: AppColors.slate, fontSize: 12.5)),
        Text(value,
            style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 12.5)),
      ],
    );
  }
}

class _FreightRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasis;
  final Color? color;

  const _FreightRow({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
            inr(value),
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
