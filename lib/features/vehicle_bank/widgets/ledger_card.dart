import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/ledger_row.dart';
import 'ledger_table.dart' show kEmptyCell;

/// One ledger row as a stacked card, for viewports too narrow for thirteen
/// columns. Carries exactly the same fields as the table in the same order —
/// grouped, not dropped: a phone-sized subset would make the two views disagree
/// about what the sheet contains.
class LedgerCard extends StatelessWidget {
  final LedgerRow row;
  final int serial;
  const LedgerCard({super.key, required this.row, required this.serial});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(row: row, serial: serial),
          const SizedBox(height: 10),
          _LedgerLine(label: 'Source', value: row.sourceCity),
          _LedgerLine(label: 'Route', value: row.routeLabel),
          _LedgerLine(label: 'Contact', value: row.personMobile),
          _LedgerLine(label: 'Transporter', value: row.transporterName),
          _LedgerLine(
            label: 'Transporter contact',
            value: row.transporterMobile,
          ),
          const _CardDivider(),
          _LedgerLine(label: 'PAN', value: row.personPan, mono: true),
          _LedgerLine(label: 'Aadhaar', value: row.personAadhaar, mono: true),
          const _CardDivider(),
          _LedgerLine(label: 'Bank name', value: row.bankName),
          _LedgerLine(label: 'Branch', value: row.bankBranch),
          _LedgerLine(
            label: 'Bank A/C no',
            value: row.bankAccountNo,
            mono: true,
          ),
          _LedgerLine(label: 'IFSC', value: row.bankIfsc, mono: true),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final LedgerRow row;
  final int serial;
  const _CardHeader({required this.row, required this.serial});

  @override
  Widget build(BuildContext context) {
    final name = row.personName.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.mist,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$serial',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.slate,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.isEmpty ? kEmptyCell : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (!row.personIsDriver && name.isNotEmpty)
                const Text(
                  'owner',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate,
                  ),
                ),
            ],
          ),
        ),
        if (row.lrCount > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.plum.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${row.lrCount} LRs',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.plum,
              ),
            ),
          ),
      ],
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 7),
      child: Divider(height: 1, thickness: 1, color: AppColors.line),
    );
  }
}

class _LedgerLine extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _LedgerLine({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final shown = value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.slate),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              shown.isEmpty ? kEmptyCell : shown,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: shown.isEmpty ? AppColors.slate : AppColors.ink,
                fontFeatures: mono
                    ? const [FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
