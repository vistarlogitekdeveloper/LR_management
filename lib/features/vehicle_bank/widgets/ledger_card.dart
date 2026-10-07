import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/ledger_row.dart';
import 'ledger_documents.dart';
import 'ledger_table.dart' show kEmptyCell;

/// One ledger row as a stacked card, for viewports too narrow for fourteen
/// columns. Carries exactly the same fields as the table in the same order —
/// grouped under the sheet's own headings, not dropped: a phone-sized subset
/// would make the two views disagree about what the sheet contains.
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
          _LedgerLine(
            label: 'Contact Number',
            value: row.personMobile,
            mono: true,
          ),
          _LedgerLine(label: 'Mail Id', value: row.personEmail),
          _LedgerLine(label: 'Vehicle Type', value: row.vehicleType),
          const _CardDivider(title: 'Route'),
          _LedgerLine(label: 'From', value: row.fromCity),
          _LedgerLine(label: 'To', value: row.toCity),
          const _CardDivider(title: 'KYC Documents'),
          _LedgerLine(label: 'Pan Card', value: row.personPan, mono: true),
          _LedgerLine(
            label: 'Adhar Card',
            value: row.personAadhaar,
            mono: true,
          ),
          const _CardDivider(title: 'Bank Details'),
          _LedgerLine(label: 'Bank Name', value: row.bankName),
          _LedgerLine(label: 'Branch Name', value: row.bankBranch),
          _LedgerLine(
            label: 'Bank AC No',
            value: row.bankAccountNo,
            mono: true,
          ),
          _LedgerLine(label: 'IFSC Code', value: row.bankIfsc, mono: true),
          const _CardDivider(title: 'Upload Document'),
          LedgerDocumentChips(documents: row.documents),
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
              if (name.isNotEmpty)
                Text(
                  // Same sub-label as the table's name cell.
                  row.personIsDriver
                      ? (row.transporterName.trim().isEmpty
                            ? 'driver'
                            : 'driver · ${row.transporterName.trim()}')
                      : 'owner',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
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

/// A divider carrying the sheet's group heading (Route, KYC Documents, …).
class _CardDivider extends StatelessWidget {
  final String title;
  const _CardDivider({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 5),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.plum,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Divider(height: 1, thickness: 1, color: AppColors.line),
          ),
        ],
      ),
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
