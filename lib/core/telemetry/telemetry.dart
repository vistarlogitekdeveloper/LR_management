import 'dart:async';

import 'package:dio/dio.dart';
import 'package:vistar_event_tracker/vistar_event_tracker.dart';

import '../network/api_config.dart';

/// Usage analytics for the LR Management app, sent to the in-house event
/// tracker and read in the Platform Console under Analytics > Event tracker.
///
/// Off unless the build is given both:
///   --dart-define=ET_APP_ID=lr_app --dart-define=ET_WRITE_KEY=wk_...
/// (register the app in the Platform Console, Settings > Event tracker; the
/// write key only lets a client append events, so it may ship in the app).
/// Optional --dart-define=ET_BASE_URL=... sends a test build's events
/// somewhere other than the API host the app uses (by default, the host of
/// API_BASE_URL, so a UAT build reports to UAT).
///
/// What is sent:
///   * screen views, by route pattern (ids and references replaced:
///     `/lrs/:id/edit`)
///   * sign-in / sign-out; the user as `lr:<user id>`, with their role and
///     organisation codes as traits
///   * named actions from successful API writes (see [_actions]):
///     `lr_created`, `lr_status_changed`, `invoice_created`, ...
///   * failed API calls (5xx or no connection), and uncaught client errors by
///     error TYPE only (see [clientError])
/// Never sent: request or response bodies, error messages, names, usernames,
/// emails, phone numbers, LR or vehicle numbers, consignor / consignee names,
/// amounts or any other record content.
///
/// NEVER IN THE WAY OF WORK. Nothing here is awaited by a screen, a write, a
/// sign-in or a sign-out; start-up waits at most [_initBudget]; every call
/// swallows its own failures; the queue is capped at [_maxQueue] events
/// (oldest dropped) in shared preferences; sending is in the background with
/// the SDK's backoff.
abstract final class Telemetry {
  static const _appId = String.fromEnvironment('ET_APP_ID');
  static const _writeKey = String.fromEnvironment('ET_WRITE_KEY');
  static const _baseUrlOverride = String.fromEnvironment('ET_BASE_URL');
  static const _appVersion = String.fromEnvironment('APP_VERSION');
  static const _initBudget = Duration(seconds: 2);
  static const _maxQueue = 200;

  static bool get enabled => _appId != '' && _writeKey != '';

  static VistarEventTracker get _t => VistarEventTracker.instance;
  static bool get _on => enabled && _t.isInitialized;

  static String? _lastScreen;
  static Future<void>? _resetting;

  static String get _origin {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    final u = Uri.parse(ApiConfig.baseUrl);
    return '${u.scheme}://${u.authority}';
  }

  static Future<void> init() async {
    if (!enabled) return;
    try {
      await _t
          .init(
            TrackerConfig(
              appId: _appId,
              writeKey: _writeKey,
              baseUrl: _origin,
              appVersion: _appVersion.isEmpty ? null : _appVersion,
              maxQueueSize: _maxQueue,
              // The SDK's own error capture would replace the app's
              // PlatformDispatcher.onError (core/observability/error_reporter.dart
              // returns true there so the process never dies) and would send
              // raw exception text. The app's error sink calls [clientError]
              // instead.
              autoCaptureErrors: false,
            ),
          )
          .timeout(_initBudget);
    } catch (_) {
      // Analytics must never stop the app from starting.
    }
  }

  /// A screen, by its route pattern. Repeats are dropped, and so is the
  /// session-restore splash (a spinner, not a screen anyone uses).
  static void screen(String location) {
    if (!_on) return;
    final name = routePattern(location);
    if (name == _lastScreen || name == '/splash') return;
    _lastScreen = name;
    _guard(() => _t.screen(name));
  }

  static void track(String name, [Map<String, dynamic>? properties]) {
    if (_on) _guard(() => _t.track(name, properties: properties));
  }

  static void error(String name, Map<String, dynamic> properties) {
    if (_on) {
      _guard(
        () => _t.track(name, properties: properties, type: EventType.error),
      );
    }
  }

  /// An uncaught error, from the app's one error sink. Only the error's type,
  /// where it came from and whether it was fatal: exception messages can carry
  /// record content (an LR or vehicle number in a parse error, a URL with
  /// search terms in a network error), so they are never sent.
  static void clientError(Object error, {String? source, bool fatal = false}) {
    if (!_on) return;
    String kind;
    try {
      kind = error.runtimeType.toString();
    } catch (_) {
      kind = 'unknown';
    }
    Telemetry.error(VistarEvents.clientError, {
      'kind': kind,
      'source': ?source,
      'fatal': fatal,
    });
  }

  static void _guard(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Analytics never surfaces as an app error.
    }
  }

  /// Fire and forget: the sign-in never waits for analytics.
  ///
  /// Called just BEFORE the auth state changes. With no sign-out in flight the
  /// SDK sets the user synchronously (before its first await), so the screen
  /// the sign-in leads to is already attributed to them.
  static void signedIn({required String userId, String? role, String? tenant}) {
    if (!_on || userId.isEmpty) return;
    final id = 'lr:$userId';
    final traits = <String, dynamic>{'role': ?role, 'org': ?tenant};
    final pending = _resetting;
    if (pending == null) {
      _identify(id, traits);
      return;
    }
    // A sign-out just before (a shared desk changing hands) resets the
    // identity; let it finish so this one is not wiped by it.
    unawaited(() async {
      try {
        await pending.timeout(const Duration(seconds: 5), onTimeout: () {});
      } catch (_) {}
      _identify(id, traits);
    }());
  }

  static void _identify(String id, Map<String, dynamic> traits) {
    try {
      unawaited(_t.identify(id, traits: traits).catchError((Object _) {}));
    } catch (_) {}
  }

  /// Fire and forget: the sign-out never waits for analytics (the SDK's reset
  /// sends what is queued first, which can take a while on a poor network).
  static void signedOut() {
    _lastScreen = null;
    if (!_on) return;
    try {
      late final Future<void> done;
      done = _t.reset().catchError((Object _) {}).whenComplete(() {
        if (identical(_resetting, done)) _resetting = null;
      });
      _resetting = done;
    } catch (_) {}
  }

  /// `/lrs/9f3c...-.../edit?x=1` -> `/lrs/:id/edit`.
  ///
  /// Every static segment of this app's screens and API paths is lower-case
  /// words joined by `-`, `_` or `.` (`vehicle-bank`, `lr-format`,
  /// `mis.xlsx`), so anything else is a value and is replaced: digits only or
  /// a UUID -> `:id`; anything else with a digit, a capital or another
  /// character -> `:ref`. That covers LR numbers in any configured format
  /// (`VLL-PUN-26-27-00012`, `LR12`; one with `/` in it splits into
  /// segments, each replaced), vehicle plates (`MH12AB1234`,
  /// `MH%2012%20AB%201234`) and lookup codes (`VEHICLE_CAPACITY`).
  static String routePattern(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    return path
        .split('/')
        .map((s) {
          if (s.isEmpty) return s;
          if (RegExp(r'^\d+$').hasMatch(s)) return ':id';
          if (RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-',
            caseSensitive: false,
          ).hasMatch(s)) {
            return ':id';
          }
          if (!RegExp(r'^[a-z]+([._-][a-z]+)*$').hasMatch(s)) return ':ref';
          return s;
        })
        .join('/');
  }

  /// Successful API writes worth naming, by method and path (ids stripped).
  /// First match wins; anything else is not reported. Paths are relative to
  /// API_BASE_URL (`.../api/v1/lr-management`).
  static final List<(String, RegExp, String)> _actions = [
    // Lorry receipts
    ('POST', RegExp(r'^/lrs$'), 'lr_created'),
    ('PATCH', RegExp(r'^/lrs/:id$'), 'lr_updated'),
    ('DELETE', RegExp(r'^/lrs/:id$'), 'lr_deleted'),
    ('POST', RegExp(r'^/lrs/:id/status$'), 'lr_status_changed'),
    ('POST', RegExp(r'^/lrs/:id/send-for-payment$'), 'lr_sent_for_payment'),
    ('POST', RegExp(r'^/lrs/:id/advance-paid$'), 'lr_advance_paid'),
    ('POST', RegExp(r'^/lrs/:id/payment-complete$'), 'lr_payment_completed'),
    ('POST', RegExp(r'^/lrs/:id/attachments$'), 'lr_attachment_uploaded'),
    ('DELETE', RegExp(r'^/lrs/:id/attachments/:id$'), 'lr_attachment_deleted'),
    ('POST', RegExp(r'^/lr-templates$'), 'lr_template_created'),
    ('PATCH', RegExp(r'^/lr-templates/:id$'), 'lr_template_updated'),
    ('DELETE', RegExp(r'^/lr-templates/:id$'), 'lr_template_deleted'),
    // E-way bills
    ('POST', RegExp(r'^/ewb$'), 'ewb_created'),
    ('PATCH', RegExp(r'^/ewb/:id$'), 'ewb_updated'),
    ('POST', RegExp(r'^/ewb/:id/validate$'), 'ewb_validated'),
    // Invoices
    ('POST', RegExp(r'^/invoices$'), 'invoice_created'),
    ('POST', RegExp(r'^/invoices/:id/cancel$'), 'invoice_cancelled'),
    ('PUT', RegExp(r'^/invoices/settings$'), 'invoice_settings_updated'),
    // Live tracking
    ('POST', RegExp(r'^/tracking/lr/:id/start$'), 'tracking_started'),
    (
      'POST',
      RegExp(r'^/tracking/lr/:id/consent-recheck$'),
      'tracking_consent_rechecked',
    ),
    ('POST', RegExp(r'^/tracking/lr/:id/public-link$'), 'tracking_link_shared'),
    // Reports
    ('POST', RegExp(r'^/reports/mis/import$'), 'mis_imported'),
    // Masters: <master>_created / _updated / _deleted, plus KYC documents.
    ('POST', RegExp(r'^/drivers/:id/document$'), 'driver_document_uploaded'),
    (
      'POST',
      RegExp(r'^/transporters/:id/document$'),
      'transporter_document_uploaded',
    ),
    (
      'DELETE',
      RegExp(r'^/transporters/:id/document$'),
      'transporter_document_deleted',
    ),
    for (final (path, master) in _masters) ...[
      ('POST', RegExp('^/$path\$'), '${master}_created'),
      ('PATCH', RegExp('^/$path/:id\$'), '${master}_updated'),
      ('DELETE', RegExp('^/$path/:id\$'), '${master}_deleted'),
    ],
    // Admin
    ('POST', RegExp(r'^/admin/users$'), 'user_created'),
    ('PATCH', RegExp(r'^/admin/users/:id$'), 'user_updated'),
    ('DELETE', RegExp(r'^/admin/users/:id$'), 'user_deleted'),
    (
      'PUT',
      RegExp(r'^/admin/users/:id/permissions$'),
      'user_permissions_changed',
    ),
    ('POST', RegExp(r'^/admin/regions$'), 'region_created'),
    ('PATCH', RegExp(r'^/admin/regions/:id$'), 'region_updated'),
    ('DELETE', RegExp(r'^/admin/regions/:id$'), 'region_deleted'),
    ('PATCH', RegExp(r'^/system/numbering$'), 'lr_numbering_updated'),
    ('PATCH', RegExp(r'^/system/lr-format$'), 'lr_format_updated'),
    ('POST', RegExp(r'^/lookups/manage/:ref$'), 'lookup_option_created'),
    (
      'PATCH',
      RegExp(r'^/lookups/manage/options/:id$'),
      'lookup_option_updated',
    ),
    (
      'DELETE',
      RegExp(r'^/lookups/manage/options/:id$'),
      'lookup_option_deleted',
    ),
    // Account
    ('POST', RegExp(r'^/auth/change-password$'), 'password_changed'),
  ];

  /// Master endpoints and the event-name stem for each.
  static const _masters = [
    ('parties', 'party'),
    ('consignors', 'consignor'),
    ('consignees', 'consignee'),
    ('vehicles', 'vehicle'),
    ('drivers', 'driver'),
    ('transporters', 'transporter'),
    ('routes', 'route'),
    ('part-descriptions', 'part_description'),
  ];

  /// The business event for a successful API call, or null.
  static String? actionFor(String method, String path) {
    final pattern = routePattern(path);
    final m = method.toUpperCase();
    for (final (am, re, name) in _actions) {
      if (am == m && re.hasMatch(pattern)) return name;
    }
    return null;
  }
}

/// Reports named actions and failed calls from the app's HTTP client
/// (core/network/api_client.dart). Adds no headers and changes nothing about
/// the request or its handling.
class TelemetryInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    // This client keeps Dio's default validateStatus, so a 4xx arrives in
    // onError, not here; the 2xx test is belt and braces. Only a 2xx is an
    // action that happened.
    final code = response.statusCode ?? 0;
    if (Telemetry.enabled && code >= 200 && code < 300) {
      String? name;
      try {
        final o = response.requestOptions;
        name = Telemetry.actionFor(o.method, o.path);
      } catch (_) {}
      if (name != null) Telemetry.track(name);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (Telemetry.enabled) {
      try {
        // A 4xx is a decision the server made (validation, conflict, a
        // permission); only 5xx and transport failures are errors here.
        final status = err.response?.statusCode;
        if (status == null || status >= 500) {
          Telemetry.error('api_error', {
            'endpoint': Telemetry.routePattern(err.requestOptions.path),
            'method': err.requestOptions.method,
            'status': ?status,
            'kind': err.type.name,
          });
        }
      } catch (_) {}
    }
    handler.next(err);
  }
}
