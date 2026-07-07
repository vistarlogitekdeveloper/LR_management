import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:printing/printing.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';

class ExportService {
  ExportService._();

  /// Exports the LR list as a real Excel workbook (.xlsx). When [includeAmounts]
  /// is false (operator role) every monetary column is omitted so no figures
  /// leak into the file.
  static Future<void> exportLrsExcel(
    List<LorryReceipt> lrs, {
    bool includeAmounts = true,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

    final headers = <String>[
      'LR No', 'Date', 'Consignor', 'Consignee', 'Vehicle', 'Route',
      if (includeAmounts) ...[
        'Freight', 'Door Delivery', 'Handling', 'Insurance', 'Mathadi',
        'Advance', 'Total', 'Balance', 'Vistar Margin',
      ],
      'Pay Type', 'Status', 'EWB',
    ];
    sheet.appendRow(
      headers.map<CellValue?>((h) => TextCellValue(h)).toList(),
    );

    for (final lr in lrs) {
      sheet.appendRow(<CellValue?>[
        TextCellValue(lr.number),
        TextCellValue(formatDate(lr.date)),
        TextCellValue(lr.consignor.name),
        TextCellValue(lr.consignee.name),
        TextCellValue(lr.vehicle.number),
        TextCellValue(lr.route),
        if (includeAmounts) ...[
          DoubleCellValue(lr.freight.freight),
          DoubleCellValue(lr.freight.doorDelivery),
          DoubleCellValue(lr.freight.handling),
          DoubleCellValue(lr.freight.insurance),
          DoubleCellValue(lr.freight.mathadi),
          DoubleCellValue(lr.freight.advance),
          DoubleCellValue(lr.freight.total),
          DoubleCellValue(lr.freight.balance),
          DoubleCellValue(lr.freight.vistarMargin),
        ],
        TextCellValue(lr.payType.label),
        TextCellValue(lr.status.label),
        TextCellValue(lr.ewb?.number ?? ''),
      ]);
    }

    final bytes = excel.encode();
    if (bytes != null) {
      await shareBytes(bytes, 'vistar_lrs_${_now()}.xlsx');
    }
  }

  static Future<void> exportTally(List<LorryReceipt> lrs) async {
    final buf = StringBuffer();
    buf.writeln('<ENVELOPE>');
    buf.writeln('  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>');
    buf.writeln('  <BODY><IMPORTDATA>');
    buf.writeln('    <REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME></REQUESTDESC>');
    buf.writeln('    <REQUESTDATA>');
    for (final lr in lrs) {
      buf.writeln('      <TALLYMESSAGE>');
      buf.writeln('        <VOUCHER VCHTYPE="Sales" ACTION="Create">');
      buf.writeln('          <DATE>${formatDate(lr.date)}</DATE>');
      buf.writeln('          <VOUCHERNUMBER>${lr.number}</VOUCHERNUMBER>');
      buf.writeln('          <PARTYNAME>${lr.consignor.name}</PARTYNAME>');
      buf.writeln('          <AMOUNT>${lr.freight.total.toStringAsFixed(2)}</AMOUNT>');
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
    buf.writeln(['LR No', 'Customer', 'Total', 'Advance', 'Balance', 'Pay Type']
        .join(','));
    for (final lr in pending) {
      buf.writeln([
        _csv(lr.number),
        _csv(lr.consignor.name),
        lr.freight.total.toStringAsFixed(0),
        lr.freight.advance.toStringAsFixed(0),
        lr.freight.balance.toStringAsFixed(0),
        _csv(lr.payType.label),
      ].join(','));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await _share(bytes, 'vistar_pending_${_now()}.csv');
  }

  static String _csv(String value) {
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n');
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
