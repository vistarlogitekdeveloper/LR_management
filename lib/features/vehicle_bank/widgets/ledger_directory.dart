import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/ledger_row.dart';
import '../data/vehicle_bank_repository.dart';
import 'ledger_card.dart';
import 'ledger_table.dart';

/// The ledger itself: the Vehicle Directory sheet's fourteen columns as a table
/// on a wide screen, stacked cards on a phone.
///
/// Wrapped in a [SelectionArea] so an account number or a PAN can be copied
/// straight out of the list — this sheet exists to be transcribed into payment
/// systems, and retyping a sixteen-digit account number is how transpositions
/// get made.
class LedgerDirectory extends StatelessWidget {
  final List<LedgerRow> rows;
  final double padding;

  const LedgerDirectory({super.key, required this.rows, required this.padding});

  @override
  Widget build(BuildContext context) {
    // Every row reports the same value — it is a property of the CALLER, not of
    // the row — so reading it off the first is enough. Empty list: nothing is
    // shown anyway, so the flag cannot mislead.
    final piiVisible = rows.isNotEmpty && rows.first.piiVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 14, padding, 8),
          child: _LedgerCount(count: rows.length, piiVisible: piiVisible),
        ),
        Expanded(
          child: SelectionArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Measured off the pane, not the window: the window is wider
                // than this by the app sidebar, so MediaQuery would promise a
                // table and then hand over cards.
                if (constraints.maxWidth < ledgerTableBreakpoint) {
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                    itemCount: rows.length,
                    itemBuilder: (context, i) =>
                        LedgerCard(row: rows[i], serial: i + 1),
                  );
                }
                return Padding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                  child: _LedgerTableBox(
                    rows: rows,
                    width: constraints.maxWidth - padding * 2,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgerTableBox extends StatelessWidget {
  final List<LedgerRow> rows;
  final double width;
  const _LedgerTableBox({required this.rows, required this.width});

  @override
  Widget build(BuildContext context) {
    final tableWidth = width < ledgerMinTableWidth
        ? ledgerMinTableWidth
        : width;
    return AppCard(
      padding: const EdgeInsets.all(4),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            // Header and body share one horizontal scroll box, so a column
            // heading never drifts away from its column.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LedgerTableHeader(),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, i) =>
                        LedgerTableRow(row: rows[i], serial: i + 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerCount extends StatelessWidget {
  final int count;
  final bool piiVisible;
  const _LedgerCount({required this.count, required this.piiVisible});

  @override
  Widget build(BuildContext context) {
    // The repository walks pages up to this ceiling; at the ceiling the list is
    // a prefix, and saying so beats letting someone conclude the missing vendors
    // were struck off.
    final capped = count >= VehicleBankRepository.maxRows;
    final noun = count == 1 ? 'entry' : 'entries';
    return Row(
      children: [
        Expanded(
          child: Text(
            capped
                ? 'First $count $noun — narrow the filters to see the rest'
                : '$count $noun',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // Says WHY the KYC and bank columns are masked or empty. Without this a
        // reader cannot tell "you may not see this" from "nobody has filled it
        // in", and would go asking the wrong people for the wrong thing.
        if (count > 0 && !piiVisible) const _MaskedNotice(),
      ],
    );
  }
}

class _MaskedNotice extends StatelessWidget {
  const _MaskedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.warn),
          SizedBox(width: 5),
          Text(
            'Aadhaar masked · bank details hidden',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.warn,
            ),
          ),
        ],
      ),
    );
  }
}
