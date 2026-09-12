/// Non-web platforms: there is no Maps JavaScript SDK, and none is wanted.
/// Android and iOS need a platform key compiled into the native project, which
/// this build does not have, so the picker draws OSM tiles there.
bool googleMapsJsAvailable() => false;
