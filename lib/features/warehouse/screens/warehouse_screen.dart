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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 1100;
                  final cols = <Widget>[
                    _Column(
                      title: 'Booked',
                      icon: Icons.inventory_2_outlined,
                      tint: AppColors.plumLight,
                      lrs: booked,
                    ),
                    _Column(
                      title: 'In Transit',
                      icon: Icons.local_shipping_outlined,
                      tint: AppColors.orange,
                      lrs: inTransit,
                    ),
                    _Column(
                      title: 'Delivered',
                      icon: Icons.check_circle_outline,
                      tint: AppColors.ok,
                      lrs: delivered,
                    ),
                  ];
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < cols.length; i++) ...[
                          Expanded(child: cols[i]),
                          if (i < cols.length - 1)
                            const SizedBox(width: 16),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < cols.length; i++) ...[
                        cols[i],
                        if (i < cols.length - 1) const SizedBox(height: 16),
                      ],
                    ],
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

class _Column extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tint;
  final List<LorryReceipt> lrs;

  const _Column({
    required this.title,
    required this.icon,
    required this.tint,
    required this.lrs,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            icon: icon,
            title: '$title  •  ${lrs.length}',
          ),
          if (lrs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Empty', style: TextStyle(color: AppColors.slate)),
            ),
          for (final lr in lrs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: tint.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lr.number,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${lr.consignor.name} → ${lr.consignee.name}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        lr.vehicle.number,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
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
