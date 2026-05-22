import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/section_title.dart';
import '../../lr/providers/lr_providers.dart';
import '../../reports/services/export_service.dart';
import '../../shell/widgets/app_topbar.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lrs = ref.watch(lrListProvider);
    final pending = lrs.where((lr) => lr.freight.balance > 0).toList();
    final totalAdvance =
        lrs.fold<double>(0, (s, l) => s + l.freight.advance);
    final totalPending =
        pending.fold<double>(0, (s, l) => s + l.freight.balance);
    final totalBilled =
        lrs.fold<double>(0, (s, l) => s + l.freight.total);
    final marginMtd =
        lrs.fold<double>(0, (s, l) => s + l.freight.vistarMargin);

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Accounts & Billing',
            subtitle: 'Freight pending, advances, exports',
            actions: [
              AppButton(
                label: 'CSV',
                icon: Icons.file_download_outlined,
                kind: BtnKind.ghost,
                onPressed: () => ExportService.exportPendingFreightCsv(lrs),
              ),
              AppButton(
                label: 'Tally export',
                icon: Icons.file_download_outlined,
                kind: BtnKind.soft,
                onPressed: () => ExportService.exportTally(lrs),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 1100
                          ? 4
                          : c.maxWidth >= 700
                              ? 2
                              : 1;
                      final tiles = <Widget>[
                        _Tile(
                          label: 'Total Billed',
                          value: inr(totalBilled),
                          icon: Icons.receipt_long_outlined,
                          color: AppColors.plum,
                        ),
                        _Tile(
                          label: 'Advance Received',
                          value: inr(totalAdvance),
                          icon: Icons.savings_outlined,
                          color: AppColors.ok,
                        ),
                        _Tile(
                          label: 'Pending Freight',
                          value: inr(totalPending),
                          icon: Icons.pending_actions_outlined,
                          color: AppColors.red,
                        ),
                        _Tile(
                          label: 'Margin (MTD)',
                          value: inr(marginMtd),
                          icon: Icons.trending_up_rounded,
                          color: AppColors.plumLight,
                        ),
                      ];
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final t in tiles)
                            SizedBox(
                              width:
                                  (c.maxWidth - 16 * (cols - 1)) / cols,
                              child: t,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.pending_actions_outlined,
                          title: 'Freight pending',
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStatePropertyAll(
                              AppColors.plum.withValues(alpha: 0.05),
                            ),
                            columns: const [
                              DataColumn(label: Text('LR No')),
                              DataColumn(label: Text('Customer')),
                              DataColumn(label: Text('Total')),
                              DataColumn(label: Text('Advance')),
                              DataColumn(label: Text('Balance')),
                              DataColumn(label: Text('Pay')),
                            ],
                            rows: [
                              for (final lr in pending)
                                DataRow(cells: [
                                  DataCell(Text(lr.number,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700))),
                                  DataCell(Text(lr.consignor.name)),
                                  DataCell(Text(inr(lr.freight.total))),
                                  DataCell(Text(inr(lr.freight.advance))),
                                  DataCell(Text(
                                    inr(lr.freight.balance),
                                    style: const TextStyle(
                                      color: AppColors.red,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )),
                                  DataCell(PayPill(pay: lr.payType)),
                                ]),
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
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
                fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}
