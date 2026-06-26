import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mime_types.dart';
import '../../../shared/models/attachment.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../../masters/widgets/master_actions.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';

class LrDetailScreen extends ConsumerWidget {
  final String id;
  const LrDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLr = ref.watch(lrDetailProvider(id));
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.canEditLr ?? false;
    final canDelete = user?.canDeleteLr ?? false;

    return asyncLr.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.mist,
        body: Column(
          children: [
            AppTopbar(title: 'LR Detail'),
            Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.mist,
        body: Column(
          children: [
            const AppTopbar(title: 'LR Detail'),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.slate,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      MasterActions.messageFor(e),
                      style: const TextStyle(color: AppColors.slate),
                    ),
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
      ),
      data: (lr) => _buildLoaded(context, ref, lr, canEdit, canDelete),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    WidgetRef ref,
    LorryReceipt lr,
    bool canEdit,
    bool canDelete,
  ) {
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: lr.number,
            subtitle: '${formatDate(lr.date)} · ${lr.status.label}',
            actions: [
              AppButton(
                label: 'Back',
                kind: BtnKind.ghost,
                icon: Icons.arrow_back_rounded,
                onPressed: () => context.go('/lrs'),
              ),
              if (canEdit)
                AppButton(
                  label: 'Status',
                  kind: BtnKind.soft,
                  icon: Icons.flag_outlined,
                  onPressed: () => _changeStatus(context, ref, lr),
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
                  onPressed: () => _delete(context, ref, lr),
                ),
              AppButton(
                label: 'Print',
                icon: Icons.print_outlined,
                onPressed: () => context.go('/lrs/${lr.id}/print'),
              ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 1000;
                final mobile = c.maxWidth < 600;
                final left = _LeftColumn(lr: lr, mobile: mobile);
                final right = _RightColumn(lr: lr, mobile: mobile);
                return SingleChildScrollView(
                  padding: EdgeInsets.all(mobile ? 14 : 28),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: left),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: right),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            left,
                            SizedBox(height: mobile ? 12 : 20),
                            right,
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    LorryReceipt lr,
  ) async {
    final next = await showDialog<LrStatus>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change status'),
        children: [
          for (final s in LrStatus.values)
            if (s != lr.status)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      StatusPill(status: s),
                      const SizedBox(width: 10),
                      Text('Mark as ${s.label}'),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
    if (next == null || !context.mounted) return;

    String? reason;
    if (next == LrStatus.cancelled) {
      reason = await _promptReason(context);
      if (reason == null) return; // cancelled the prompt
    }

    try {
      await ref
          .read(lrListProvider.notifier)
          .changeStatus(lr.id, next, reason: reason);
      ref.invalidate(lrDetailProvider(lr.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${next.label}')),
        );
      }
    } catch (e) {
      if (context.mounted) MasterActions.showError(context, e);
    }
  }

  Future<String?> _promptReason(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancellation reason'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Why is this LR cancelled?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Confirm Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    LorryReceipt lr,
  ) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Delete LR ${lr.number}?',
      message:
          'This cannot be undone. The LR record will be removed from the system.',
      confirmLabel: 'Delete LR',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(lrListProvider.notifier).remove(lr.id);
      if (context.mounted) context.go('/lrs');
    } catch (e) {
      if (context.mounted) MasterActions.showError(context, e);
    }
  }
}

class _LeftColumn extends StatelessWidget {
  final LorryReceipt lr;
  final bool mobile;
  const _LeftColumn({required this.lr, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    final cardPad = EdgeInsets.all(mobile ? 12 : 20);
    final gap = SizedBox(height: mobile ? 12 : 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: cardPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.swap_horiz_rounded,
                title: 'Parties',
                mobile: mobile,
              ),
              _KeyValueGrid(
                items: [
                  if (lr.customerName.isNotEmpty) ('Customer', lr.customerName),
                  ('Consignor', lr.consignor.name),
                  ('GST', lr.consignor.gst),
                  ('Address', lr.consignor.address),
                  ('Consignee', lr.consignee.name),
                  ('GST', lr.consignee.gst),
                  ('Delivery', lr.consignee.location),
                ],
                mobile: mobile,
              ),
            ],
          ),
        ),
        gap,
        AppCard(
          padding: cardPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.inventory_2_outlined,
                title: 'Invoice & Goods',
                mobile: mobile,
              ),
              if (lr.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No invoice items',
                    style: TextStyle(color: AppColors.slate),
                  ),
                ),
              for (final item in lr.items) _ItemRow(item: item, mobile: mobile),
            ],
          ),
        ),
        if (lr.attachments.isNotEmpty) ...[
          gap,
          AppCard(
            padding: cardPad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon: Icons.attach_file_rounded,
                  title: 'Invoice Attachments (${lr.attachments.length})',
                  mobile: mobile,
                ),
                for (final a in lr.attachments)
                  _AttachmentTile(lrId: lr.id, attachment: a),
              ],
            ),
          ),
        ],
        gap,
        AppCard(
          padding: cardPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.local_shipping_outlined,
                title: 'Vehicle & Route',
                mobile: mobile,
              ),
              _KeyValueGrid(
                items: [
                  ('Vehicle', '${lr.vehicle.number} · ${lr.vehicle.type}'),
                  (
                    'Driver',
                    '${lr.vehicle.driver} (${lr.vehicle.driverMobile})',
                  ),
                  ('Capacity', lr.vehicle.capacity),
                  ('Route', lr.route),
                  ('Transporter', lr.transporter.name),
                ],
                mobile: mobile,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  final LorryReceipt lr;
  final bool mobile;
  const _RightColumn({required this.lr, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    final cardPad = EdgeInsets.all(mobile ? 12 : 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: cardPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.flag_outlined,
                title: 'Status',
                mobile: mobile,
              ),
              Row(
                children: [
                  StatusPill(status: lr.status),
                  const SizedBox(width: 8),
                  PayPill(pay: lr.payType),
                ],
              ),
              const SizedBox(height: 12),
              _KeyValueGrid(
                items: [
                  ('Delivery Type', lr.deliveryType.label),
                  if (lr.ewb != null) ('EWB', lr.ewb!.number),
                  if (lr.ewb?.expiry != null)
                    ('EWB Expiry', formatDate(lr.ewb!.expiry!)),
                ],
                mobile: mobile,
              ),
            ],
          ),
        ),
        SizedBox(height: mobile ? 12 : 20),
        AppCard(
          padding: cardPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.calculate_outlined,
                title: 'Freight',
                mobile: mobile,
              ),
              _FreightRow(label: 'Freight', value: lr.freight.freight),
              _FreightRow(
                label: 'Door Delivery',
                value: lr.freight.doorDelivery,
              ),
              _FreightRow(label: 'Handling', value: lr.freight.handling),
              _FreightRow(label: 'Insurance', value: lr.freight.insurance),
              const Divider(),
              _FreightRow(
                label: 'Total',
                value: lr.freight.total,
                emphasis: true,
              ),
              _FreightRow(label: 'Advance', value: lr.freight.advance),
              _FreightRow(
                label: 'Balance',
                value: lr.freight.balance,
                emphasis: true,
                color: AppColors.red,
              ),
              const SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(mobile ? 12 : 14),
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
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          inr(lr.freight.vistarMargin),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _KeyValueGrid(
                items: [
                  ('Mathadi', inr(lr.freight.mathadi)),
                  if (lr.freight.advancePaidBy.isNotEmpty)
                    ('Advance Paid By', lr.freight.advancePaidBy),
                  if (lr.freight.tripLeadBy.isNotEmpty)
                    ('Trip Lead By', lr.freight.tripLeadBy),
                ],
                mobile: mobile,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Compact section header; on mobile shrinks the icon badge and title.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool mobile;
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.mobile = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!mobile) return SectionTitle(icon: icon, title: title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.plum.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: AppColors.plum),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValueGrid extends StatelessWidget {
  final List<(String, String)> items;
  final bool mobile;
  const _KeyValueGrid({required this.items, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 500 ? 2 : 1;
        return Wrap(
          spacing: 16,
          runSpacing: mobile ? 8 : 12,
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
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                        fontSize: mobile ? 13 : 13.5,
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
  final bool mobile;
  const _ItemRow({required this.item, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: mobile ? 8 : 10),
      padding: EdgeInsets.all(mobile ? 10 : 12),
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
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatDate(item.invoiceDate),
                style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.partDescription,
            style: const TextStyle(color: AppColors.slate, fontSize: 13),
          ),
          SizedBox(height: mobile ? 8 : 10),
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
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
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

class _AttachmentTile extends ConsumerStatefulWidget {
  final String lrId;
  final Attachment attachment;
  const _AttachmentTile({required this.lrId, required this.attachment});

  @override
  ConsumerState<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends ConsumerState<_AttachmentTile> {
  bool _loading = false;

  Future<void> _view() async {
    setState(() => _loading = true);
    try {
      final a = widget.attachment;
      final bytes = await ref
          .read(lrRepositoryProvider)
          .downloadAttachmentBytes(widget.lrId, a.id);
      openFileInBrowser(bytes, a.mimeType ?? mimeForName(a.name), a.name);
    } catch (e) {
      if (mounted) MasterActions.showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 18,
            color: AppColors.plum,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${a.sizeLabel} · ${formatDate(a.uploadedAt)}',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton.icon(
                  onPressed: _view,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('View'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.plum,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
        ],
      ),
    );
  }
}
