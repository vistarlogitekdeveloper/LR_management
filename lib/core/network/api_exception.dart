import 'package:dio/dio.dart';

/// Pulls the real [ApiException] out of whatever was thrown.
///
/// This matters more than it looks. `api_client.dart` attaches the parsed
/// backend error as `DioException.error` — it does not throw the
/// [ApiException] itself — so a bare `e is ApiException` test never matches.
/// Every caller that relied on one fell through to `e.toString()` and showed
/// the operator Dio's whole wrapper:
///
///   DioException [bad response]: This exception was thrown because the
///   response has a status code of 409 and RequestOptions.validateStatus was
///   configured to throw for this status code… Read more about status codes at
///   https://developer.mozilla.org/… In order to resolve this exception you
///   typically have either to verify and fix your request code…
///
/// with the one sentence that actually helps buried at the very end.
ApiException? asApiException(Object? error) {
  if (error is ApiException) return error;
  if (error is DioException && error.error is ApiException) {
    return error.error as ApiException;
  }
  return null;
}

/// UI-friendly rendering of an error caught from an API call.
///
/// Always returns something an operator can act on: the backend's own message
/// when there is one, a plain-language network message when the request never
/// got a reply, and a generic line otherwise. Never a class dump, a stack
/// trace, a URL or a trace id (those belong in logs, not on screen).
String friendlyErrorMessage(Object e) {
  final api = asApiException(e);
  if (api != null) {
    if (api.isVersionConflict) {
      return 'This record was updated in the background — its details have been '
          'refreshed. Please review and try again.';
    }
    if (api.isUnauthorized) {
      return 'Your session has expired. Please sign in again.';
    }
    if (api.isForbidden) {
      return "You don't have permission to do this.";
    }
    // The backend writes these for the operator (e.g. the SIM_BUSY explanation),
    // so pass it straight through.
    return api.message;
  }

  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Please check your '
            'connection and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Please check your internet '
            'connection and try again.';
      case DioExceptionType.badCertificate:
        return 'Could not establish a secure connection to the server.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return 'Something went wrong on the server. Please try again.';
    }
  }

  return 'Something went wrong. Please try again.';
}

class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.traceId,
    this.details,
  });

  final int status;
  final String code;
  final String message;
  final String? traceId;

  /// Raw body for VALIDATION_ERROR (Joi `details[]`) and any other code that
  /// returns extra fields. Kept as dynamic so callers can read what they need.
  final dynamic details;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isValidation => code == 'VALIDATION_ERROR';
  bool get isVersionConflict => status == 412 || code == 'VERSION_CONFLICT';
  bool get isPreconditionRequired => status == 428;
  bool get isRateLimited => status == 429;

  /// The driver's phone is already on a running trip for another vehicle, so
  /// this LR cannot start one of its own. Worth surfacing prominently rather
  /// than in a snackbar: the resolution is a dispatch decision, not a retry.
  bool get isSimBusy => status == 409 && code == 'SIM_BUSY';

  @override
  String toString() =>
      'ApiException($status $code: $message${traceId != null ? ' [trace=$traceId]' : ''})';
}
