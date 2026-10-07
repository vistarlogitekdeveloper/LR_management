import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/ledger_row.dart';
import 'ledger_documents.dart';

/// The office's "Vehicle Directory" sheet, column for column: label, share of
/// the table width (flex), and the group the column sits under in the header's
/// first row (null = the label spans both header rows). Order is the sheet's
/// and must not change casually — this list IS the spec, [LedgerTableRow]
/// indexes its cells against it, and `ledger_workbook.dart` writes the same
/// columns (the test asserts the three agree).
const List<(String, int, String?)> ledgerColumns = [
  ('Sr.no.', 4, null),
  ('Driver/Owner Name', 13, null),
  ('Contact Number', 9, null),
  ('Mail Id', 13, null),
  ('Vehicle Type', 10, null),
  ('From', 8, 'Route'),
  ('To', 8, 'Route'),
  ('Pan Card', 9, 'KYC Documents'),
  ('Adhar Card', 10, 'KYC Documents'),
  ('Bank Name', 10, 'Bank Details'),
  ('Branch Name', 9, 'Bank Details'),
  ('Bank AC No', 11, 'Bank Details'),
  ('IFSC Code', 9, 'Bank Details'),
  ('Upload Document', 14, null),
];

/// Fourteen columns do not fit a phone, so below this each row becomes a
/// stacked card — the same break the rest of the app uses.
const double ledgerTableBreakpoint = 720;

/// Fourteen columns sharing less than this produce fourteen ellipsised words.
/// Between the two the table scrolls sideways inside its own box.
const double ledgerMinTableWidth = 1760;

/// Placeholder for a value the row genuinely does not carry, so an empty cell is
/// never ambiguous with a layout bug.
const String kEmptyCell = '—';

String _orDash(String value) =>
    value.trim().isEmpty ? kEmptyCell : value.trim();

const _headerStyle = TextStyle(
  fontSize: 11.5,
  fontWeight: FontWeight.w800,
  color: AppColors.slate,
  letterSpacing: 0.2,
);

/// The sheet's two-row header: Route, KYC Documents and Bank Details span their
/// columns in the top row with the column names beneath; every other column's
/// name fills both rows. Kept beside the row so the flex lists can only ever be
/// edited together.
class LedgerTableHeader extends StatelessWidget {
  const LedgerTableHeader({super.key});

  // Consecutive columns of one group become one segment.
  static List<(String?, List<(String, int, String?)>)> _segments() {
    final out = <(String?, List<(String, int, String?)>)>[];
    for (final c in ledgerColumns) {
      final group = c.$3;
      if (group != null && out.isNotEmpty && out.last.$1 == group) {
        out.last.$2.add(c);
      } else {
        out.add((group, [c]));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppColors.mist,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (group, cols) in _segments())
              Expanded(
                flex: cols.fold(0, (sum, c) => sum + c.$2),
                child: group == null
                    ? _HeaderLabel(cols.single.$1)
                    : _HeaderGroup(title: group, columns: cols),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String label;
  const _HeaderLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _headerStyle,
        ),
      ),
    );
  }
}

class _HeaderGroup extends StatelessWidget {
  final String title;
  final List<(String, int, String?)> columns;
  const _HeaderGroup({required this.title, required this.columns});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(top: 8, bottom: 5),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _headerStyle.copyWith(color: AppColors.plum),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  flex: columns[i].$2,
                  child: Padding(
                    // The segment's own right padding stands in for the last
                    // column's, so the leaves line up with the cells below.
                    padding: EdgeInsets.fromLTRB(
                      0,
                      6,
                      i == columns.length - 1 ? 0 : 10,
                      8,
                    ),
                    child: Text(
                      columns[i].$1,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _headerStyle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One ledger line. [serial] is the 1-based Sr.no. — a position in the current
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
      _PersonCell(row: row),
      _Cell(_orDash(row.personMobile), mono: true),
      _Cell(_orDash(row.personEmail)),
      _Cell(_orDash(row.vehicleType)),
      _Cell(_orDash(row.fromCity), bold: true),
      _Cell(_orDash(row.toCity), bold: true),
      _Cell(_orDash(row.personPan), mono: true),
      _Cell(_orDash(row.personAadhaar), mono: true),
      _Cell(_orDash(row.bankName)),
      _Cell(_orDash(row.bankBranch)),
      _Cell(_orDash(row.bankAccountNo), mono: true),
      _Cell(_orDash(row.bankIfsc), mono: true),
      LedgerDocumentChips(documents: row.documents),
    ];
    assert(cells.length == ledgerColumns.length);

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

  /// Identifiers — phone, PAN, Aadhaar, account number, IFSC — read better in a
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
    final empty = text == kEmptyCell;
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: bold && !empty ? FontWeight.w700 : FontWeight.w500,
        color: muted || empty ? AppColors.slate : AppColors.ink,
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
        if (row.personName.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              // The transporter is no longer a column of its own (the sheet has
              // none), so a driver row names who he runs for here.
              row.personIsDriver
                  ? (row.transporterName.trim().isEmpty
                        ? 'driver'
                        : 'driver · ${row.transporterName.trim()}')
                  : 'owner',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
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
