import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/features/lr/widgets/lr_slip_pdf.dart';
import 'package:lr_management/shared/models/consignee.dart';
import 'package:lr_management/shared/models/consignor.dart';
import 'package:lr_management/shared/models/lr_models.dart';
import 'package:lr_management/shared/models/transporter.dart';
import 'package:lr_management/shared/models/vehicle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const company = LrSlipCompany(
    name: 'Vistar Logitek Private Limited',
    tagline: 'Warehousing, Transportation & Contracts Logistics',
    address:
        'Office No. 302, 3rd Floor, MSR Capital Building, Samrat Chowk, Morwadi, Pimpri, Pune 411018.',
    gstin: 'MH 27AAECV9694A1ZZ',
  );

  LorryReceipt sample({List<InvoiceItem> items = const []}) => LorryReceipt(
        id: 'lr1',
        number: 'PUN-26-27-0817',
        date: DateTime(2026, 6, 16),
        enteredBy: 'u1',
        enteredByName: 'Chetan',
        consignor: const Consignor(
          id: 'c1',
          name: 'MRF LIMITED',
          gst: '33AAACM4154GIZU',
          city: 'Chennai',
          address: '114 Greams Road Chennai 600006',
          contact: '',
          mobile: '+91-8939538110',
          email: '',
        ),
        consignee: const Consignee(
          id: 'c2',
          name: 'BABAJI SHIVRAM CLEARING & CARRIERS PVT LTD',
          gst: '',
          location: 'Bharuch',
          address: 'PLOT No. Z-70, DAHEZ SEZ PART – 1, TALUKA VAGRA, GUJRAT - 392130',
          contact: '',
          mobile: '',
        ),
        vehicle: const Vehicle(
          id: 'v1',
          number: 'MH46DC2197',
          type: '40FT Flat Bed Trailer',
          driver: '40FT-MH46DC2197',
          driverMobile: '+91-9309094924',
        ),
        transporter: const Transporter(id: 't1', name: '', pan: '', tds: 'No'),
        route: 'SOUTH GOA → BHARUCH',
        fromCity: 'SOUTH GOA',
        toCity: 'BHARUCH',
        items: items,
        freight: const FreightDetails(freight: 25000),
        payType: PayType.tbb,
        deliveryType: DeliveryType.doorDelivery,
        status: LrStatus.booked,
      );

  test('builds a non-empty 4-copy consignment-note PDF (with items)', () async {
    final bytes = await buildLrSlipPdf(
      lr: sample(items: [
        InvoiceItem(
          invoiceNo: 'GPS/MAY/118/26',
          invoiceDate: DateTime(2026, 5, 6),
          asn: '',
          partDescription: 'Returnable Metal Crates made of Galvanized Steel',
          quantity: 0,
          weight: 26,
          grossValue: 0,
          packages: 192,
          packageType: 'Crate',
          natureOfGoods: 'Returnable Metal Crates made of Galvanized Steel-192 ,26MT',
        ),
      ]),
      company: company,
    );
    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(1000));
  });

  test('builds without throwing when the LR has no invoice items', () async {
    final bytes = await buildLrSlipPdf(lr: sample(), company: company);
    expect(bytes.length, greaterThan(1000));
  });
}
