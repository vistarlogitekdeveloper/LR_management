import 'maps_load_result.dart';

/// Non-web platforms: there is no Maps JavaScript SDK to load, and none is
/// wanted. Android and iOS need a platform key compiled into the native
/// project, which this build does not have, so the picker draws OSM tiles.
Future<MapsLoadResult> loadGoogleMaps(
  String apiKey, {
  Duration timeout = const Duration(seconds: 12),
}) async => MapsLoadResult.unsupported;

/// Never true off the web: nothing was ever presented to Google to refuse.
bool get googleMapsKeyRefused => false;

/// Never fires off the web.
Stream<void> get googleMapsAuthFailures => const Stream<void>.empty();
