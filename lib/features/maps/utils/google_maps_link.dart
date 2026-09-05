// Recovers coordinates from a pasted Google Maps URL, without a Google API key
// and without a network call — it is pure string parsing.
//
// Ops staff share plant gates as Google Maps links on WhatsApp. A gate has no
// searchable name (Nominatim will never find "TATA - Chakan"), but the link the
// driver sent carries the exact pin, so the picker accepts the link instead.

/// How coordinates were recovered from a pasted Google Maps URL.
enum GoogleLinkPrecision { placePin, mapCentre, query }

class GoogleMapsLink {
  final double lat;
  final double lng;
  final GoogleLinkPrecision precision;

  const GoogleMapsLink({
    required this.lat,
    required this.lng,
    required this.precision,
  });
}

// Every coordinate in a Maps URL has this shape: optionally negative, any
// number of decimals, integers allowed. Scientific notation is excluded on
// purpose — Google never emits it, and accepting "1e5" would let a truncated
// number through as a plausible-looking coordinate.
const _numberEnd = r'(?![0-9.eE])';

// The place's own pin, written into the /data= segment.
final _placePinPattern = RegExp(
  r'!3d(-?\d+(?:\.\d+)?)'
  r'!4d(-?\d+(?:\.\d+)?)'
  '$_numberEnd',
);

// The viewport centre, optionally followed by a zoom (",17z", ",17.5z") or an
// altitude (",1234m") segment that the trailing comma keeps out of the match.
final _mapCentrePattern = RegExp(
  r'@(-?\d+(?:\.\d+)?),'
  r'(-?\d+(?:\.\d+)?)'
  '$_numberEnd',
);

// A "lat,lng" pair at the head of a query parameter value; Google appends a
// label after it ("18.52,73.85 (TATA Motors)"), so anything after is ignored.
final _leadingPairPattern = RegExp(
  r'^\s*\(?\s*(-?\d+(?:\.\d+)?)'
  r'\s*,\s*(-?\d+(?:\.\d+)?)\s*\)?'
  '$_numberEnd',
);

// The whole paste is nothing but a coordinate pair, copied off the Maps info
// card, e.g. "18.5204, 73.8567" or "(18.5204,73.8567)".
final _barePairPattern = RegExp(
  r'^\(?\s*(-?\d+(?:\.\d+)?)'
  r'\s*,\s*(-?\d+(?:\.\d+)?)\s*\)?$',
);

// Searching a coordinate in Google Maps produces a URL that carries it in the
// PATH only — no @, no !3d/!4d and no query parameter — as in
// /maps/place/18.5204,73.8567 or /maps/search/18.5204,+73.8567.
final _pathPairPattern = RegExp(
  r'/maps/(?:place|search|dir)/(-?\d+(?:\.\d+)?)'
  r',\+?\s*(-?\d+(?:\.\d+)?)',
  caseSensitive: false,
);

// Query parameters Google uses to carry a coordinate pair, in the order they
// are trusted when a URL carries more than one.
const _coordParams = <String>[
  'q',
  'query',
  'll',
  'sll',
  'daddr',
  'destination',
  'center',
];

final _rawParamPattern = RegExp(
  r'[?&](?:q|query|ll|sll|daddr|destination|center)=([^&#\s]*)',
  caseSensitive: false,
);

final _googleMapsHostPattern = RegExp(
  r'maps\.app\.goo\.gl'
  r'|goo\.gl/maps'
  r'|maps\.google\.[a-z.]+'
  r'|google\.[a-z.]+/maps',
  caseSensitive: false,
);

final _shortLinkPattern = RegExp(
  r'maps\.app\.goo\.gl|goo\.gl/maps',
  caseSensitive: false,
);

/// True when [text] looks like a Google Maps URL at all — or is a bare
/// "18.5204, 73.8567" pair copied off the Maps info card, which is why the bare
/// form counts here too: the picker must route it to [parseGoogleMapsLink]
/// instead of sending digits to the place-name search.
bool looksLikeGoogleMapsLink(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return false;
  return _googleMapsHostPattern.hasMatch(raw) || _barePairPattern.hasMatch(raw);
}

/// True for shortened links (maps.app.goo.gl, goo.gl/maps), whose coordinates
/// exist only behind the redirect. [parseGoogleMapsLink] returns null for these
/// so the picker can tell the user to open the link once and paste the full URL
/// the browser lands on.
bool isShortGoogleMapsLink(String text) =>
    _shortLinkPattern.hasMatch(text.trim());

/// Extracts coordinates from a pasted Google Maps URL, or null.
GoogleMapsLink? parseGoogleMapsLink(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  if (isShortGoogleMapsLink(raw)) return null;

  // !3d/!4d is the place's own pin and wins over @, which is only wherever the
  // viewport happened to sit when the link was copied — on a long plant road
  // that is hundreds of metres off the gate.
  for (final m in _placePinPattern.allMatches(raw)) {
    final hit = _coord(m.group(1), m.group(2), GoogleLinkPrecision.placePin);
    if (hit != null) return hit;
  }
  // A malformed higher-priority pair must not mask a good lower-priority one,
  // so each pattern falls through rather than failing the whole parse.
  for (final m in _mapCentrePattern.allMatches(raw)) {
    final hit = _coord(m.group(1), m.group(2), GoogleLinkPrecision.mapCentre);
    if (hit != null) return hit;
  }
  final fromQuery = _fromQueryParams(raw);
  if (fromQuery != null) return fromQuery;

  // Last URL shape: the pair sits in the path with nothing else to go on.
  for (final m in _pathPairPattern.allMatches(raw)) {
    final hit = _coord(m.group(1), m.group(2), GoogleLinkPrecision.query);
    if (hit != null) return hit;
  }

  final bare = _barePairPattern.firstMatch(raw);
  if (bare != null) {
    return _coord(bare.group(1), bare.group(2), GoogleLinkPrecision.query);
  }
  return null;
}

GoogleMapsLink? _fromQueryParams(String raw) {
  // Uri.parse is tried first because it decodes %2C and "+" for us, but pasted
  // links routinely carry unencoded characters that make it throw, so the raw
  // scan below has to work on its own.
  try {
    final params = Uri.parse(raw).queryParameters;
    for (final name in _coordParams) {
      final hit = _pairIn(params[name]);
      if (hit != null) return hit;
    }
  } on FormatException {
    // Not a parseable URI; the raw scan still finds the parameter.
  } on ArgumentError {
    // A truncated %-escape in some other parameter; same fallback.
  }
  // Also reached for well-formed URIs whose pair sits in the "#" fragment,
  // which Uri.queryParameters does not expose.
  for (final m in _rawParamPattern.allMatches(raw)) {
    final hit = _pairIn(_decodeValue(m.group(1)));
    if (hit != null) return hit;
  }
  return null;
}

GoogleMapsLink? _pairIn(String? value) {
  if (value == null) return null;
  final m = _leadingPairPattern.firstMatch(value);
  if (m == null) return null;
  return _coord(m.group(1), m.group(2), GoogleLinkPrecision.query);
}

String? _decodeValue(String? value) {
  if (value == null) return null;
  try {
    return Uri.decodeQueryComponent(value);
  } on ArgumentError {
    // Half-typed escape such as "%2": fall back to the text as pasted.
    return value;
  } on FormatException {
    return value;
  }
}

GoogleMapsLink? _coord(String? lat, String? lng, GoogleLinkPrecision p) {
  if (lat == null || lng == null) return null;
  final la = double.tryParse(lat);
  final ln = double.tryParse(lng);
  if (la == null || ln == null) return null;
  if (la < -90 || la > 90 || ln < -180 || ln > 180) return null;
  // (0, 0) is the uninitialised default of every map widget and sits in the
  // Atlantic — never a real location anyone would share.
  if (la == 0 && ln == 0) return null;
  return GoogleMapsLink(lat: la, lng: ln, precision: p);
}
