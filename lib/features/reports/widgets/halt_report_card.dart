import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/pills.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../lr/utils/manual_lr_number.dart';
import '../providers/reports_providers.dart';
import '../services/export_service.dart';

/// Reports → Daily: the special vehicles on the books, and the halt report
/// download (GET /reports/halts.xlsx — every recorded halt, filterable by
/// period, region and special vehicles only). 30 Oct 2026, migration 254.
class HaltReportCard extends ConsumerStatefulWidget {
  final List<LorryReceipt> lrs;
  const HaltReportCard({super.key, required this.lrs});

  @override
  ConsumerState<HaltReportCard> createState() => _HaltReportCardState();
}

class _HaltReportCardState extends ConsumerState<HaltReportCard> {
  DateTimeRange? _range;
  String? _region;
  bool _specialOnly = false;
  bool _busy = false;

  String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await ref
          .read(reportsRepositoryProvider)
          .haltsXlsx(
            from: _range == null ? null : _day(_range!.start),
            to: _range == null ? null : _day(_range!.end),
            regionId: _region,
            special: _specialOnly,
          );
      await ExportService.shareBytes(
        bytes,
        'Halt_Report_${ExportService.stamp()}.xlsx',
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Halt report generated')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not generate the halt report: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final regions = <String, String>{};
    for (final l in widget.lrs) {
      final rid = l.regionId;
      final code = regionCodeFromLrNumber(l.number);
      if (rid != null && rid.isNotEmpty && code != null) regions[rid] = code;
    }
    final special = widget.lrs.where((l) => l.isSpecialVehicle).toList();
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            icon: Icons.pause_circle_outline_rounded,
            title: 'Halt report & special vehicles',
          ),
          const SizedBox(height: 6),
          const Text(
            'Every recorded halt with start, end, duration, location and the '
            'reason given. Special vehicles are recorded from 1 hour.',
            style: TextStyle(fontSize: 12, color: AppColors.slate),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  _range == null
                      ? 'All dates'
                      : '${formatDate(_range!.start)} – ${formatDate(_range!.end)}',
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 2),
                    lastDate: now,
                    initialDateRange: _range,
                  );
                  if (r != null) setState(() => _range = r);
                },
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Clear dates',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _range = null),
                ),
              if (regions.length > 1)
                SizedBox(
                  width: 180,
                  child: SearchableField<String>(
                    value: _region,
                    options: regions.keys.toList()
                      ..sort((a, b) => regions[a]!.compareTo(regions[b]!)),
                    labelOf: (id) => regions[id] ?? id,
                    hintText: 'All regions',
                    dialogTitle: 'Region',
                    clearable: true,
                    onChanged: (v) => setState(() => _region = v),
                  ),
                ),
              FilterChip(
                key: const ValueKey('halt-report-special'),
                avatar: const Icon(Icons.star_rounded, size: 16),
                label: const Text('Special vehicles only'),
                selected: _specialOnly,
                onSelected: (v) => setState(() => _specialOnly = v),
              ),
              AppButton(
                label: 'Download halt report (Excel)',
                icon: Icons.download_outlined,
                kind: BtnKind.primary,
                small: true,
                loading: _busy,
                onPressed: _busy ? null : _download,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const SpecialVehiclePill(compact: true),
              const SizedBox(width: 8),
              Text(
                '${special.length} special vehicle LR${special.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          if (special.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final l in special.take(10))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l.number} · ${l.vehicle.number} · ${l.route} · ${l.status.label}',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (special.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '…and ${special.length - 10} more — filter the LR list by '
                  '"Special vehicles" to see them all.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.slate,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
