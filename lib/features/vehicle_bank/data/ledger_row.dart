import '../../../core/utils/json_parse.dart';

String _str(dynamic v) => v == null ? '' : v.toString();

/// One entry of the "Upload Document" column: an uploaded file on a driver or
/// transporter master. [ownerType] + [ownerId] + [type] are what the existing
/// document endpoints take (GET /drivers/:id/document?type=…,
/// GET /transporters/:id/document?type=…).
///
/// [viewable] is false when the caller may not open it (the server then also
/// withholds [fileName]); the cell still shows that it is on file.
class LedgerDocument {
  final String ownerType; // 'driver' | 'transporter'
  final String ownerId;
  final String type; // pan | aadhaar | cheque | tds
  final String label; // "PAN", "Aadhaar", "Cheque", "TDS"
  final String fileName;
  final bool viewable;

  const LedgerDocument({
    required this.ownerType,
    required this.ownerId,
    required this.type,
    required this.label,
    this.fileName = '',
    this.viewable = false,
  });

  factory LedgerDocument.fromJson(Map<String, dynamic> json) => LedgerDocument(
    ownerType: _str(json['owner']),
    ownerId: _str(json['owner_id']),
    type: _str(json['type']),
    label: _str(json['label']).isEmpty
        ? _str(json['type']).toUpperCase()
        : _str(json['label']),
    fileName: _str(json['file_name']),
    viewable: json['viewable'] == true,
  );
}

/// One line of the Vehicle Bank ledger: a driver/owner, the transporter they
/// ran under, and the lane — as actually recorded on the LRs, deduplicated
/// server-side to one row per (driver, transporter, lane).
///
/// This is NOT the vehicle directory ([VehicleBankRow]). That one answers "who
/// is attached to this truck today" from the vehicle master; this one answers
/// "every vendor we have actually run a load with, and on which lane", which
/// only the LR table records.
///
/// KYC and bank fields arrive already resolved by the service:
///   - [personAadhaar] is the FULL number only for a caller holding
///     VEHICLE_BANK_PII_VIEW, and "XXXX XXXX 9012" otherwise. It is rendered as
///     given and never reassembled here.
///   - The four bank fields are empty unless that same permission is held —
///     the server does not select them at all without it.
/// [piiVisible] says which of the two the row is, so the UI can label the
/// difference instead of showing blanks that look like missing data.
class LedgerRow {
  /// Server-assigned identity for the deduplicated row. Opaque — used as the
  /// list key, never parsed.
  final String key;

  /// Column 2, "source of this route": the origin the load is picked up from.
  /// Always equal to [fromCity]; kept as its own field because it is its own
  /// column in the agreed sheet and the two could diverge later.
  final String sourceCity;

  /// Whoever the row is about — the driver when the LR named one, otherwise the
  /// transporter wearing its owner hat. [personIsDriver] distinguishes them.
  final String personName;
  final bool personIsDriver;
  final String personMobile;

  /// "Mail Id" — the same person's email (driver or transporter master). Empty
  /// until someone fills it in on the master.
  final String personEmail;

  /// The driver's id on a driver row, else null.
  final String? driverId;

  /// "Vehicle Type" — every type this driver/owner ran the lane with, e.g.
  /// "20 FT SXL, 32 FT MXL".
  final String vehicleType;

  /// "Upload Document" — the files on record, in the order PAN, Aadhaar,
  /// Cheque, TDS. PAN / Aadhaar are [personName]'s own; Cheque / TDS are the
  /// payee transporter's.
  final List<LedgerDocument> documents;

  /// PAN and Aadhaar of [personName] — never borrowed from the other party. A
  /// KYC number attributed to the wrong person is worse than a blank one.
  final String personPan;
  final String personAadhaar;

  final String? transporterId;
  final String transporterName;
  final String transporterMobile;

  final String fromCity;
  final String toCity;
  final double? routeDistanceKm;

  /// The PAYEE's bank block — the transporter's, even on a driver row, because
  /// the transporter is who gets paid and drivers hold no account in this
  /// system. [bankBranch] is the Branch Name entered on the transporter form.
  final String bankName;
  final String bankBranch;
  final String bankAccountNo;
  final String bankIfsc;

  /// NOT a column of the sheet — this feeds the screen's region picker, which
  /// builds its option list from the rows it already has.
  final String? regionId;
  final String regionName;

  final bool piiVisible;

  /// How many LRs this one row stands for, and the most recent of them.
  final int lrCount;
  final DateTime? lastLrDate;

  const LedgerRow({
    required this.key,
    this.sourceCity = '',
    this.personName = '',
    this.personIsDriver = false,
    this.personMobile = '',
    this.personEmail = '',
    this.driverId,
    this.vehicleType = '',
    this.documents = const [],
    this.personPan = '',
    this.personAadhaar = '',
    this.transporterId,
    this.transporterName = '',
    this.transporterMobile = '',
    this.fromCity = '',
    this.toCity = '',
    this.routeDistanceKm,
    this.bankName = '',
    this.bankBranch = '',
    this.bankAccountNo = '',
    this.bankIfsc = '',
    this.regionId,
    this.regionName = '',
    this.piiVisible = false,
    this.lrCount = 0,
    this.lastLrDate,
  });

  // route_distance_km is Postgres NUMERIC and so arrives as a STRING — a plain
  // `as double?` cast throws at runtime.
  factory LedgerRow.fromJson(Map<String, dynamic> json) => LedgerRow(
    key: _str(json['key']),
    sourceCity: _str(json['source_city']),
    personName: _str(json['person_name']),
    personIsDriver: json['person_is_driver'] == true,
    personMobile: _str(json['person_mobile']),
    personEmail: _str(json['person_email']),
    driverId: _str(json['driver_id']).isEmpty ? null : _str(json['driver_id']),
    vehicleType: _str(json['vehicle_type']),
    documents: json['documents'] is List
        ? (json['documents'] as List)
              .whereType<Map>()
              .map((d) => LedgerDocument.fromJson(Map<String, dynamic>.from(d)))
              .toList()
        : const [],
    personPan: _str(json['person_pan']),
    personAadhaar: _str(json['person_aadhaar']),
    transporterId: _str(json['transporter_id']).isEmpty
        ? null
        : _str(json['transporter_id']),
    transporterName: _str(json['transporter_name']),
    transporterMobile: _str(json['transporter_mobile']),
    fromCity: _str(json['from_city']),
    toCity: _str(json['to_city']),
    routeDistanceKm: asDoubleOrNull(json['route_distance_km']),
    bankName: _str(json['bank_name']),
    bankBranch: _str(json['bank_branch']),
    bankAccountNo: _str(json['bank_account_no']),
    bankIfsc: _str(json['bank_ifsc']),
    regionId: _str(json['region_id']).isEmpty ? null : _str(json['region_id']),
    regionName: _str(json['region_name']),
    piiVisible: json['pii_visible'] == true,
    lrCount: asInt(json['lr_count']),
    lastLrDate: _str(json['last_lr_date']).isEmpty
        ? null
        : DateTime.tryParse(_str(json['last_lr_date'])),
  );

  /// "CHAKAN → DEWAS", or empty when neither end is recorded.
  String get routeLabel => fromCity.isEmpty && toCity.isEmpty
      ? ''
      : '${fromCity.isEmpty ? '?' : fromCity} → ${toCity.isEmpty ? '?' : toCity}';

  /// True when the row has no bank block at all — either because the caller may
  /// not see one, or because the transporter master holds none. The UI needs to
  /// tell those apart, which is what [piiVisible] is for.
  bool get hasBankDetails =>
      bankName.isNotEmpty || bankAccountNo.isNotEmpty || bankIfsc.isNotEmpty;
}
