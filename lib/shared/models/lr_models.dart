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
  final double additionalFreight;
  // Client-funded incentives (NOT part of transporter freight). Each carries a
  // per-LR driver share; the remainder is Vistar's margin. See the incentive
  // getters below.
  final double expressCharges; // total received from client
  final double expressChargesDriverShare; // portion paid out to the driver
  final double extraPointDelivery; // total received from client
  final double extraPointDeliveryDriverShare; // portion paid out to the driver
  final double haltingCharge;
  final double gst;
  final double advance;
  /// Share of the transporter freight released as this LR's advance. Copied
  /// from the transporter's default when the LR is created and overridable on
  /// this one LR; frozen thereafter, so later edits to the transporter's
  /// default never move an already-billed LR. Legacy LRs read back as 90.
  final double advancePercent;
  final double mathadi;
  final double vistarMargin;
  final String advancePaidById;
  final String tripLeadById;
  final String advancePaidBy; // display label
  final String tripLeadBy; // display label (legacy TRIP_LEAD_BY lookup)
  final String tripLeadUserId; // app-user id — the current "Trip Lead By"
  final String tripLeadUserName; // that user's display name
  final double? _total; // backend-computed (generated column)
  final double? _balance; // backend-computed (generated column)

  const FreightDetails({
    this.freight = 0,
    this.collection = 0,
    this.doorDelivery = 0,
    this.handling = 0,
    this.insurance = 0,
    this.additionalFreight = 0,
    this.expressCharges = 0,
    this.expressChargesDriverShare = 0,
    this.extraPointDelivery = 0,
    this.extraPointDeliveryDriverShare = 0,
    this.haltingCharge = 0,
    this.gst = 0,
    this.advance = 0,
    this.advancePercent = kDefaultAdvancePercent,
    this.mathadi = 0,
    this.vistarMargin = 0,
    this.advancePaidById = '',
    this.tripLeadById = '',
    this.advancePaidBy = '',
    this.tripLeadBy = '',
    this.tripLeadUserId = '',
    this.tripLeadUserName = '',
    double? total,
    double? balance,
  }) : _total = total,
       _balance = balance;

  // GST is no longer charged; it is excluded from the total. The backend still
  // returns a `total` generated column (authoritative) — this fallback is only
  // used when that is absent.
  // Client incentive charges (express / extra-point delivery) are NOT part of
  // the transporter freight total — they are a separate client-funded incentive
  // split between the driver and Vistar (see the incentive getters below). This
  // fallback (used only when the backend omits `total`) mirrors the backend
  // generated column exactly.
  double get total =>
      _total ??
      (freight +
          doorDelivery +
          handling +
          insurance +
          gst +
          mathadi +
          collection +
          vistarMargin +
          additionalFreight +
          haltingCharge);
  double get balance => _balance ?? (total - advance);

  // ---- Client incentive charges (express + extra-point delivery) -----------
  // Each is an extra amount the client pays; a per-LR portion is paid out to
  // the driver (together with the transporter balance, after POD) and the
  // remainder is Vistar's margin. Margins are clamped at 0 in case a driver
  // share is (mis-)entered above the client amount.
  double get expressChargesVistarMargin {
    final m = expressCharges - expressChargesDriverShare;
    return m > 0 ? m : 0;
  }

  double get extraPointDeliveryVistarMargin {
    final m = extraPointDelivery - extraPointDeliveryDriverShare;
    return m > 0 ? m : 0;
  }

  /// Total incentive owed to the driver, paid with the transporter balance.
  double get driverIncentiveTotal =>
      expressChargesDriverShare + extraPointDeliveryDriverShare;

  /// Vistar's combined share of the client incentives.
  double get incentiveVistarMargin =>
      expressChargesVistarMargin + extraPointDeliveryVistarMargin;

  /// Total incentive received from the client across both heads.
  double get clientIncentiveTotal => expressCharges + extraPointDelivery;

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
      additionalFreight: asDouble(json['additional_freight']),
      expressCharges: asDouble(json['express_charges']),
      expressChargesDriverShare: asDouble(json['express_charges_driver_share']),
      extraPointDelivery: asDouble(json['extra_point_delivery']),
      extraPointDeliveryDriverShare:
          asDouble(json['extra_point_delivery_driver_share']),
      haltingCharge: asDouble(json['halting_charge']),
      gst: asDouble(json['gst']),
      advance: asDouble(json['advance']),
      // asDoubleOrNull (not asDouble) so an absent column falls back to the
      // standard default while an explicit 0% ("no advance") survives — the
      // null-coercing asDouble would turn both into 0.
      advancePercent:
          asDoubleOrNull(json['advance_percent']) ?? kDefaultAdvancePercent,
      mathadi: asDouble(json['mathadi']),
      vistarMargin: asDouble(json['vistar_margin']),
      advancePaidById: apbId ?? '',
      tripLeadById: tlbId ?? '',
      advancePaidBy: resolveLookup('ADVANCE_PAID_BY', apbId),
      tripLeadBy: resolveLookup('TRIP_LEAD_BY', tlbId),
      tripLeadUserId: (json['trip_lead_user_id'] as String?) ?? '',
      tripLeadUserName: (json['trip_lead_user_name'] as String?) ?? '',
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
    double? additionalFreight,
    double? expressCharges,
    double? expressChargesDriverShare,
    double? extraPointDelivery,
    double? extraPointDeliveryDriverShare,
    double? haltingCharge,
    double? gst,
    double? advance,
    double? advancePercent,
    double? mathadi,
    double? vistarMargin,
    String? advancePaidById,
    String? tripLeadById,
    String? advancePaidBy,
    String? tripLeadBy,
    String? tripLeadUserId,
    String? tripLeadUserName,
  }) {
    return FreightDetails(
      freight: freight ?? this.freight,
      collection: collection ?? this.collection,
      doorDelivery: doorDelivery ?? this.doorDelivery,
      handling: handling ?? this.handling,
      insurance: insurance ?? this.insurance,
      additionalFreight: additionalFreight ?? this.additionalFreight,
      expressCharges: expressCharges ?? this.expressCharges,
      expressChargesDriverShare:
          expressChargesDriverShare ?? this.expressChargesDriverShare,
      extraPointDelivery: extraPointDelivery ?? this.extraPointDelivery,
      extraPointDeliveryDriverShare:
          extraPointDeliveryDriverShare ?? this.extraPointDeliveryDriverShare,
      haltingCharge: haltingCharge ?? this.haltingCharge,
      gst: gst ?? this.gst,
      advance: advance ?? this.advance,
      advancePercent: advancePercent ?? this.advancePercent,
      mathadi: mathadi ?? this.mathadi,
      vistarMargin: vistarMargin ?? this.vistarMargin,
      advancePaidById: advancePaidById ?? this.advancePaidById,
      tripLeadById: tripLeadById ?? this.tripLeadById,
      advancePaidBy: advancePaidBy ?? this.advancePaidBy,
      tripLeadBy: tripLeadBy ?? this.tripLeadBy,
      tripLeadUserId: tripLeadUserId ?? this.tripLeadUserId,
      tripLeadUserName: tripLeadUserName ?? this.tripLeadUserName,
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
  final DateTime? inDateTime;
  final DateTime? outDateTime;
  final Consignor consignor;
  final Consignee consignee;
  final Vehicle vehicle;
  final Transporter transporter;
  final String? driverId;
  final String? routeId;
  final String? regionId;
  final String? regionName;
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
  // Optional vehicle capacity (VEHICLE_CAPACITY lookup): id for the form, label
  // for the slip.
  final String capacityId;
  final String capacityLabel;
  final String? remarks;
  final List<Attachment> attachments;
  // Accounts-owned MIS / billing fields (set by Accounts; see Accounts screen).
  final String vistarBillNo;
  final DateTime? vistarBillDate;
  final DateTime? podSoftCopyDate;
  final DateTime? advancePaidAt;
  final DateTime? balancePaidAt;
  // Two-step payment hand-off: an LR is created NOT sent to Accounts; an ops
  // user explicitly "sends for payment", which (server-side) flips this flag
  // and triggers the Accounts email. When the field is ABSENT (older backend)
  // it is treated as already sent, so existing LRs never disappear from the
  // Accounts queue and no non-functional button appears.
  final bool sentForPayment;
  final DateTime? sentForPaymentAt;
  // Set (server-side) when the driver's incentive share is released together
  // with the transporter balance (Complete Payment / after POD) — never with
  // the 90% advance.
  final bool driverIncentivePaid;
  final DateTime? driverIncentivePaidAt;

  const LorryReceipt({
    required this.id,
    required this.number,
    required this.date,
    required this.enteredBy,
    this.enteredByName = '',
    this.version = 0,
    this.customerName = '',
    this.orderNo = '',
    this.inDateTime,
    this.outDateTime,
    required this.consignor,
    required this.consignee,
    required this.vehicle,
    required this.transporter,
    this.driverId,
    this.routeId,
    this.regionId,
    this.regionName,
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
    this.capacityId = '',
    this.capacityLabel = '',
    this.remarks,
    this.attachments = const [],
    this.vistarBillNo = '',
    this.vistarBillDate,
    this.podSoftCopyDate,
    this.advancePaidAt,
    this.balancePaidAt,
    this.sentForPayment = false,
    this.sentForPaymentAt,
    this.driverIncentivePaid = false,
    this.driverIncentivePaidAt,
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
      enteredByName: (nested('enteredBy')?['name'] as String?) ??
          (json['entered_by_name'] as String?) ??
          '',
      version: asInt(json['version']),
      customerName: (json['customer_name'] as String?) ?? '',
      orderNo: (json['order_no'] as String?) ?? '',
      inDateTime: DateTime.tryParse(json['in_datetime']?.toString() ?? ''),
      outDateTime: DateTime.tryParse(json['out_datetime']?.toString() ?? ''),
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
      regionId: json['region_id'] as String?,
      regionName: (json['region_name'] as String?) ??
          ((json['region'] as Map?)?['name'] as String?),
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
      capacityId: (json['capacity_id'] as String?) ?? '',
      capacityLabel: (nested('capacity')?['label'] as String?) ?? '',
      remarks: json['remarks'] as String?,
      attachments: attachJson
          .cast<Map<String, dynamic>>()
          .map(Attachment.fromJson)
          .toList(),
      vistarBillNo: (json['vistar_bill_no'] as String?) ?? '',
      vistarBillDate: DateTime.tryParse(json['vistar_bill_date']?.toString() ?? ''),
      podSoftCopyDate:
          DateTime.tryParse(json['pod_soft_copy_date']?.toString() ?? ''),
      advancePaidAt:
          DateTime.tryParse(json['advance_paid_at']?.toString() ?? ''),
      balancePaidAt:
          DateTime.tryParse(json['balance_paid_at']?.toString() ?? ''),
      // Absent → true (older backend): keep legacy LRs visible in Accounts.
      sentForPayment: (json['sent_for_payment'] as bool?) ?? true,
      sentForPaymentAt:
          DateTime.tryParse(json['sent_for_payment_at']?.toString() ?? ''),
      driverIncentivePaid: (json['driver_incentive_paid'] as bool?) ?? false,
      driverIncentivePaidAt: DateTime.tryParse(
        json['driver_incentive_paid_at']?.toString() ?? '',
      ),
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
    String? vistarBillNo,
    DateTime? vistarBillDate,
    DateTime? podSoftCopyDate,
    DateTime? advancePaidAt,
    DateTime? balancePaidAt,
    bool? sentForPayment,
    DateTime? sentForPaymentAt,
    bool? driverIncentivePaid,
    DateTime? driverIncentivePaidAt,
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
      inDateTime: inDateTime,
      outDateTime: outDateTime,
      consignor: consignor,
      consignee: consignee,
      vehicle: vehicle,
      transporter: transporter,
      driverId: driverId,
      routeId: routeId,
      regionId: regionId,
      regionName: regionName,
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
      capacityId: capacityId,
      capacityLabel: capacityLabel,
      remarks: remarks ?? this.remarks,
      attachments: attachments ?? this.attachments,
      vistarBillNo: vistarBillNo ?? this.vistarBillNo,
      vistarBillDate: vistarBillDate ?? this.vistarBillDate,
      podSoftCopyDate: podSoftCopyDate ?? this.podSoftCopyDate,
      advancePaidAt: advancePaidAt ?? this.advancePaidAt,
      balancePaidAt: balancePaidAt ?? this.balancePaidAt,
      sentForPayment: sentForPayment ?? this.sentForPayment,
      sentForPaymentAt: sentForPaymentAt ?? this.sentForPaymentAt,
      driverIncentivePaid: driverIncentivePaid ?? this.driverIncentivePaid,
      driverIncentivePaidAt:
          driverIncentivePaidAt ?? this.driverIncentivePaidAt,
    );
  }
}
