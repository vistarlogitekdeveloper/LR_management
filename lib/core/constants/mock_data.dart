/// Static reference fallbacks. All live business data (consignors, consignees,
/// vehicles, drivers, routes, transporters, users, LRs) now comes from the
/// backend API via repositories/providers. These string lists remain only as
/// last-resort fallbacks for dropdowns when the live lookups have not loaded.
class MockData {
  MockData._();

  static const routes = <String>[
    'Pune → Chakan',
    'Pune → Mumbai',
    'Karad → Pune',
    'Mumbai → Aurangabad',
    'Pune → Bhiwandi',
  ];

  static const vehicleTypes = <String>[
    'Open Body',
    'Closed Container',
    'Reefer',
    'Trailer',
  ];

  static const packageTypes = <String>['Box', 'Pallet', 'Bag', 'Drum', 'Loose'];
}
