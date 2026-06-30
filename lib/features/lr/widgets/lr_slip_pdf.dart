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

/// The traditional four recipient copies. The print screen now emits a single
/// copy by default; pass this as [buildLrSlipPdf]'s `copies` to get the old
/// four-page consignment note (one labelled page per recipient).
const List<String> kLrCopies = [
  'Consignor Copy',
  'Consignee Copy',
  'Lorry Copy',
  'Office Copy',
];

/// Single unlabelled copy — the default for [buildLrSlipPdf].
const List<String> kLrSingleCopy = [''];

const double _bw = 0.7; // border width

// Goods-table column widths. Defined once so the ruled table and the blank
// "filler" that stretches it to the page bottom keep their dividers aligned.
// Fixed columns are absolute points; flex columns share the remaining width by
// the given ratio (mirrored as integer flex weights in the filler below).
const Map<int, pw.TableColumnWidth> _goodsWidths = {
  0: pw.FlexColumnWidth(3),
  1: pw.FixedColumnWidth(46),
  2: pw.FixedColumnWidth(50),
  3: pw.FixedColumnWidth(50),
  4: pw.FlexColumnWidth(1.5),
  5: pw.FlexColumnWidth(1.3),
  6: pw.FixedColumnWidth(56),
  7: pw.FlexColumnWidth(1.9),
};

/// Builds the "Goods Consignment Note" PDF for [lr].
///
/// Emits a single copy by default ([kLrSingleCopy]); pass [kLrCopies] to get the
/// older four-page layout (one labelled page per recipient).
///
/// The layout mirrors the approved Vistar consignment note and intentionally
/// shows ONLY those fields — company header, vehicle/LR meta, consignor/
/// consignee block, route, e-way + driver, the goods table and a signature
/// footer. No freight/charge/GST/margin amounts are rendered.
///
/// The note is sized to fill the whole page: the goods table stretches down to
/// push the signature footer to the bottom edge, and the type scales with how
/// much content there is so a sparse LR reads large while a dense one still
/// shows every row without being cut off.
Future<Uint8List> buildLrSlipPdf({
  required LorryReceipt lr,
  required LrSlipCompany company,
  List<String> copies = kLrSingleCopy,
  PdfPageFormat? pageFormat,
}) async {
  // Uses the built-in Helvetica font (no network) — all text is run through
  // _ascii() so it stays inside Helvetica's WinAnsi glyph set. This keeps PDF
  // generation instant and deterministic; fetching a web font here could stall
  // on the network and leave the preview spinning forever.
  // Use small, PDF-optimized copies (~60 KB each). The source PNGs are ~2 MB /
  // 1536x1024 — embedding and rasterizing those on web made the preview hang on
  // a spinner. The slip only draws the logo ~52pt tall and the watermark ~360pt.
  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/images/vistar_logo_pdf.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    logo = null;
  }

  // Faint centered watermark behind every copy.
  pw.MemoryImage? symbol;
  try {
    final data = await rootBundle.load('assets/images/logo_symbol_pdf.png');
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
        pageTheme: pw.PageTheme(
          pageFormat: format,
          buildBackground: background,
        ),
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
    .replaceAll(' ', ' '); // nbsp

pw.Widget _txt(
  String t, {
  double size = 8,
  bool bold = false,
  pw.TextAlign? align,
}) => pw.Text(
  _ascii(t),
  style: _s(size: size, bold: bold),
  textAlign: align,
);

pw.Widget _pad(pw.Widget child, {pw.Alignment? align, double vertical = 4}) =>
    pw.Container(
      alignment: align,
      padding: pw.EdgeInsets.symmetric(horizontal: 5, vertical: vertical),
      child: child,
    );

/// "Label : value" cell — label bold, value normal (matches the reference).
/// Pass [valueBold] to bold the value too (used for the emphasised meta row).
pw.Widget _kv(
  String label,
  String value, {
  double size = 8,
  bool valueBold = false,
  double vertical = 4,
}) => _pad(
  vertical: vertical,
  pw.RichText(
    text: pw.TextSpan(
      style: _s(size: size, bold: true),
      children: [
        pw.TextSpan(text: '${_ascii(label)} : '),
        pw.TextSpan(
          text: _ascii(value),
          style: _s(size: size, bold: valueBold),
        ),
      ],
    ),
  ),
);

/// Centered bold header cell for the goods table.
pw.Widget _hc(String t, double size) => pw.Container(
  alignment: pw.Alignment.center,
  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
  child: _txt(t, size: size, bold: true, align: pw.TextAlign.center),
);

const _allBorder = pw.TableBorder(
  left: pw.BorderSide(width: _bw),
  right: pw.BorderSide(width: _bw),
  top: pw.BorderSide(width: _bw),
  bottom: pw.BorderSide(width: _bw),
  horizontalInside: pw.BorderSide(width: _bw),
  verticalInside: pw.BorderSide(width: _bw),
);

pw.Widget _section({
  required List<pw.TableRow> rows,
  Map<int, pw.TableColumnWidth>? widths,
}) => pw.Table(border: _allBorder, columnWidths: widths, children: rows);

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
  final dtf = DateFormat('dd/MM/yy HH:mm');

  // Type scales with how many goods rows there are so a short note reads large
  // and a long one still fits every row on the single page (no cut-off). The
  // goods table then stretches via _goodsFiller() to reach the page bottom.
  // The goods-table filler does the page-filling, so the scale only needs to be
  // big enough to read and small enough that the fixed sections + footer always
  // fit (no clipped jurisdiction line). It steps down as rows are added so even
  // a long list shows every row on the one page.
  final itemCount = lr.items.length;
  final double s; // master scale for the whole note
  if (itemCount <= 3) {
    s = 1.10;
  } else if (itemCount <= 6) {
    s = 1.03;
  } else if (itemCount <= 9) {
    s = 0.97;
  } else if (itemCount <= 13) {
    s = 0.90;
  } else {
    s = 0.84;
  }
  // Goods rows get an extra squeeze for dense notes to protect against cut-off.
  final goodsFont = (itemCount > 10 ? 7.6 : 8.0) * s;
  final goodsPadV = (itemCount > 10 ? 2.2 : 3.2) * s;
  final padV = 4.0 * s;

  final routeStr = (lr.fromCity.isNotEmpty || lr.toCity.isNotEmpty)
      ? [lr.fromCity, lr.toCity].where((str) => str.isNotEmpty).join(' - ')
      : lr.route;
  final driverStr = [
    lr.vehicle.driver,
    lr.vehicle.driverMobile,
  ].where((str) => str.isNotEmpty).join(' , ');
  final consignorContact = lr.consignor.mobile.isNotEmpty
      ? lr.consignor.mobile
      : lr.consignor.contact;
  final consigneeContact = lr.consignee.mobile.isNotEmpty
      ? lr.consignee.mobile
      : lr.consignee.contact;

  final goodsRows = <pw.TableRow>[_goodsHeaderRow(7.6 * s)];
  if (lr.items.isEmpty) {
    goodsRows.add(_goodsRow(remarks: lr.remarks ?? '', size: goodsFont, padV: goodsPadV));
  } else {
    for (var i = 0; i < lr.items.length; i++) {
      final it = lr.items[i];
      goodsRows.add(
        _goodsRow(
          desc: it.partDescription,
          pkg: it.packages > 0 ? '${it.packages}' : '',
          wt: _num(it.weight),
          chargeableWt: _num(it.chargeableWeight),
          invNo: it.invoiceNo,
          invDate: it.invoiceNo.isNotEmpty ? idf.format(it.invoiceDate) : '',
          invVal: _num(it.grossValue),
          remarks: it.natureOfGoods,
          size: goodsFont,
          padV: goodsPadV,
        ),
      );
    }
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // 1. Company header
      _section(
        widths: {0: pw.FixedColumnWidth(135 * s), 1: const pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(
            children: [
              _pad(
                logo != null
                    ? pw.Image(logo, height: 52 * s, fit: pw.BoxFit.contain)
                    : _txt(company.name, size: 12 * s, bold: true),
                align: pw.Alignment.center,
              ),
              _pad(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _txt(company.name, size: 15 * s, bold: true),
                    _txt(company.tagline, size: 9 * s),
                    pw.SizedBox(height: 2),
                    _txt('Address : ${company.address}', size: 8.5 * s),
                    _txt('GSTIN : ${company.gstin}', size: 8.5 * s, bold: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      // 2. Title
      _section(
        rows: [
          pw.TableRow(
            children: [
              pw.Container(
                alignment: pw.Alignment.center,
                padding: pw.EdgeInsets.symmetric(vertical: 5 * s),
                child: _txt(
                  copyName.trim().isEmpty
                      ? 'GOODS CONSIGNMENT NOTE'
                      : 'GOODS CONSIGNMENT NOTE - ${copyName.toUpperCase()}',
                  size: 11.5 * s,
                  bold: true,
                ),
              ),
            ],
          ),
        ],
      ),
      // 3. Vehicle / LR meta
      _section(
        widths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FlexColumnWidth(),
          2: pw.FlexColumnWidth(),
          3: pw.FlexColumnWidth(),
        },
        rows: [
          pw.TableRow(
            children: [
              _kv('Vehicle Capacity', lr.capacityLabel,
                  size: 11 * s, valueBold: true, vertical: padV),
              _kv('LR Date.', df.format(lr.date),
                  size: 11 * s, valueBold: true, vertical: padV),
              _kv('Vehicle Number', lr.vehicle.number,
                  size: 11 * s, valueBold: true, vertical: padV),
              _kv('L.R. No', lr.number,
                  size: 11 * s, valueBold: true, vertical: padV),
            ],
          ),
          pw.TableRow(
            children: [
              _kv('ID Date',
                  lr.inDateTime != null ? dtf.format(lr.inDateTime!) : '',
                  size: 9 * s, vertical: padV),
              _kv('Out Date',
                  lr.outDateTime != null ? dtf.format(lr.outDateTime!) : '',
                  size: 9 * s, vertical: padV),
              _kv('Order No', lr.orderNo, size: 9 * s, vertical: padV),
              _pad(_txt(''), vertical: padV),
            ],
          ),
        ],
      ),
      // 4. Consignor / Consignee
      _section(
        widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(
            children: [
              _kv('Consignor', lr.consignor.name, size: 9.5 * s, vertical: padV),
              _kv('Consignee', lr.consignee.name, size: 9.5 * s, vertical: padV),
            ],
          ),
          pw.TableRow(
            children: [
              _kv('Consignor Address', lr.consignor.address,
                  size: 9.5 * s, vertical: padV),
              _kv('Consignee Address', lr.consignee.address,
                  size: 9.5 * s, vertical: padV),
            ],
          ),
          pw.TableRow(
            children: [
              _kv('Consignor Contact No', consignorContact,
                  size: 9.5 * s, vertical: padV),
              _kv('Consignee Contact No', consigneeContact,
                  size: 9.5 * s, vertical: padV),
            ],
          ),
          pw.TableRow(
            children: [
              _kv('Consignor GSTIN', lr.consignor.gst,
                  size: 9.5 * s, vertical: padV),
              _kv('Consignee GSTIN', lr.consignee.gst,
                  size: 9.5 * s, vertical: padV),
            ],
          ),
        ],
      ),
      // 5. Route
      _section(
        rows: [
          pw.TableRow(
              children: [_kv('Route', routeStr, size: 9.5 * s, vertical: padV)]),
        ],
      ),
      // 6. E-way bill + driver
      _section(
        widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(
            children: [
              _kv('Goods Eway Bill Number', lr.ewb?.number ?? '',
                  size: 9.5 * s, vertical: padV),
              _kv('Driver Name', driverStr, size: 9.5 * s, vertical: padV),
            ],
          ),
        ],
      ),
      // 7. Goods table, then a filler that continues the column rules down to
      // the footer. Together they stretch the ruled table to fill the page so
      // there's no blank band and the signature footer sits on the page edge.
      // (The filler is a direct flex child of the page column — nesting it
      // inside an inner Column suppressed the table's paint when the filler
      // was tall, so keep these as siblings.)
      pw.Table(
        border: _allBorder,
        columnWidths: _goodsWidths,
        children: goodsRows,
      ),
      pw.Expanded(child: _goodsFiller()),
      // 8. Total
      _section(
        rows: [
          pw.TableRow(
            children: [
              _pad(_txt('Total-${lr.totalPackages}', size: 10 * s, bold: true),
                  vertical: padV),
            ],
          ),
        ],
      ),
      // 9. Created / received
      _section(
        widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
        rows: [
          pw.TableRow(
            children: [
              _kv('Created By', lr.enteredByName, size: 9.5 * s, vertical: padV),
              _kv('Received By', '', size: 9.5 * s, vertical: padV),
            ],
          ),
        ],
      ),
      // 10. Signatures — recipient / sender / authorised (matches the paper note)
      _section(
        widths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FlexColumnWidth(),
          2: pw.FlexColumnWidth(),
        },
        rows: [
          pw.TableRow(
            children: [
              _signCell(
                'Received above materials in good and sound condition as per the terms and conditions overleaf.',
                "Recipient's Signature & Stamp",
                s,
              ),
              _signCell(
                'I accept the terms & conditions as per overleaf.',
                "Sender's Name & Signature",
                s,
              ),
              _signCell('For ${company.name}', 'Authorised Signatory', s),
            ],
          ),
        ],
      ),
      // 11. Jurisdiction + copy legend
      _section(
        rows: [
          pw.TableRow(
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4 * s,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _txt('SUBJECT TO PUNE JURISDICTION',
                        size: 8 * s, bold: true),
                    pw.SizedBox(height: 2),
                    _txt(
                      '1) White - Sender Copy   2) Pink - Acknowledgement Copy   3) Blue - Recipient Copy   4) News - Office Copy',
                      size: 7.5 * s,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The blank lower portion of the goods table. It continues the 8 column
/// dividers down to the page bottom so the ruled table looks like one tall
/// box rather than a few rows above empty space. The flex weights and fixed
/// widths mirror [_goodsWidths] exactly so the dividers line up with the rows.
pw.Widget _goodsFiller() {
  pw.Widget divider() => pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(right: pw.BorderSide(width: _bw)),
        ),
      );
  pw.Widget flexCol(int flex) => pw.Expanded(flex: flex, child: divider());
  pw.Widget fixedCol(double width) =>
      pw.SizedBox(width: width, child: divider());

  return pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(width: _bw),
        right: pw.BorderSide(width: _bw),
        bottom: pw.BorderSide(width: _bw),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        flexCol(30), // 0: FlexColumnWidth(3)
        fixedCol(46), // 1
        fixedCol(50), // 2
        fixedCol(50), // 3
        flexCol(15), // 4: FlexColumnWidth(1.5)
        flexCol(13), // 5: FlexColumnWidth(1.3)
        fixedCol(56), // 6
        pw.Expanded(flex: 19, child: pw.SizedBox()), // 7: no inner divider
      ],
    ),
  );
}

/// A signature block: small terms text, a gap to sign, then the bold label.
pw.Widget _signCell(String terms, String label, double s) => pw.Padding(
  padding: const pw.EdgeInsets.fromLTRB(6, 6, 6, 6),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      _txt(terms, size: 7.5 * s),
      pw.SizedBox(height: 28 * s),
      _txt(label, size: 9 * s, bold: true),
    ],
  ),
);

pw.TableRow _goodsHeaderRow(double size) => pw.TableRow(
  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
  children: [
    _hc('Description of Goods', size),
    _hc('NO OF\nPACKAGING', size),
    _hc('ACTUAL\nWEIGHT', size),
    _hc('CHARGEABLE\nWEIGHT', size),
    _hc('Invoice No', size),
    _hc('Invoice Date', size),
    _hc('Invoice\nValue', size),
    _hc('REMARKS', size),
  ],
);

pw.TableRow _goodsRow({
  String desc = '',
  String pkg = '',
  String wt = '',
  String chargeableWt = '',
  String invNo = '',
  String invDate = '',
  String invVal = '',
  String remarks = '',
  double size = 7.5,
  double padV = 3.5,
}) {
  pw.Widget cell(String t, {pw.Alignment align = pw.Alignment.centerLeft}) =>
      pw.Container(
        alignment: align,
        padding: pw.EdgeInsets.symmetric(horizontal: 5, vertical: padV),
        child: _txt(t, size: size),
      );
  return pw.TableRow(
    children: [
      cell(desc),
      cell(pkg, align: pw.Alignment.center),
      cell(wt, align: pw.Alignment.center),
      cell(chargeableWt, align: pw.Alignment.center),
      cell(invNo),
      cell(invDate),
      cell(invVal, align: pw.Alignment.center),
      cell(remarks),
    ],
  );
}
