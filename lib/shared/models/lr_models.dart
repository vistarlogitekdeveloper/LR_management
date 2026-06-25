import '../../core/utils/json_parse.dart';
import 'attachment.dart';
import 'consignee.dart';
import 'consignor.dart';
import 'transporter.dart';
import 'vehicle.dart';

// Lightweight lookup resolver: category -> code -> label. Passed into LR
// parsing so id-only fields (advance_paid_by, trip_lead_by, package_type) can be
// shown as human labels. Built from the live `lookupsProvider`.
typedef LookupResolver = String Function(String category, String? id);

String _noopResolve(String category, String? id) => '';

enum LrStatus { booked, inTransit, delivered, cancelled }

extension LrStatusX on LrStatus {
  String get label => switch (this) {
    LrStatus.booked => 'Booked',
    LrStatus.inTransit => 'In Transit',
    LrStatus.delivered => 'Delivered',
    LrStatus.cancelled => 'Cancelled',
  };

  String get code => switch (this) {
    LrStatus.booked => 'BOOKED',
    LrStatus.inTransit => 'IN_TRANSIT',
    LrStatus.delivered => 'DELIVERED',
    LrStatus.cancelled => 'CANCELLED',
  };

  static LrStatus fromLabel(String s) => LrStatus.values.firstWhere(
    (e) => e.label == s,
    orElse: () => LrStatus.booked,
  );

  static LrStatus fromCode(String? s) => LrStatus.values.firstWhere(
    (e) => e.code == (s ?? '').toUpperCase(),
    orElse: () => LrStatus.booked,
  );
}

enum PayType { tbb, paid, tbr }

extension PayTypeX on PayType {
  String get label => switch (this) {
    PayType.tbb => 'To Be Billed',
    PayType.paid => 'Paid',
    PayType.tbr => 'To Be Received',
  };

  String get code => switch (this) {
    PayType.tbb => 'TBB',
    PayType.paid => 'PAID',
    PayType.tbr => 'TBR',
  };

  static PayType fromCode(String? s) => PayType.values.firstWhere(
    (e) => e.code == (s ?? '').toUpperCase(),
    orElse: () => PayType.tbb,
  );
}

enum DeliveryType { doorDelivery, godownDelivery }

extension DeliveryTypeX on DeliveryType {
  String get label => switch (this) {
    DeliveryType.doorDelivery => 'Door Delivery',
    DeliveryType.godownDelivery => 'Godown Delivery',
  };

  String get code => switch (this) {
    DeliveryType.doorDelivery => 'DOOR',
    DeliveryType.godownDelivery => 'GODOWN',
  };

  static DeliveryType fromCode(String? s) => DeliveryType.values.firstWhere(
    (e) => e.code == (s ?? '').toUpperCase(),
    orElse: () => DeliveryType.doorDelivery,
  );
}

class InvoiceItem {
  final String invoiceNo;
  final DateTime invoiceDate;
  final String asn;
  final String partDescription;
  final int quantity;
  final double weight;
  final double chargeableWeight;
  final double grossValue;
  final int packages;
  final String packageTypeId;
  final String packageType; // display label
  final String natureOfGoods;

  const InvoiceItem({
    required this.invoiceNo,
    required this.invoiceDate,
    required this.asn,
    required this.partDescription,
    required this.quantity,
    required this.weight,
    this.chargeableWeight = 0,
    required this.grossValue,
    required this.packages,
    this.packageTypeId = '',
    required this.packageType,
    required this.natureOfGoods,
  });

  factory InvoiceItem.fromJson(
    Map<String, dynamic> json, {
    LookupResolver resolveLookup = _noopResolve,
  }) {
    final pkgId = json['package_type_id'] as String?;
    String pkgLabel = '';
    final pkgNested = json['packageType'];
    if (pkgNested is Map) {
      pkgLabel = (pkgNested['label'] as String?) ?? '';
    }
    if (pkgLabel.isEmpty) pkgLabel = resolveLookup('PACKAGE_TYPE', pkgId);
    return InvoiceItem(
      invoiceNo: (json['invoice_no'] as String?) ?? '',
      invoiceDate:
          DateTime.tryParse(json['invoice_date']?.toString() ?? '') ??
          DateTime.now(),
      asn: (json['asn'] as String?) ?? '',
      partDescription: (json['part_description'] as String?) ?? '',
      quantity: asInt(json['quantity']),
      weight: asDouble(json['weight_kg']),
      chargeableWeight: asDouble(json['chargeable_weight_kg']),
      grossValue: asDouble(json['gross_value']),
      packages: asInt(json['packages']),
      packageTypeId: pkgId ?? '',
      packageType: pkgLabel,
      natureOfGoods: (json['nature_of_goods'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    if (invoiceNo.isNotEmpty) 'invoice_no': invoiceNo,
    'invoice_date': invoiceDate.toIso8601String(),
    if (asn.isNotEmpty) 'asn': asn,
    if (partDescription.isNotEmpty) 'part_description': partDescription,
    'quantity': quantity,
    'weight_kg': weight,
    'chargeable_weight_kg': chargeableWeight,
    'gross_value': grossValue,
    'packages': packages,
    if (packageTypeId.isNotEmpty) 'package_type_id': packageTypeId,
    if (natureOfGoods.isNotEmpty) 'nature_of_goods': natureOfGoods,
  };
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
  final String advancePaidById;
  final String tripLeadById;
  final String advancePaidBy; // display label
  final String tripLeadBy; // display label
  final double? _total; // backend-computed (generated column)
  final double? _balance; // backend-computed (generated column)

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
    this.advancePaidById = '',
    this.tripLeadById = '',
    this.advancePaidBy = '',
    this.tripLeadBy = '',
    double? total,
    double? balance,
  }) : _total = total,
       _balance = balance;

  double get total =>
      _total ?? (freight + doorDelivery + handling + gst + insurance);
  double get balance => _balance ?? (total - advance);

  factory FreightDetails.fromJson(
    Map<String, dynamic> json, {
    LookupResolver resolveLookup = _noopResolve,
  }) {
    final apbId = json['advance_paid_by_id'] as String?;
    final tlbId = json['trip_lead_by_id'] as String?;
    return FreightDetails(
      freight: asDouble(json['freight']),
      collection: asDouble(json['collection']),
      doorDelivery: asDouble(json['door_delivery']),
      handling: asDouble(json['handling']),
      insurance: asDouble(json['insurance']),
      gst: asDouble(json['gst']),
      advance: asDouble(json['advance']),
      mathadi: asDouble(json['mathadi']),
      vistarMargin: asDouble(json['vistar_margin']),
      advancePaidById: apbId ?? '',
      tripLeadById: tlbId ?? '',
      advancePaidBy: resolveLookup('ADVANCE_PAID_BY', apbId),
      tripLeadBy: resolveLookup('TRIP_LEAD_BY', tlbId),
      total: asDoubleOrNull(json['total']),
      balance: asDoubleOrNull(json['balance']),
    );
  }

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
    String? advancePaidById,
    String? tripLeadById,
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
      advancePaidById: advancePaidById ?? this.advancePaidById,
      tripLeadById: tripLeadById ?? this.tripLeadById,
      advancePaidBy: advancePaidBy ?? this.advancePaidBy,
      tripLeadBy: tripLeadBy ?? this.tripLeadBy,
    );
  }
}

class EwayBill {
  final String id;
  final String number;
  final DateTime? expiry;
  final String loadTypeId;
  final String loadType; // display label
  final String validationStatus;

  const EwayBill({
    this.id = '',
    required this.number,
    this.expiry,
    this.loadTypeId = '',
    this.loadType = '',
    this.validationStatus = 'pending',
  });

  factory EwayBill.fromJson(
    Map<String, dynamic> json, {
    LookupResolver resolveLookup = _noopResolve,
  }) {
    final loadId = json['load_type_id'] as String?;
    String loadLabel = '';
    final nested = json['loadType'];
    if (nested is Map) loadLabel = (nested['label'] as String?) ?? '';
    if (loadLabel.isEmpty) loadLabel = resolveLookup('EWB_LOAD_TYPE', loadId);
    return EwayBill(
      id: (json['id'] as String?) ?? '',
      number: (json['number'] as String?) ?? '',
      expiry: DateTime.tryParse(json['expiry_at']?.toString() ?? ''),
      loadTypeId: loadId ?? '',
      loadType: loadLabel,
      validationStatus: (json['validation_status'] as String?) ?? 'pending',
    );
  }
}

class LorryReceipt {
  final String id;
  final String number;
  final DateTime date;
  final String enteredBy;
  final String enteredByName;
  final int version;
  final String customerName;
  final String orderNo;
  final Consignor consignor;
  final Consignee consignee;
  final Vehicle vehicle;
  final Transporter transporter;
  final String? driverId;
  final String? routeId;
  final String route;
  final String fromCity;
  final String toCity;
  final List<InvoiceItem> items;
  final FreightDetails freight;
  final EwayBill? ewb;
  final PayType payType;
  final DeliveryType deliveryType;
  final LrStatus status;
  final String payTypeId;
  final String deliveryTypeId;
  final String statusId;
  final String? remarks;
  final List<Attachment> attachments;

  const LorryReceipt({
    required this.id,
    required this.number,
    required this.date,
    required this.enteredBy,
    this.enteredByName = '',
    this.version = 0,
    this.customerName = '',
    this.orderNo = '',
    required this.consignor,
    required this.consignee,
    required this.vehicle,
    required this.transporter,
    this.driverId,
    this.routeId,
    required this.route,
    required this.fromCity,
    required this.toCity,
    required this.items,
    required this.freight,
    this.ewb,
    required this.payType,
    required this.deliveryType,
    required this.status,
    this.payTypeId = '',
    this.deliveryTypeId = '',
    this.statusId = '',
    this.remarks,
    this.attachments = const [],
  });

  int get totalPackages => items.fold(0, (sum, item) => sum + item.packages);
  double get totalWeight => items.fold(0.0, (sum, item) => sum + item.weight);
  double get totalValue =>
      items.fold(0.0, (sum, item) => sum + item.grossValue);

  factory LorryReceipt.fromJson(
    Map<String, dynamic> json, {
    LookupResolver resolveLookup = _noopResolve,
  }) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      return v is Map ? v.cast<String, dynamic>() : null;
    }

    String codeOf(String key) => (nested(key)?['code'] as String?) ?? '';

    final consignorJson = nested('consignor');
    final consigneeJson = nested('consignee');
    final vehicleJson = nested('vehicle');
    final transporterJson = nested('transporter');
    final routeJson = nested('route');
    final driverJson = nested('driver');

    final fromCity =
        (json['from_city'] as String?) ??
        (routeJson?['from_city'] as String?) ??
        '';
    final toCity =
        (json['to_city'] as String?) ??
        (routeJson?['to_city'] as String?) ??
        '';

    final itemsJson =
        (json['invoiceItems'] as List?) ??
        (json['invoice_items'] as List?) ??
        const [];
    final attachJson = (json['attachments'] as List?) ?? const [];
    final ewbJson = nested('ewayBill') ?? nested('eway_bill');

    return LorryReceipt(
      id: json['id'] as String,
      number: (json['number'] as String?) ?? '',
      date:
          DateTime.tryParse(json['lr_date']?.toString() ?? '') ??
          DateTime.now(),
      enteredBy: (json['entered_by'] as String?) ?? '',
      enteredByName: (nested('enteredBy')?['name'] as String?) ?? '',
      version: asInt(json['version']),
      customerName: (json['customer_name'] as String?) ?? '',
      orderNo: (json['order_no'] as String?) ?? '',
      consignor: consignorJson != null
          ? Consignor.fromJson(consignorJson)
          : Consignor(
              id: (json['consignor_id'] as String?) ?? '',
              name: '',
              gst: '',
              city: '',
              address: '',
              contact: '',
              mobile: '',
              email: '',
            ),
      consignee: consigneeJson != null
          ? Consignee.fromJson(consigneeJson)
          : Consignee(
              id: (json['consignee_id'] as String?) ?? '',
              name: '',
              gst: '',
              location: '',
              address: '',
              contact: '',
              mobile: '',
            ),
      vehicle: vehicleJson != null
          ? Vehicle.fromJson(vehicleJson)
          : Vehicle(id: (json['vehicle_id'] as String?) ?? '', number: ''),
      transporter: transporterJson != null
          ? Transporter.fromJson(transporterJson)
          : Transporter(
              id: (json['transporter_id'] as String?) ?? '',
              name: '',
              pan: '',
              tds: 'No',
            ),
      driverId: json['driver_id'] as String? ?? driverJson?['id'] as String?,
      routeId: json['route_id'] as String?,
      route: (fromCity.isNotEmpty || toCity.isNotEmpty)
          ? '$fromCity → $toCity'
          : '',
      fromCity: fromCity,
      toCity: toCity,
      items: itemsJson
          .cast<Map<String, dynamic>>()
          .map((e) => InvoiceItem.fromJson(e, resolveLookup: resolveLookup))
          .toList(),
      freight: FreightDetails.fromJson(json, resolveLookup: resolveLookup),
      ewb: ewbJson != null
          ? EwayBill.fromJson(ewbJson, resolveLookup: resolveLookup)
          : null,
      payType: PayTypeX.fromCode(codeOf('payType')),
      deliveryType: DeliveryTypeX.fromCode(codeOf('deliveryType')),
      status: LrStatusX.fromCode(codeOf('status')),
      payTypeId: (json['pay_type_id'] as String?) ?? '',
      deliveryTypeId: (json['delivery_type_id'] as String?) ?? '',
      statusId: (json['status_id'] as String?) ?? '',
      remarks: json['remarks'] as String?,
      attachments: attachJson
          .cast<Map<String, dynamic>>()
          .map(Attachment.fromJson)
          .toList(),
    );
  }

  LorryReceipt copyWith({
    LrStatus? status,
    PayType? payType,
    DeliveryType? deliveryType,
    FreightDetails? freight,
    EwayBill? ewb,
    String? remarks,
    List<Attachment>? attachments,
    int? version,
  }) {
    return LorryReceipt(
      id: id,
      number: number,
      date: date,
      enteredBy: enteredBy,
      enteredByName: enteredByName,
      version: version ?? this.version,
      customerName: customerName,
      orderNo: orderNo,
      consignor: consignor,
      consignee: consignee,
      vehicle: vehicle,
      transporter: transporter,
      driverId: driverId,
      routeId: routeId,
      route: route,
      fromCity: fromCity,
      toCity: toCity,
      items: items,
      freight: freight ?? this.freight,
      ewb: ewb ?? this.ewb,
      payType: payType ?? this.payType,
      deliveryType: deliveryType ?? this.deliveryType,
      status: status ?? this.status,
      payTypeId: payTypeId,
      deliveryTypeId: deliveryTypeId,
      statusId: statusId,
      remarks: remarks ?? this.remarks,
      attachments: attachments ?? this.attachments,
    );
  }
}
