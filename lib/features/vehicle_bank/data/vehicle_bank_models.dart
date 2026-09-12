import '../../../core/utils/json_parse.dart';

/// Ceiling the backend accepts for `expiring_within_days` (Joi: 0..730).
/// [VehicleBankFilter.toQueryParameters] clamps to it so a stray value from a
/// slider or a text field comes back as rows instead of a 400.
const int kVehicleBankMaxExpiryWindowDays = 730;

String _str(dynamic v) => v == null ? '' : v.toString();

/// FK ids are null when the vehicle has nothing attached; an empty string is
/// normalised to null too, so `row.transporterId != null` is a safe test.
String? _idOrNull(dynamic v) {
  final s = _str(v);
  return s.isEmpty ? null : s;
}

/// Dates arrive as bare YYYY-MM-DD (no zone), so they parse to local midnight —
/// which is what a "days until expiry" comparison against DateTime.now() wants.
DateTime? _dateOrNull(dynamic v) {
  final s = _str(v);
  return s.isEmpty ? null : DateTime.tryParse(s);
}

/// One line of the Vehicle Bank directory: a vehicle with its transporter,
/// current driver and assigned route flattened onto the same row.
///
/// Two absences are deliberate and enforced by the server, not here:
///   - No rate of any kind. Route rates are permission-gated elsewhere and this
///     directory is shared widely, so the API never selects them.
///   - No full Aadhaar. [transporterAadhaarMasked] is masked to
///     "XXXX XXXX 9012" by the service; the full number only exists behind the
///     transporter master's manage permission.
///
/// String fields are empty (never null) when absent, matching the API. Numeric
/// fields stay nullable: a vehicle with no recorded capacity is not a
/// zero-tonne vehicle.
class VehicleBankRow {
  final String vehicleId;
  final String registrationNo;
  final String vehicleType;
  final double? capacityMt;
  final double? lengthFt;
  final bool active;

  final DateTime? fitnessExpiry;
  final DateTime? insuranceExpiry;
  final DateTime? permitExpiry;
  final DateTime? pucExpiry;

  /// Whether a GPS device is attached — never the device id, which is of no use
  /// on this screen.
  final bool hasGps;

  final String? regionId;
  final String regionName;

  final String? transporterId;
  final String transporterName;
  final String transporterPan;

  /// Already masked server-side ("XXXX XXXX 9012"), or empty when the master
  /// holds no valid 12-digit Aadhaar.
  final String transporterAadhaarMasked;
  final String transporterMobile;
  final bool transporterTdsApplicable;

  final String? driverId;
  final String driverName;
  final String driverMobile;
  final String driverLicenseNo;
  final DateTime? driverLicenseExpiry;

  final String? routeId;
  final String routeFromCity;
  final String routeToCity;
  final double? routeDistanceKm;

  const VehicleBankRow({
    required this.vehicleId,
    this.registrationNo = '',
    this.vehicleType = '',
    this.capacityMt,
    this.lengthFt,
    this.active = true,
    this.fitnessExpiry,
    this.insuranceExpiry,
    this.permitExpiry,
    this.pucExpiry,
    this.hasGps = false,
    this.regionId,
    this.regionName = '',
    this.transporterId,
    this.transporterName = '',
    this.transporterPan = '',
    this.transporterAadhaarMasked = '',
    this.transporterMobile = '',
    this.transporterTdsApplicable = false,
    this.driverId,
    this.driverName = '',
    this.driverMobile = '',
    this.driverLicenseNo = '',
    this.driverLicenseExpiry,
    this.routeId,
    this.routeFromCity = '',
    this.routeToCity = '',
    this.routeDistanceKm,
  });

  // capacity_mt / length_ft / route_distance_km are Postgres NUMERIC and so
  // arrive as STRINGS — a plain `as double?` cast throws at runtime.
  factory VehicleBankRow.fromJson(Map<String, dynamic> json) => VehicleBankRow(
    vehicleId: _str(json['vehicle_id']),
    registrationNo: _str(json['registration_no']),
    vehicleType: _str(json['vehicle_type']),
    capacityMt: asDoubleOrNull(json['capacity_mt']),
    lengthFt: asDoubleOrNull(json['length_ft']),
    active: json['active'] != false,
    fitnessExpiry: _dateOrNull(json['fitness_expiry']),
    insuranceExpiry: _dateOrNull(json['insurance_expiry']),
    permitExpiry: _dateOrNull(json['permit_expiry']),
    pucExpiry: _dateOrNull(json['puc_expiry']),
    hasGps: json['has_gps'] == true,
    regionId: _idOrNull(json['region_id']),
    regionName: _str(json['region_name']),
    transporterId: _idOrNull(json['transporter_id']),
    transporterName: _str(json['transporter_name']),
    transporterPan: _str(json['transporter_pan']),
    transporterAadhaarMasked: _str(json['transporter_aadhaar_masked']),
    transporterMobile: _str(json['transporter_mobile']),
    transporterTdsApplicable: json['transporter_tds_applicable'] == true,
    driverId: _idOrNull(json['driver_id']),
    driverName: _str(json['driver_name']),
    driverMobile: _str(json['driver_mobile']),
    driverLicenseNo: _str(json['driver_license_no']),
    driverLicenseExpiry: _dateOrNull(json['driver_license_expiry']),
    routeId: _idOrNull(json['route_id']),
    routeFromCity: _str(json['route_from_city']),
    routeToCity: _str(json['route_to_city']),
    routeDistanceKm: asDoubleOrNull(json['route_distance_km']),
  );

  /// "Mumbai → Pune", or empty when no route is assigned.
  String get routeLabel => routeFromCity.isEmpty && routeToCity.isEmpty
      ? ''
      : '$routeFromCity → $routeToCity';

  /// The soonest of the four vehicle documents to lapse — what an expiry badge
  /// counts down to. Null when none of them is recorded.
  DateTime? get earliestDocumentExpiry {
    DateTime? earliest;
    for (final d in [fitnessExpiry, insuranceExpiry, permitExpiry, pucExpiry]) {
      if (d == null) continue;
      if (earliest == null || d.isBefore(earliest)) earliest = d;
    }
    return earliest;
  }
}

/// The directory's filter set — the exact arguments both the list and the
/// export take.
///
/// Immutable with value equality because it keys [vehicleBankRowsProvider]:
/// without `==` every rebuild would make a new family key, dispose the old one
/// and refetch, so the screen would loop requests forever.
///
/// Text fields use the empty string for "not filtering" rather than null, which
/// keeps [copyWith] able to clear them (`copyWith(regionId: '')`). Only [active]
/// and [expiringWithinDays] are nullable, and each has an explicit clear flag.
class VehicleBankFilter {
  /// Free text over registration no, transporter name, driver name and licence.
  final String q;
  final String regionId;

  /// Partial, case-insensitive match on the ASSIGNED route's endpoints.
  final String fromCity;
  final String toCity;

  final String transporterId;
  final String driverId;

  /// Null means both active and inactive vehicles.
  final bool? active;

  /// Any of fitness/insurance/permit/PUC lapsing within N days of today (IST),
  /// already-expired included. Null means no expiry filter.
  final int? expiringWithinDays;

  const VehicleBankFilter({
    this.q = '',
    this.regionId = '',
    this.fromCity = '',
    this.toCity = '',
    this.transporterId = '',
    this.driverId = '',
    this.active,
    this.expiringWithinDays,
  });

  static const VehicleBankFilter empty = VehicleBankFilter();

  /// How many filters are engaged — for a "Filters (3)" badge, and to choose
  /// between the "no vehicles yet" and "nothing matches" empty states.
  int get activeFilterCount => [
    q.trim().isNotEmpty,
    regionId.isNotEmpty,
    fromCity.trim().isNotEmpty,
    toCity.trim().isNotEmpty,
    transporterId.isNotEmpty,
    driverId.isNotEmpty,
    active != null,
    expiringWithinDays != null,
  ].where((engaged) => engaged).length;

  bool get hasFilters => activeFilterCount > 0;

  VehicleBankFilter copyWith({
    String? q,
    String? regionId,
    String? fromCity,
    String? toCity,
    String? transporterId,
    String? driverId,
    bool? active,
    int? expiringWithinDays,
    bool clearActive = false,
    bool clearExpiringWithinDays = false,
  }) {
    return VehicleBankFilter(
      q: q ?? this.q,
      regionId: regionId ?? this.regionId,
      fromCity: fromCity ?? this.fromCity,
      toCity: toCity ?? this.toCity,
      transporterId: transporterId ?? this.transporterId,
      driverId: driverId ?? this.driverId,
      active: clearActive ? null : (active ?? this.active),
      expiringWithinDays: clearExpiringWithinDays
          ? null
          : (expiringWithinDays ?? this.expiringWithinDays),
    );
  }

  /// Query string for both endpoints. An empty value is OMITTED rather than
  /// sent blank, and `active: false` survives: the server reads `?active=` as
  /// absent, so sending blanks would quietly turn "only inactive" into
  /// "everything".
  Map<String, dynamic> toQueryParameters() {
    final text = q.trim();
    final from = fromCity.trim();
    final to = toCity.trim();
    final onlyActive = active;
    final days = expiringWithinDays;
    return <String, dynamic>{
      if (text.isNotEmpty) 'q': text,
      if (regionId.isNotEmpty) 'region_id': regionId,
      if (from.isNotEmpty) 'from_city': from,
      if (to.isNotEmpty) 'to_city': to,
      if (transporterId.isNotEmpty) 'transporter_id': transporterId,
      if (driverId.isNotEmpty) 'driver_id': driverId,
      if (onlyActive != null) 'active': onlyActive ? 'true' : 'false',
      if (days != null)
        'expiring_within_days': days.clamp(0, kVehicleBankMaxExpiryWindowDays),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleBankFilter &&
          other.q == q &&
          other.regionId == regionId &&
          other.fromCity == fromCity &&
          other.toCity == toCity &&
          other.transporterId == transporterId &&
          other.driverId == driverId &&
          other.active == active &&
          other.expiringWithinDays == expiringWithinDays;

  @override
  int get hashCode => Object.hash(
    q,
    regionId,
    fromCity,
    toCity,
    transporterId,
    driverId,
    active,
    expiringWithinDays,
  );
}
