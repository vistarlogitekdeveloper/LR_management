import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/models/lr_models.dart';

/// Company header shown at the top of every consignment-note copy.
class LrSlipCompany {
  final String name;
  final String tagline;
  final String address;
  final String gstin;
  const LrSlipCompany({
    required this.name,
    required this.tagline,
    required this.address,
    required this.gstin,
  });
}

const List<String> kLrCopies = [
  'Consignor Copy',
  'Consignee Copy',
  'Lorry Copy',
  'Office Copy',
];

const double _bw = 0.7; // border width

/// Builds the multi-copy "Goods Consignment Note" PDF for [lr].
///
/// The layout mirrors the approved Vistar consignment note and intentionally
/// shows ONLY those fields — company header, vehicle/LR meta, consignor/
/// consignee block, route, e-way + driver, the goods table (with To Pay /
/// To Be Billed freight columns) and a signature footer. No charge/GST/margin
/// breakdown is rendered.
Future<Uint8List> buildLrSlipPdf({
  required LorryReceipt lr,
  required LrSlipCompany company,
  List<String> copies = kLrCopies,
  PdfPageFormat? pageFormat,
}) async {
  // Uses the built-in Helvetica font (no network) — all text is run through
  // _ascii() so it stays inside Helvetica's WinAnsi glyph set. This keeps PDF
  // generation instant and deterministic; fetching a web font here could stall
  // on the network and leave the preview spinning forever.
  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/images/vistar_logo.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    logo = null;
  }

  // Faint centered watermark behind every copy.
  pw.MemoryImage? symbol;
  try {
    final data = await rootBundle.load('assets/images/logo-symbol.png');
    symbol = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    symbol = null;
  }

  final doc = pw.Document();
  final base = (pageFormat ?? PdfPageFormat.a4).landscape;
  final format = base.copyWith(
    marginLeft: 18,
    marginRight: 18,
    marginTop: 18,
    marginBottom: 18,
  );

  pw.Widget background(pw.Context context) {
    if (symbol == null) return pw.SizedBox();
    return pw.Center(
      child: pw.Opacity(
        opacity: 0.06,
        child: pw.Image(symbol, width: 360, fit: pw.BoxFit.contain),
      ),
    );
  }

  for (final copy in copies) {
    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(pageFormat: format, buildBackground: background),
        build: (context) => _copyBody(lr, company, copy, logo),
      ),
    );
  }
  return doc.save();
}

// ---------------------------------------------------------------------------
// Text + cell helpers
// ---------------------------------------------------------------------------

pw.TextStyle _s({double size = 8, bool bold = false}) => pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

/// Normalise common typographic characters to ASCII so the slip renders cleanly
/// even when the embedded Unicode font can't be fetched (offline / strict CSP)
/// and the PDF engine falls back to Helvetica.
String _ascii(String s) => s
    .replaceAll('–', '-') // en dash
    .replaceAll('—', '-') // em dash
    .replaceAll('‘', "'")
    .replaceAll('’', "'")
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('•', '-') // bullet
    .replaceAll('₹', 'Rs ') // rupee
    .replaceAll(' ', ' '); // nbsp

pw.Widget _txt(String t, {double size = 8, bool bold = false, pw.TextAlign? align}) =>
    pw.Text(_ascii(t), style: _s(size: size, bold: bold), textAlign: align);

pw.Widget _pad(pw.Widget child, {pw.Alignment? align}) => pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
      child: child,
    );

/// "Label : value" cell — label bold, value normal (matches the reference).
pw.Widget _kv(String label, String value, {double size = 8}) => _pad(
      pw.RichText(
        text: pw.TextSpan(
          style: _s(size: size, bold: true),
          children: [
            pw.TextSpan(text: '${_ascii(label)} : '),
            pw.TextSpan(text: _ascii(value), style: _s(size: size, bold: false)),
          ],
        ),
      ),
    );

/// Centered bold header cell for the goods table.
pw.Widget _hc(String t) => pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: _txt(t, size: 7, bold: true, align: pw.TextAlign.center),
    );

const _allBorder = pw.TableBorder(
  left: pw.BorderSide(width: _bw),
  right: pw.BorderSide(width: _bw),
  top: pw.BorderSide(width: _bw),
  bottom: pw.BorderSide(width: _bw),
  horizontalInside: pw.BorderSide(width: _bw),
  verticalInside: pw.BorderSide(width: _bw),
);

pw.Widget _section({required List<pw.TableRow> rows, Map<int, pw.TableColumnWidth>? widths}) =>
    pw.Table(border: _allBorder, columnWidths: widths, children: rows);

String _num(double v) {
  if (v <= 0) return '';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

pw.Widget _copyBody(
  LorryReceipt lr,
  LrSlipCompany company,
  String copyName,
  pw.MemoryImage? logo,
) {
  final df = DateFormat('dd/MM/yyyy');
  final idf = DateFormat('dd MMM yy');

  final routeStr = (lr.fromCity.isNotEmpty || lr.toCity.isNotEmpty)
      ? [lr.fromCity, lr.toCity].where((s) => s.isNotEmpty).join(' - ')
      : lr.route;
  final driverStr = [lr.vehicle.driver, lr.vehicle.driverMobile]
      .where((s) => s.isNotEmpty)
      .join(' , ');
  final consignorContact =
      lr.consignor.mobile.isNotEmpty ? lr.consignor.mobile : lr.consignor.contact;
  final consigneeContact =
      lr.consignee.mobile.isNotEmpty ? lr.consignee.mobile : lr.consignee.contact;

  // LR-level freight lands in one of the two freight columns based on pay type
  // (To Be Billed for TBB, otherwise To Pay), on the first goods row only.
  final freightStr = _num(lr.freight.freight);
  final firstToPay = freightStr.isNotEmpty && lr.payType != PayType.tbb ? freightStr : '';
  final firstToBeBilled = freightStr.isNotEmpty && lr.payType == PayType.tbb ? freightStr : '';

  final goodsRows = <pw.TableRow>[_goodsHeaderRow()];
  if (lr.items.isEmpty) {
    goodsRows.add(_goodsRow(
      remarks: lr.remarks ?? '',
      toPay: firstToPay,
      toBeBilled: firstToBeBilled,
    ));
  } else {
    for (var i = 0; i < lr.items.length; i++) {
      final it = lr.items[i];
      goodsRows.add(_goodsRow(
        desc: it.partDescription,
        pkg: it.packages > 0 ? '${it.packages}' : '',
        wt: _num(it.weight),
        invNo: it.invoiceNo,
        invDate: it.invoiceNo.isNotEmpty ? idf.format(it.invoiceDate) : '',
        invVal: _num(it.grossValue),
        toPay: i == 0 ? firstToPay : '',
        toBeBilled: i == 0 ? firstToBeBilled : '',
        remarks: it.natureOfGoods,
      ));
    }
  }
  // Pad with blank rows so short notes keep the familiar boxed look.
  for (var i = goodsRows.length - 1; i < 3; i++) {
    goodsRows.add(_goodsRow(spacer: true));
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // 1. Company header
      _section(
        widths: const {0: pw.FixedColumnWidth(135), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(children: [
            _pad(
              logo != null
                  ? pw.Image(logo, height: 52, fit: pw.BoxFit.contain)
                  : _txt(company.name, size: 12, bold: true),
              align: pw.Alignment.center,
            ),
            _pad(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _txt(company.name, size: 14, bold: true),
              _txt(company.tagline, size: 8.5),
              pw.SizedBox(height: 2),
              _txt('Address : ${company.address}', size: 8),
              _txt('GSTIN : ${company.gstin}', size: 8, bold: true),
            ])),
          ]),
        ],
      ),
      // 2. Title
      _section(rows: [
        pw.TableRow(children: [
          pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: _txt('GOODS CONSIGNMENT NOTE - ${copyName.toUpperCase()}',
                size: 10, bold: true),
          ),
        ]),
      ]),
      // 3. Vehicle / LR meta
      _section(
        widths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FlexColumnWidth(),
          2: pw.FlexColumnWidth(),
          3: pw.FlexColumnWidth(),
        },
        rows: [
          pw.TableRow(children: [
            _kv('Vehicle Type', lr.vehicle.type),
            _kv('LR Date.', df.format(lr.date)),
            _kv('Vehicle Number', lr.vehicle.number),
            _kv('L.R. No', lr.number),
          ]),
          pw.TableRow(children: [
            _kv('ID Date', ''),
            _kv('Out Date', ''),
            _pad(_txt('')),
            _pad(_txt('')),
          ]),
        ],
      ),
      // 4. Consignor / Consignee
      _section(
        widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(children: [
            _kv('Consignor', lr.consignor.name),
            _kv('Consignee', lr.consignee.name),
          ]),
          pw.TableRow(children: [
            _kv('Consignor Address', lr.consignor.address),
            _kv('Consignee Address', lr.consignee.address),
          ]),
          pw.TableRow(children: [
            _kv('Consignor Contact No', consignorContact),
            _kv('Consignee Contact No', consigneeContact),
          ]),
          pw.TableRow(children: [
            _kv('Consignor GSTIN', lr.consignor.gst),
            _kv('Consignee GSTIN', lr.consignee.gst),
          ]),
        ],
      ),
      // 5. Route
      _section(rows: [
        pw.TableRow(children: [_kv('Route', routeStr)]),
      ]),
      // 6. E-way bill + driver
      _section(
        widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(children: [
            _kv('Goods Eway Bill Number', lr.ewb?.number ?? ''),
            _kv('Driver Name', driverStr),
          ]),
        ],
      ),
      // 7. Goods table
      pw.Table(
        border: _allBorder,
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FixedColumnWidth(46),
          2: pw.FixedColumnWidth(46),
          3: pw.FlexColumnWidth(1.6),
          4: pw.FlexColumnWidth(1.4),
          5: pw.FixedColumnWidth(52),
          6: pw.FixedColumnWidth(96),
          7: pw.FlexColumnWidth(2),
        },
        children: goodsRows,
      ),
      // 8. Total
      _section(rows: [
        pw.TableRow(children: [
          _pad(_txt('Total-${lr.totalPackages}', size: 8, bold: true)),
        ]),
      ]),
      // 9. Created / received
      _section(
        widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(children: [
            _kv('Created By', lr.enteredByName),
            _kv('Received By', ''),
          ]),
        ],
      ),
      // 10. Footer
      _section(rows: [
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 26, 6, 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _txt('For ${company.name}', size: 9, bold: true),
                _txt('Date, Signature & Stamp', size: 9, bold: true),
              ],
            ),
          ),
        ]),
      ]),
    ],
  );
}

pw.TableRow _goodsHeaderRow() => pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _hc('Description of Goods'),
        _hc('NO OF\nPACKAGING'),
        _hc('ACTUAL\nWEIGHT'),
        _hc('Invoice No'),
        _hc('Invoice Date'),
        _hc('Invoice\nValue'),
        _freightHeaderCell(),
        _hc('REMARKS'),
      ],
    );

/// The grouped FREIGHT header: "FREIGHT" over a "TO PAY | TO BE BILLED" split,
/// kept inside one parent column so it always aligns with the data cell.
pw.Widget _freightHeaderCell() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: _txt('FREIGHT', size: 7, bold: true),
        ),
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(width: _bw)),
          ),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: _txt('TO PAY', size: 6, bold: true),
              ),
            ),
            pw.Expanded(
              child: pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(left: pw.BorderSide(width: _bw)),
                ),
                child: _txt('TO BE BILLED', size: 6, bold: true),
              ),
            ),
          ]),
        ),
      ],
    );

pw.Widget _freightDataCell(String toPay, String toBeBilled) => pw.Row(
      children: [
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3.5),
            child: _txt(toPay, size: 7.5),
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3.5),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(width: _bw)),
            ),
            child: _txt(toBeBilled, size: 7.5),
          ),
        ),
      ],
    );

pw.TableRow _goodsRow({
  String desc = '',
  String pkg = '',
  String wt = '',
  String invNo = '',
  String invDate = '',
  String invVal = '',
  String toPay = '',
  String toBeBilled = '',
  String remarks = '',
  bool spacer = false,
}) {
  pw.Widget cell(String t, {pw.Alignment align = pw.Alignment.centerLeft}) => pw.Container(
        alignment: align,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        child: _txt(t, size: 7.5),
      );
  return pw.TableRow(children: [
    // give blank rows a little height so the table reads as ruled rows
    spacer
        ? pw.Container(height: 12, padding: const pw.EdgeInsets.symmetric(horizontal: 5))
        : cell(desc),
    cell(pkg, align: pw.Alignment.center),
    cell(wt, align: pw.Alignment.center),
    cell(invNo),
    cell(invDate),
    cell(invVal, align: pw.Alignment.center),
    _freightDataCell(toPay, toBeBilled),
    cell(remarks),
  ]);
}
