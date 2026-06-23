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

  @override
  String toString() =>
      'ApiException($status $code: $message${traceId != null ? ' [trace=$traceId]' : ''})';
}
