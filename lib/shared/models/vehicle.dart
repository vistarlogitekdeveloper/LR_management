class Vehicle {
  final String id;
  final String number;
  final String type;
  final String capacity;
  final String driver;
  final String driverMobile;
  final String mode;
  final String pmark;

  const Vehicle({
    required this.id,
    required this.number,
    required this.type,
    required this.capacity,
    required this.driver,
    required this.driverMobile,
    required this.mode,
    required this.pmark,
  });

  Vehicle copyWith({
    String? number,
    String? type,
    String? capacity,
    String? driver,
    String? driverMobile,
    String? mode,
    String? pmark,
  }) {
    return Vehicle(
      id: id,
      number: number ?? this.number,
      type: type ?? this.type,
      capacity: capacity ?? this.capacity,
      driver: driver ?? this.driver,
      driverMobile: driverMobile ?? this.driverMobile,
      mode: mode ?? this.mode,
      pmark: pmark ?? this.pmark,
    );
  }
}
