import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/lr/utils/lr_summary_text.dart';
import 'package:lr_management/shared/models/consignee.dart';
import 'package:lr_management/shared/models/consignor.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/models/transporter.dart';
import 'package:lr_management/shared/models/vehicle.dart';

/// The Copy button on the LR detail screen produces this text.
///
/// The gating tests are the ones that matter: the client is holding the full
/// LorryReceipt, including rates the screen deliberately does not draw, so a
/// copy that ignored permissions would put those figures in a user's clipboard
/// and from there into a chat message.
void main() {
  LorryReceipt sample({
    List<InvoiceItem> items = const [],
    FreightDetails? freight,
  }) => LorryReceipt(
    id: 'lr1',
    number: 'LR/SBN/26-27/02130',
    date: DateTime(2026, 9, 18),
    enteredBy: 'u1',
    customerName: 'ENDURANCE TECHONLOGIES LTD K226/2',
    consignor: const Consignor(
      id: 'c1',
      name: 'ENDURANCE TECHONLOGIES LTD K226/2',
      gst: '27AAACE7066P1Z3',
      city: 'Sambhajinagar',
      address: 'K226/2 waluj MIDC CHH. Sambhajinagar 431136 MH',
      contact: '',
      mobile: '',
      email: '',
    ),
    consignee: const Consignee(
      id: 'c2',
      name: 'ENDURANCE TECHNOLOGIES LIMITED CHENNAI',
      gst: '33AAACE7066P1ZA',
      location: 'Chennai',
      address: '',
      contact: '',
      mobile: '',
    ),
    vehicle: const Vehicle(
      id: 'v1',
      number: 'MH41AU7298',
      type: 'Closed Container',
      driver: 'Ramesh',
      driverMobile: '+91-9000000000',
    ),
    transporter: const Transporter(id: 't1', name: 'ACME', pan: '', tds: 'No'),
    route: 'WALUJ → ORGADAM, CHENNAI PICKUP 1MT',
    fromCity: 'WALUJ',
    toCity: 'CHENNAI',
    items: items,
    freight:
        freight ??
        const FreightDetails(freight: 24000, advancePercent: 90, mathadi: 0),
    payType: PayType.tbb,
    deliveryType: DeliveryType.doorDelivery,
    status: LrStatus.booked,
  );

  String copy(LorryReceipt lr, {bool rate = true, bool margin = true}) =>
      buildLrSummaryText(
        lr,
        includeTransporterRate: rate,
        includeVistarMargin: margin,
      );

  group('identity and parties', () {
    test('leads with the LR number, date and status', () {
      final text = copy(sample());
      expect(text.split('\n').first, 'LR/SBN/26-27/02130');
      expect(text, contains('18 Sep 2026'));
      expect(text, contains('Booked'));
    });

    test('carries the fields a consignee is actually asked for', () {
      final text = copy(sample());
      expect(text, contains('Consignor GST: 27AAACE7066P1Z3'));
      expect(text, contains('Consignee GST: 33AAACE7066P1ZA'));
      expect(text, contains('Delivery: Chennai'));
      expect(text, contains('Route: WALUJ → ORGADAM, CHENNAI PICKUP 1MT'));
      expect(text, contains('Driver: Ramesh (+91-9000000000)'));
    });

    test('an empty field is omitted, never printed as a bare label', () {
      // This LR has no consignee address; "Consignee address:" with nothing
      // after it reads as missing data rather than as absent data.
      final text = copy(sample());
      expect(text, isNot(contains('address: \n')));
      expect(text, isNot(matches(RegExp(r':\s*$', multiLine: true))));
    });
  });

  group('rate permissions', () {
    final withMoney = sample(
      freight: const FreightDetails(
        freight: 24000,
        advancePercent: 90,
        vistarMargin: 3170,
      ),
    );

    test('a user who may see rates gets them', () {
      final text = copy(withMoney);
      expect(text, contains('FREIGHT'));
      expect(text, contains('Freight: ₹24,000'));
      expect(text, contains('Total:'));
      expect(text, contains('Balance:'));
    });

    test('a user who may NOT see rates gets no figures at all', () {
      final text = copy(withMoney, rate: false, margin: false);
      expect(text, isNot(contains('FREIGHT')));
      expect(text, isNot(contains('24,000')));
      expect(text, isNot(contains('Total:')));
      expect(text, isNot(contains('Balance:')));
      // The rest of the LR is still copyable — the gate redacts, not disables.
      expect(text, contains('LR/SBN/26-27/02130'));
      expect(text, contains('Consignor GST: 27AAACE7066P1Z3'));
    });

    test('the margin is gated separately from the transporter rate', () {
      // A user may see what the transporter is paid without being allowed to
      // see what Vistar keeps, so the two gates cannot be collapsed into one.
      final rateOnly = copy(withMoney, margin: false);
      expect(rateOnly, contains('Freight: ₹24,000'));
      expect(rateOnly, isNot(contains('Vistar Margin')));

      final marginOnly = copy(withMoney, rate: false);
      expect(marginOnly, contains('Vistar Margin: ₹3,170'));
      expect(marginOnly, isNot(contains('Freight: ₹24,000')));
    });

    test('zero charges are dropped so the real figures stand out', () {
      final text = copy(withMoney);
      expect(text, isNot(contains('Handling')));
      expect(text, isNot(contains('Insurance')));
      expect(text, isNot(contains('Halting Charge')));
    });
  });

  group('invoice items', () {
    test('one line per invoice, with the zero columns dropped', () {
      final text = copy(
        sample(
          items: [
            InvoiceItem(
              invoiceNo: '261270248125',
              invoiceDate: DateTime(2026, 9, 18),
              asn: '',
              partDescription: '',
              quantity: 0,
              weight: 0,
              grossValue: 0,
              packages: 3,
              packageType: 'pallet',
              natureOfGoods: '',
            ),
          ],
        ),
      );
      expect(text, contains('INVOICE & GOODS'));
      expect(text, contains('261270248125'));
      expect(text, contains('pallet'));
      expect(text, contains('3 pkg'));
      // Screen shows "Qty: 0  Weight: 0 kg  Value: ₹0"; a chat message must not.
      expect(text, isNot(contains('qty 0')));
      expect(text, isNot(contains('0 kg')));
    });

    test('the section disappears entirely when there are no items', () {
      expect(copy(sample()), isNot(contains('INVOICE & GOODS')));
    });
  });

  test('the text is plain — no markdown a chat client would mangle', () {
    final text = copy(sample());
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('|')));
    expect(text.trim(), text, reason: 'no leading or trailing blank lines');
  });
}
