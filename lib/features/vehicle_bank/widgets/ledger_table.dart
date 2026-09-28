import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/ledger_row.dart';

/// The agreed column order, with each column's share of the table width as flex
/// units. Order is the reading order of the sheet and must not be reordered
/// casually — this list IS the spec, and [LedgerTableRow] indexes its cells
/// against it.
const List<(String, int)> ledgerColumns = [
  ('Sr.', 3),
  ('Source', 7),
  ('Driver / Owner', 11),
  ('Contact', 7),
  ('Transporter', 11),
  ('Transporter Contact', 7),
  ('Route', 12),
  ('PAN', 7),
  ('Aadhaar', 8),
  ('Bank Name', 8),
  ('Branch', 6),
  ('Bank A/C No', 9),
  ('IFSC', 7),
];

/// Thirteen columns do not fit a phone, so below this each row becomes a
/// stacked card — the same break the rest of the app uses.
const double ledgerTableBreakpoint = 720;

/// Thirteen columns sharing less than this produce thirteen ellipsised words.
/// Between the two the table scrolls sideways inside its own box.
const double ledgerMinTableWidth = 1680;

/// Placeholder for a value the row genuinely does not carry, so an empty cell is
/// never ambiguous with a layout bug.
const String kEmptyCell = '—';

String _orDash(String value) =>
    value.trim().isEmpty ? kEmptyCell : value.trim();

/// Header strip for [LedgerTableRow]. Kept beside the row so the two flex lists
/// can only ever be edited together.
class LedgerTableHeader extends StatelessWidget {
  const LedgerTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(
        color: AppColors.mist,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          for (final (label, flex) in ledgerColumns)
            Expanded(
              flex: flex,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.slate,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One ledger line. [serial] is the 1-based Sr. no. — a position in the current
/// ordering, not an id, which is why the whole set is fetched before numbering.
class LedgerTableRow extends StatelessWidget {
  final LedgerRow row;
  final int serial;
  const LedgerTableRow({super.key, required this.row, required this.serial});

  @override
  Widget build(BuildContext context) {
    // One entry per column, in the same order as ledgerColumns — they are
    // indexed together below, so a column added to one must be added to both.
    final cells = <Widget>[
      _Cell('$serial', muted: true),
      _Cell(_orDash(row.sourceCity), bold: true),
      _PersonCell(row: row),
      _Cell(_orDash(row.personMobile)),
      _Cell(_orDash(row.transporterName)),
      _Cell(_orDash(row.transporterMobile)),
      _Cell(_orDash(row.routeLabel)),
      _Cell(_orDash(row.personPan), mono: true),
      _Cell(_orDash(row.personAadhaar), mono: true),
      _Cell(_orDash(row.bankName)),
      _Cell(_orDash(row.bankBranch)),
      _Cell(_orDash(row.bankAccountNo), mono: true),
      _Cell(_orDash(row.bankIfsc), mono: true),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < ledgerColumns.length; i++)
            Expanded(
              flex: ledgerColumns[i].$2,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: cells[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool bold;
  final bool muted;

  /// Identifiers — PAN, Aadhaar, account number, IFSC — read better in a
  /// tabular figure face, where digits align down the column and a
  /// transposition is visible.
  final bool mono;

  const _Cell(
    this.text, {
    this.bold = false,
    this.muted = false,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: muted ? AppColors.slate : AppColors.ink,
        fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
      ),
    );
  }
}

/// Driver/Owner. A row whose LR named no driver is the transporter wearing its
/// owner hat, and saying so is what stops the column reading as "the driver was
/// called ONKAR TRANSPORT".
class _PersonCell extends StatelessWidget {
  final LedgerRow row;
  const _PersonCell({required this.row});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _orDash(row.personName),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (!row.personIsDriver && row.personName.trim().isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text(
              'owner',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.slate,
              ),
            ),
          ),
      ],
    );
  }
}
