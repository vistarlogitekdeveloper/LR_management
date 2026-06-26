import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';

class ExportService {
  ExportService._();

  static Future<void> exportLrsCsv(List<LorryReceipt> lrs) async {
    final buf = StringBuffer();
    buf.writeln(
      [
        'LR No',
        'Date',
        'Consignor',
        'Consignee',
        'Vehicle',
        'Route',
        'Freight',
        'Door Delivery',
        'Handling',
        'Insurance',
        'Mathadi',
        'Advance',
        'Total',
        'Balance',
        'Vistar Margin',
        'Pay Type',
        'Status',
        'EWB',
      ].join(','),
    );
    for (final lr in lrs) {
      buf.writeln([
        _csv(lr.number),
        _csv(formatDate(lr.date)),
        _csv(lr.consignor.name),
        _csv(lr.consignee.name),
        _csv(lr.vehicle.number),
        _csv(lr.route),
        lr.freight.freight.toStringAsFixed(0),
        lr.freight.doorDelivery.toStringAsFixed(0),
        lr.freight.handling.toStringAsFixed(0),
        lr.freight.insurance.toStringAsFixed(0),
        lr.freight.mathadi.toStringAsFixed(0),
        lr.freight.advance.toStringAsFixed(0),
        lr.freight.total.toStringAsFixed(0),
        lr.freight.balance.toStringAsFixed(0),
        lr.freight.vistarMargin.toStringAsFixed(0),
        _csv(lr.payType.label),
        _csv(lr.status.label),
        _csv(lr.ewb?.number ?? ''),
      ].join(','));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await _share(bytes, 'vistar_lrs_${_now()}.csv');
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
