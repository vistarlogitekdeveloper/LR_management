import 'attachment.dart';
import 'consignee.dart';
import 'consignor.dart';
import 'transporter.dart';
import 'vehicle.dart';

enum LrStatus { booked, inTransit, delivered, cancelled }

extension LrStatusX on LrStatus {
  String get label => switch (this) {
        LrStatus.booked => 'Booked',
        LrStatus.inTransit => 'In Transit',
        LrStatus.delivered => 'Delivered',
        LrStatus.cancelled => 'Cancelled',
      };

  static LrStatus fromLabel(String s) => LrStatus.values.firstWhere(
        (e) => e.label == s,
        orElse: () => LrStatus.booked,
      );
}

enum PayType { toPay, paid, tbb, foc }

extension PayTypeX on PayType {
  String get label => switch (this) {
        PayType.toPay => 'To Pay',
        PayType.paid => 'Paid',
        PayType.tbb => 'TBB',
        PayType.foc => 'FOC',
      };

  static PayType fromLabel(String s) => PayType.values.firstWhere(
        (e) => e.label == s,
        orElse: () => PayType.tbb,
      );
}

enum DeliveryType {
  doorDelivery,
  godownDelivery,
  warehousePickup,
  customerPickup,
}

extension DeliveryTypeX on DeliveryType {
  String get label => switch (this) {
        DeliveryType.doorDelivery => 'Door Delivery',
        DeliveryType.godownDelivery => 'Godown Delivery',
        DeliveryType.warehousePickup => 'Warehouse Pickup',
        DeliveryType.customerPickup => 'Customer Pickup',
      };
}

class InvoiceItem {
  final String invoiceNo;
  final DateTime invoiceDate;
  final String asn;
  final String partDescription;
  final int quantity;
  final double weight;
  final double grossValue;
  final int packages;
  final String packageType;
  final String natureOfGoods;

  const InvoiceItem({
    required this.invoiceNo,
    required this.invoiceDate,
    required this.asn,
    required this.partDescription,
    required this.quantity,
    required this.weight,
    required this.grossValue,
    required this.packages,
    required this.packageType,
    required this.natureOfGoods,
  });
}

class FreightDetails {
  final double freight;
  final double collection;
  final double doorDelivery;
  final double handling;
  final double insurance;
  final double gst;
  final double advance;
  final double mathadi;
  final double vistarMargin;
  final String advancePaidBy;
  final String tripLeadBy;

  const FreightDetails({
    this.freight = 0,
    this.collection = 0,
    this.doorDelivery = 0,
    this.handling = 0,
    this.insurance = 0,
    this.gst = 0,
    this.advance = 0,
    this.mathadi = 0,
    this.vistarMargin = 0,
    this.advancePaidBy = 'Vistar',
    this.tripLeadBy = 'Operations',
  });

  double get total => freight + doorDelivery + handling + gst + insurance;
  double get balance => total - advance;

  FreightDetails copyWith({
    double? freight,
    double? collection,
    double? doorDelivery,
    double? handling,
    double? insurance,
    double? gst,
    double? advance,
    double? mathadi,
    double? vistarMargin,
    String? advancePaidBy,
    String? tripLeadBy,
  }) {
    return FreightDetails(
      freight: freight ?? this.freight,
      collection: collection ?? this.collection,
      doorDelivery: doorDelivery ?? this.doorDelivery,
      handling: handling ?? this.handling,
      insurance: insurance ?? this.insurance,
      gst: gst ?? this.gst,
      advance: advance ?? this.advance,
      mathadi: mathadi ?? this.mathadi,
      vistarMargin: vistarMargin ?? this.vistarMargin,
      advancePaidBy: advancePaidBy ?? this.advancePaidBy,
      tripLeadBy: tripLeadBy ?? this.tripLeadBy,
    );
  }
}

class EwayBill {
  final String number;
  final DateTime? expiry;
  final String loadType;

  const EwayBill({
    required this.number,
    this.expiry,
    this.loadType = 'Full Load',
  });
}

class LorryReceipt {
  final String id;
  final String number;
  final DateTime date;
  final String enteredBy;
  final Consignor consignor;
  final Consignee consignee;
  final Vehicle vehicle;
  final Transporter transporter;
  final String route;
  final String fromCity;
  final String toCity;
  final List<InvoiceItem> items;
  final FreightDetails freight;
  final EwayBill? ewb;
  final PayType payType;
  final DeliveryType deliveryType;
  final LrStatus status;
  final String? remarks;
  final List<Attachment> attachments;

  const LorryReceipt({
    required this.id,
    required this.number,
    required this.date,
    required this.enteredBy,
    required this.consignor,
    required this.consignee,
    required this.vehicle,
    required this.transporter,
    required this.route,
    required this.fromCity,
    required this.toCity,
    required this.items,
    required this.freight,
    this.ewb,
    required this.payType,
    required this.deliveryType,
    required this.status,
    this.remarks,
    this.attachments = const [],
  });

  int get totalPackages =>
      items.fold(0, (sum, item) => sum + item.packages);
  double get totalWeight =>
      items.fold(0.0, (sum, item) => sum + item.weight);
  double get totalValue =>
      items.fold(0.0, (sum, item) => sum + item.grossValue);

  LorryReceipt copyWith({
    LrStatus? status,
    PayType? payType,
    DeliveryType? deliveryType,
    FreightDetails? freight,
    EwayBill? ewb,
    String? remarks,
    List<Attachment>? attachments,
  }) {
    return LorryReceipt(
      id: id,
      number: number,
      date: date,
      enteredBy: enteredBy,
      consignor: consignor,
      consignee: consignee,
      vehicle: vehicle,
      transporter: transporter,
      route: route,
      fromCity: fromCity,
      toCity: toCity,
      items: items,
      freight: freight ?? this.freight,
      ewb: ewb ?? this.ewb,
      payType: payType ?? this.payType,
      deliveryType: deliveryType ?? this.deliveryType,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      attachments: attachments ?? this.attachments,
    );
  }
}
