import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:printing/printing.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';

class ExportService {
  ExportService._();

  /// Exports the LR list as a real Excel workbook (.xlsx). The transporter-side
  /// columns (freight … balance) are emitted only when [canViewTransporterRate]
  /// is true, and the Vistar Margin column only when [canViewVistarMargin] is
  /// true (migration 072 visibility perms). [canViewCustomerRate] joins the
  /// other two to gate Vistar Billing Amount, which MIS releases only to a
  /// holder of all three — any two of billing amount, freight and margin yield
  /// the third by arithmetic. Callers pass the current user's flags; all three
  /// default true so unrestricted callers are unaffected. Header and row cells
  /// share the same guards so columns stay aligned.
  static Future<void> exportLrsExcel(
    List<LorryReceipt> lrs, {
    bool canViewTransporterRate = true,
    bool canViewVistarMargin = true,
    bool canViewCustomerRate = true,
    String? filenameSuffix,
  }) async {
    final bytes = buildLrsWorkbook(
      lrs,
      canViewTransporterRate: canViewTransporterRate,
      canViewVistarMargin: canViewVistarMargin,
      canViewCustomerRate: canViewCustomerRate,
    );
    if (bytes != null) {
      final suffix = filenameSuffix == null ? '' : '_$filenameSuffix';
      await shareBytes(bytes, 'vistar_lrs${suffix}_${_now()}.xlsx');
    }
  }

  /// Builds the LR workbook and returns its `.xlsx` bytes (no sharing) — split
  /// out from [exportLrsExcel] so the column layout can be unit-tested.
  static List<int>? buildLrsWorkbook(
    List<LorryReceipt> lrs, {
    bool canViewTransporterRate = true,
    bool canViewVistarMargin = true,
    bool canViewCustomerRate = true,
  }) {
    // MIS emits billing_amount only to a caller holding all three rate perms.
    final canViewBillingAmount =
        canViewTransporterRate && canViewVistarMargin && canViewCustomerRate;
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

    // Header names deliberately mirror the MIS workbook
    // (lr-management/services/misWorkbook.service.js, MIS_COLUMNS) so the two
    // sheets can be read, compared and pasted side by side. Where MIS spells a
    // heading oddly — "Transportor name", "TransportBalance Payment" — the
    // spelling is copied verbatim rather than corrected, because matching is
    // the whole point; fix them in MIS first if they should change.
    //
    // Columns with no MIS counterpart (Consignor, Consignee, the In/Out
    // date-time split, Door Delivery, Handling, Insurance, Pay Type, Status,
    // EWB) keep their own names.
    final headers = <String>[
      'LR No', 'LR Date', 'Customer Name (Billing From Vistar)',
      'Consignor', 'Consignee',
      'Transportor name', 'Vehicle No.', 'Vehicle Type', 'Vehicle Capacity',
      // In / Out are split into separate date and (24-hour) time columns.
      'In Date', 'In Time', 'Out Date', 'Out Time', 'Origin to Destination',
      if (canViewTransporterRate) ...[
        // MIS calls the base freight "Total Transport Charges" (its
        // total_charges cell is lr.freight, not the grand total), so this
        // column takes that name.
        'Total Transport Charges',
        'Door Delivery',
        'Handling',
        'Insurance',
        'Mathadi Charges',
        'Transport Advance Paid',
        if (canViewBillingAmount) 'Vistar Billing Amount',
        'TransportBalance Payment',
      ],
      if (canViewVistarMargin) 'Vistar Margin',
      'Pay Type', 'Status', 'EWB',
    ];
    sheet.appendRow(headers.map<CellValue?>((h) => TextCellValue(h)).toList());

    // The list arrives latest-first (created_at DESC); reverse it so the sheet
    // reads oldest → newest, i.e. the latest LR is the LAST row.
    for (final lr in lrs.reversed) {
      sheet.appendRow(<CellValue?>[
        TextCellValue(lr.number),
        TextCellValue(formatDate(lr.date)),
        TextCellValue(lr.customerName),
        TextCellValue(lr.consignor.name),
        TextCellValue(lr.consignee.name),
        TextCellValue(lr.transporter.name),
        TextCellValue(lr.vehicle.number),
        TextCellValue(lr.vehicle.type),
        TextCellValue(lr.capacityLabel),
        // Date and 24-hour time in their own columns (blank when not recorded).
        TextCellValue(lr.inDateTime != null ? formatDate(lr.inDateTime!) : ''),
        TextCellValue(
          lr.inDateTime != null ? formatTime24(lr.inDateTime!) : '',
        ),
        TextCellValue(
          lr.outDateTime != null ? formatDate(lr.outDateTime!) : '',
        ),
        TextCellValue(
          lr.outDateTime != null ? formatTime24(lr.outDateTime!) : '',
        ),
        TextCellValue(lr.route),
        if (canViewTransporterRate) ...[
          DoubleCellValue(lr.freight.freight),
          DoubleCellValue(lr.freight.doorDelivery),
          DoubleCellValue(lr.freight.handling),
          DoubleCellValue(lr.freight.insurance),
          DoubleCellValue(lr.freight.mathadi),
          DoubleCellValue(lr.freight.advance),
          // misRow's billing_amount: what Vistar bills the customer.
          if (canViewBillingAmount)
            DoubleCellValue(lr.freight.freight + lr.freight.vistarMargin),
          // misRow's balance is freight - advance, not lr.freight.balance: the
          // `balance` generated column (migration 078) is total - advance, and
          // `total` there sums vistar_margin in with the freight heads, so
          // using it would bill Vistar's own margin to the transporter.
          DoubleCellValue(lr.freight.freight - lr.freight.advance),
        ],
        if (canViewVistarMargin) DoubleCellValue(lr.freight.vistarMargin),
        TextCellValue(lr.payType.label),
        TextCellValue(lr.status.label),
        TextCellValue(lr.ewb?.number ?? ''),
      ]);
    }

    return excel.encode();
  }

  static Future<void> exportTally(List<LorryReceipt> lrs) async {
    final buf = StringBuffer();
    buf.writeln('<ENVELOPE>');
    buf.writeln('  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>');
    buf.writeln('  <BODY><IMPORTDATA>');
    buf.writeln(
      '    <REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME></REQUESTDESC>',
    );
    buf.writeln('    <REQUESTDATA>');
    for (final lr in lrs) {
      buf.writeln('      <TALLYMESSAGE>');
      buf.writeln('        <VOUCHER VCHTYPE="Sales" ACTION="Create">');
      buf.writeln('          <DATE>${formatDate(lr.date)}</DATE>');
      buf.writeln('          <VOUCHERNUMBER>${lr.number}</VOUCHERNUMBER>');
      buf.writeln('          <PARTYNAME>${lr.consignor.name}</PARTYNAME>');
      buf.writeln(
        '          <AMOUNT>${lr.freight.total.toStringAsFixed(2)}</AMOUNT>',
      );
      buf.writeln('        </VOUCHER>');
      buf.writeln('      </TALLYMESSAGE>');
    }
    buf.writeln('    </REQUESTDATA>');
    buf.writeln('  </IMPORTDATA></BODY>');
    buf.writeln('</ENVELOPE>');
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await _share(bytes, 'vistar_tally_${_now()}.xml');
  }

  static Future<void> exportPendingFreightCsv(List<LorryReceipt> lrs) async {
    final pending = lrs.where((lr) => lr.freight.balance > 0).toList();
    final buf = StringBuffer();
    buf.writeln(
      [
        'LR No',
        'Customer',
        'Total',
        'Advance',
        'Balance',
        'Pay Type',
      ].join(','),
    );
    for (final lr in pending) {
      buf.writeln(
        [
          _csv(lr.number),
          _csv(lr.consignor.name),
          lr.freight.total.toStringAsFixed(0),
          lr.freight.advance.toStringAsFixed(0),
          lr.freight.balance.toStringAsFixed(0),
          _csv(lr.payType.label),
        ].join(','),
      );
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await _share(bytes, 'vistar_pending_${_now()}.csv');
  }

  static String _csv(String value) {
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    if (!needsQuotes) return value;
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _now() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
  }

  static Future<void> _share(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Shares/downloads arbitrary file bytes (e.g. a server-generated .xlsx).
  static Future<void> shareBytes(List<int> bytes, String filename) async {
    await _share(Uint8List.fromList(bytes), filename);
  }

  static String stamp() => _now();
}
