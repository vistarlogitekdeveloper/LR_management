import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../data/ewb_repository.dart';
import '../providers/ewb_providers.dart';
import '../../shell/widgets/app_topbar.dart';

class EwbScreen extends ConsumerStatefulWidget {
  const EwbScreen({super.key});

  @override
  ConsumerState<EwbScreen> createState() => _EwbScreenState();
}

class _EwbScreenState extends ConsumerState<EwbScreen> {
  final _validateCtrl = TextEditingController();
  final _tableScrollCtrl = ScrollController();
  String? _validateMessage;
  bool _validateOk = false;

  @override
  void dispose() {
    _validateCtrl.dispose();
    _tableScrollCtrl.dispose();
    super.dispose();
  }

  void _validate() {
    final v = _validateCtrl.text.trim();
    if (v.isEmpty) {
      setState(() {
        _validateMessage = 'Enter an EWB number';
        _validateOk = false;
      });
      return;
    }
    if (v.length != 12) {
      setState(() {
        _validateMessage = 'EWB must be exactly 12 digits';
        _validateOk = false;
      });
      return;
    }
    if (!RegExp(r'^\d{12}$').hasMatch(v)) {
      setState(() {
        _validateMessage = 'Digits only — letters not allowed';
        _validateOk = false;
      });
      return;
    }
    setState(() {
      _validateMessage = 'Valid 12-digit EWB · ready for GST portal verify';
      _validateOk = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ewbAsync = ref.watch(ewbListProvider);
    final now = DateTime.now();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final cardPad = isMobile
        ? const EdgeInsets.all(12)
        : const EdgeInsets.all(20);
    final gap = isMobile ? 10.0 : 20.0;

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'E-Way Bill Tracking',
            subtitle: '12-digit validation · expiry alerts',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 14 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    padding: cardPad,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.verified_outlined,
                          title: 'EWB Validator',
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _validateCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 12,
                                decoration: const InputDecoration(
                                  hintText: '12-digit EWB number',
                                  prefixIcon: Icon(
                                    Icons.qr_code_2_rounded,
                                    color: AppColors.slate,
                                  ),
                                  counterText: '',
                                ),
                                onChanged: (_) => setState(() {
                                  _validateMessage = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: _validate,
                              child: const Text('Validate'),
                            ),
                          ],
                        ),
                        if (_validateMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  (_validateOk
                                          ? AppColors.ok
                                          : AppColors.danger)
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _validateOk
                                      ? Icons.check_circle_outline
                                      : Icons.error_outline,
                                  color: _validateOk
                                      ? AppColors.ok
                                      : AppColors.danger,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _validateMessage!,
                                    style: TextStyle(
                                      color: _validateOk
                                          ? AppColors.ok
                                          : AppColors.danger,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  ewbAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => AppCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Could not load E-Way Bills: $err',
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    data: (records) {
                      final expiringSoon = records.where((rec) {
                        final exp = rec.expiry;
                        if (exp == null) return false;
                        final days = exp.difference(now).inDays;
                        return days <= 3 && days >= 0;
                      }).toList();
                      final expired = records.where((rec) {
                        final exp = rec.expiry;
                        return exp != null && exp.isBefore(now);
                      }).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, c) {
                              // mobile: 3 compact tiles in one row; wide: 3 across
                              final cols = c.maxWidth >= 900
                                  ? 3
                                  : (isMobile ? 3 : 1);
                              final spacing = isMobile ? 8.0 : 16.0;
                              final tiles = <_EwbStat>[
                                _EwbStat(
                                  icon: Icons.list_alt,
                                  label: 'EWBs Issued',
                                  value: '${records.length}',
                                  tint: AppColors.plum,
                                  compact: isMobile,
                                ),
                                _EwbStat(
                                  icon: Icons.warning_amber_rounded,
                                  label: 'Expiring ≤ 3 days',
                                  value: '${expiringSoon.length}',
                                  tint: AppColors.warn,
                                  compact: isMobile,
                                ),
                                _EwbStat(
                                  icon: Icons.error_outline,
                                  label: 'Expired',
                                  value: '${expired.length}',
                                  tint: AppColors.danger,
                                  compact: isMobile,
                                ),
                              ];
                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: [
                                  for (final t in tiles)
                                    SizedBox(
                                      width:
                                          (c.maxWidth - spacing * (cols - 1)) /
                                          cols,
                                      child: t,
                                    ),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: gap),
                          AppCard(
                            padding: cardPad,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionTitle(
                                  icon: Icons.qr_code_2_rounded,
                                  title: 'All EWBs',
                                ),
                                Scrollbar(
                                  controller: _tableScrollCtrl,
                                  thumbVisibility: isMobile,
                                  child: SingleChildScrollView(
                                    controller: _tableScrollCtrl,
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStatePropertyAll(
                                        AppColors.plum.withValues(alpha: 0.05),
                                      ),
                                      columnSpacing: isMobile ? 16 : 24,
                                      columns: const [
                                        DataColumn(label: Text('LR No')),
                                        DataColumn(label: Text('EWB Number')),
                                        DataColumn(label: Text('Load Type')),
                                        DataColumn(label: Text('Expiry')),
                                        DataColumn(label: Text('Status')),
                                        DataColumn(label: Text('')),
                                      ],
                                      rows: [
                                        for (final rec in records)
                                          DataRow(
                                            cells: [
                                              DataCell(
                                                Text(
                                                  rec.lrNumber,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              DataCell(Text(rec.number)),
                                              DataCell(Text(rec.loadType)),
                                              DataCell(
                                                Text(
                                                  rec.expiry == null
                                                      ? '—'
                                                      : formatDate(rec.expiry!),
                                                ),
                                              ),
                                              DataCell(_expiryBadge(rec, now)),
                                              DataCell(
                                                IconButton(
                                                  tooltip: 'Open LR',
                                                  icon: const Icon(
                                                    Icons.arrow_forward_rounded,
                                                    color: AppColors.plum,
                                                    size: 18,
                                                  ),
                                                  onPressed:
                                                      (rec.lrId != null &&
                                                          rec.lrId!.isNotEmpty)
                                                      ? () => context.go(
                                                          '/lrs/${rec.lrId}',
                                                        )
                                                      : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expiryBadge(EwbRecord rec, DateTime now) {
    final status = rec.validationStatus.toLowerCase();
    final exp = rec.expiry;
    late final String label;
    late final Color color;
    if (status == 'invalid') {
      label = 'Invalid';
      color = AppColors.danger;
    } else if (status == 'expired' || (exp != null && exp.isBefore(now))) {
      label = 'Expired';
      color = AppColors.danger;
    } else if (exp == null) {
      if (status == 'valid') {
        label = 'Valid';
        color = AppColors.ok;
      } else {
        label = 'Pending';
        color = AppColors.slate;
      }
    } else {
      final diff = exp.difference(now).inDays;
      if (diff <= 3) {
        label = '${diff}d left';
        color = AppColors.warn;
      } else {
        label = status == 'valid' ? 'Valid' : 'OK';
        color = AppColors.ok;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EwbStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final bool compact;
  const _EwbStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // narrow 3-across mobile tile: icon + value + label stacked
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.15,
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
