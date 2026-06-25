import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../lr/providers/lr_providers.dart';
import '../../shell/widgets/app_topbar.dart';

class WarehouseScreen extends ConsumerWidget {
  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(lrListProvider);
    final booked = lrs.where((l) => l.status == LrStatus.booked).toList();
    final inTransit = lrs.where((l) => l.status == LrStatus.inTransit).toList();
    final delivered = lrs.where((l) => l.status == LrStatus.delivered).toList();

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'Warehouse',
            subtitle: 'Stage, dispatch, and delivery view',
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 1100;
                final mobile = c.maxWidth < 600;
                final cols = <Widget>[
                  _Column(
                    title: 'Booked',
                    icon: Icons.inventory_2_outlined,
                    tint: AppColors.plumLight,
                    lrs: booked,
                    mobile: mobile,
                  ),
                  _Column(
                    title: 'In Transit',
                    icon: Icons.local_shipping_outlined,
                    tint: AppColors.orange,
                    lrs: inTransit,
                    mobile: mobile,
                  ),
                  _Column(
                    title: 'Delivered',
                    icon: Icons.check_circle_outline,
                    tint: AppColors.ok,
                    lrs: delivered,
                    mobile: mobile,
                  ),
                ];
                final gap = mobile ? 10.0 : 16.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(mobile ? 14 : 28),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < cols.length; i++) ...[
                              Expanded(child: cols[i]),
                              if (i < cols.length - 1)
                                const SizedBox(width: 16),
                            ],
                          ],
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < cols.length; i++) ...[
                              cols[i],
                              if (i < cols.length - 1) SizedBox(height: gap),
                            ],
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
}

class _Column extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tint;
  final List<LorryReceipt> lrs;
  final bool mobile;

  const _Column({
    required this.title,
    required this.icon,
    required this.tint,
    required this.lrs,
    this.mobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(mobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(icon: icon, title: '$title  •  ${lrs.length}'),
          if (lrs.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: mobile ? 10 : 18),
              child: const Text(
                'Empty',
                style: TextStyle(color: AppColors.slate),
              ),
            ),
          for (final lr in lrs)
            Container(
              margin: EdgeInsets.only(bottom: mobile ? 6 : 8),
              padding: EdgeInsets.all(mobile ? 10 : 12),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tint.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lr.number,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      fontSize: mobile ? 13 : null,
                    ),
                  ),
                  SizedBox(height: mobile ? 2 : 4),
                  Text(
                    '${lr.consignor.name} → ${lr.consignee.name}',
                    style: TextStyle(
                      color: AppColors.slate,
                      fontSize: mobile ? 12 : 12.5,
                    ),
                    maxLines: mobile ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: mobile ? 6 : 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          lr.vehicle.number,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDate(lr.date),
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PayPill(pay: lr.payType),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
