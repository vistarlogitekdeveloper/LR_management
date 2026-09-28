import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';

/// The LR detail screen, rendered as plain text for the clipboard.
///
/// Dispatchers forward LR details into WhatsApp, email and customers' own
/// portals dozens of times a day. Selecting the screen by hand gets them the
/// labels, the layout and whatever else the mouse dragged across; this gets
/// them the same facts in the order they read them on screen.
///
/// PLAIN text on purpose — no markdown, no box drawing. The destination is
/// usually a chat box or an ERP field that renders neither, and a stray `*`
/// reads as a typo there.
///
/// PERMISSIONS ARE NOT COSMETIC HERE. The client holds the whole [LorryReceipt]
/// — the server sends it, and the screen merely declines to draw the rate rows
/// a user may not see. A copy that walked the object would therefore hand
/// somebody, in their own clipboard, the exact figures the UI is hiding from
/// them. So the same two gates that control the Freight card control this, and
/// they are required arguments rather than optional flags: a caller cannot
/// forget them.
String buildLrSummaryText(
  LorryReceipt lr, {
  required bool includeTransporterRate,
  required bool includeVistarMargin,
}) {
  final out = StringBuffer();

  // Header: what the page's title bar shows.
  out.writeln(lr.number);
  out.writeln('${formatDate(lr.date)} · ${lr.status.label}');

  _section(out, 'PARTIES', [
    ('Customer', lr.customerName),
    ('Consignor', lr.consignor.name),
    ('Consignor GST', lr.consignor.gst),
    ('Consignor address', lr.consignor.address),
    ('Consignee', lr.consignee.name),
    ('Consignee GST', lr.consignee.gst),
    ('Delivery', lr.consignee.location),
  ]);

  _section(out, 'VEHICLE & ROUTE', [
    ('Vehicle', _join([lr.vehicle.number, lr.vehicle.type], ' · ')),
    ('Driver', _driver(lr)),
    ('Capacity', lr.vehicle.capacity),
    ('Route', lr.route),
    ('Transporter', lr.transporter.name),
  ]);

  if (lr.items.isNotEmpty) {
    out
      ..writeln()
      ..writeln('INVOICE & GOODS');
    for (final item in lr.items) {
      // One line per invoice: the fields a consignee actually asks about, and
      // nothing that is zero. A row of "Qty: 0  Weight: 0 kg  Value: ₹0" is
      // noise in a chat message even though the screen shows it in a grid.
      final parts = <String>[
        item.invoiceNo,
        formatDate(item.invoiceDate),
        if (item.packageType.trim().isNotEmpty) item.packageType.trim(),
        if (item.packages > 0) '${item.packages} pkg',
        if (item.quantity > 0) 'qty ${item.quantity}',
        if (item.weight > 0) '${pctText(item.weight)} kg',
        if (item.grossValue > 0) inr(item.grossValue),
        if (item.asn.trim().isNotEmpty) 'ASN ${item.asn.trim()}',
      ].where((p) => p.trim().isNotEmpty).toList();
      out.writeln('- ${parts.join(' · ')}');
    }
  }

  if (includeTransporterRate) {
    _section(out, 'FREIGHT', [
      ('Freight', inr(lr.freight.freight)),
      ('Door Delivery', _money(lr.freight.doorDelivery)),
      ('Handling', _money(lr.freight.handling)),
      ('Insurance', _money(lr.freight.insurance)),
      ('Additional Freight Charges', _money(lr.freight.additionalFreight)),
      ('Halting Charge', _money(lr.freight.haltingCharge)),
      ('Total', inr(lr.freight.total)),
      (
        'Advance (${pctText(lr.freight.advancePercent)}%)',
        _money(lr.freight.advance),
      ),
      ('Balance', inr(lr.freight.balance)),
      ('Mathadi', _money(lr.freight.mathadi)),
    ]);
  }

  // Gated separately from the rates above: a user may be allowed to see what
  // the transporter is paid without being allowed to see what Vistar keeps.
  if (includeVistarMargin) {
    out
      ..writeln()
      ..writeln('Vistar Margin: ${inr(lr.freight.vistarMargin)}');
  }

  return out.toString().trimRight();
}

/// Writes a headed block, skipping it entirely when every row is empty — an
/// empty "PARTIES" heading is worse than no heading.
void _section(StringBuffer out, String title, List<(String, String)> rows) {
  final present = rows
      .where((r) => r.$2.trim().isNotEmpty)
      .toList(growable: false);
  if (present.isEmpty) return;
  out
    ..writeln()
    ..writeln(title);
  for (final (label, value) in present) {
    out.writeln('$label: ${value.trim()}');
  }
}

/// Zero is omitted rather than printed. Every optional charge on an LR is
/// usually zero, and ten "₹0" lines bury the three figures that are not.
String _money(double v) => v == 0 ? '' : inr(v);

String _driver(LorryReceipt lr) {
  final name = lr.vehicle.driver.trim();
  final mobile = lr.vehicle.driverMobile.trim();
  if (name.isEmpty && mobile.isEmpty) return '';
  if (mobile.isEmpty) return name;
  if (name.isEmpty) return mobile;
  return '$name ($mobile)';
}

String _join(List<String> parts, String sep) =>
    parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(sep);
