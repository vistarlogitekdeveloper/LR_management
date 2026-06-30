import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'token_storage.dart';

class ApiClient {
  ApiClient(this._tokens)
      : _dio = Dio(BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: ApiConfig.connectTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          // Never serve stale data from the browser HTTP cache — this is a
          // live operational app, so every read must hit the server.
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        )) {
    _dio.interceptors.add(_buildAuthInterceptor());
  }

  final Dio _dio;
  final TokenStorage _tokens;

  bool _refreshing = false;
  final List<_PendingRequest> _queue = [];

  Dio get dio => _dio;

  InterceptorsWrapper _buildAuthInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokens.readAccess();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        // Cache-bust GET reads so the browser can never hand back a stale body
        // (e.g. after a backend deploy that changes the response shape).
        if (options.method.toUpperCase() == 'GET') {
          options.queryParameters = {
            ...options.queryParameters,
            '_ts': DateTime.now().millisecondsSinceEpoch,
          };
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final isAuthFailure = e.response?.statusCode == 401;
        final alreadyRetried = e.requestOptions.extra['__retried'] == true;
        if (!isAuthFailure || alreadyRetried) {
          // Transient upstream errors (e.g. the DB briefly unreachable) on
          // idempotent GETs are retried a couple of times before surfacing.
          if (await _maybeRetryTransient(e, handler)) return;
          handler.next(_withMappedError(e));
          return;
        }

        final refresh = await _tokens.readRefresh();
        if (refresh == null || refresh.isEmpty) {
          await _tokens.clear();
          handler.next(_withMappedError(e));
          return;
        }

        if (_refreshing) {
          _queue.add(_PendingRequest(e.requestOptions, handler));
          return;
        }

        _refreshing = true;
        try {
          final newAccess = await _refreshTokens(refresh);
          _refreshing = false;
          final waiting = [
            _PendingRequest(e.requestOptions, handler),
            ..._queue,
          ];
          _queue.clear();
          for (final pending in waiting) {
            await _replay(pending, newAccess);
          }
        } catch (refreshErr) {
          _refreshing = false;
          // Only a DEFINITIVE rejection (a 4xx from /auth/refresh — the refresh
          // token is genuinely invalid or revoked) clears the saved session. A
          // transient failure (backend cold-start 5xx, timeout, offline) keeps
          // the tokens so the NEXT launch can recover instead of forcing a
          // needless re-login.
          final st = refreshErr is DioException
              ? (refreshErr.response?.statusCode ?? 0)
              : 0;
          if (st >= 400 && st < 500) {
            await _tokens.clear();
          }
          final waiting = [..._queue];
          _queue.clear();
          for (final pending in waiting) {
            pending.handler.next(_withMappedError(e));
          }
          handler.next(_withMappedError(e));
        }
      },
    );
  }

  /// Retries idempotent GETs on transient upstream failures (5xx) using a bare
  /// Dio so it doesn't recurse through this interceptor. Returns true when it
  /// resolved the request. The original request's headers (incl. auth) are
  /// preserved on `RequestOptions`.
  Future<bool> _maybeRetryTransient(
    DioException e,
    ErrorInterceptorHandler handler,
  ) async {
    final opts = e.requestOptions;
    final status = e.response?.statusCode ?? 0;
    final transient5xx =
        status == 500 || status == 502 || status == 503 || status == 504;
    // A pre-connection failure (DNS lookup / connect timeout) means the request
    // never reached the server, so retrying is safe for ANY method — this is
    // the common flaky-mobile-network case (e.g. "Failed host lookup").
    final preConnect = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout;
    final retryGet5xx = opts.method.toUpperCase() == 'GET' && transient5xx;
    if (!preConnect && !retryGet5xx) return false;

    final bare = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
    for (var attempt = 1; attempt <= 2; attempt++) {
      await Future.delayed(Duration(milliseconds: 400 * attempt));
      try {
        final resp = await bare.fetch(opts);
        handler.resolve(resp);
        return true;
      } on DioException {
        // try again, then fall through to surface the original error
      }
    }
    return false;
  }

  Future<String> _refreshTokens(String refreshToken) async {
    // Bare Dio to avoid recursing through this interceptor. Generous timeouts +
    // a few retries so a cold-starting backend (Render free tier spins down
    // after inactivity) doesn't fail the refresh and nuke the session on
    // reopen. The refresh token is only rotated on a SUCCESSFUL response, so
    // retrying after a transient failure is safe (the token wasn't consumed).
    final raw = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
    DioException? lastErr;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final res = await raw.post(
          '/auth/refresh',
          data: {'refresh_token': refreshToken},
        );
        final data = (res.data['data'] as Map).cast<String, dynamic>();
        final access = data['access_token'] as String;
        final refresh = (data['refresh_token'] as String?) ?? refreshToken;
        await _tokens.write(access: access, refresh: refresh);
        return access;
      } on DioException catch (e) {
        // A 4xx means the refresh token is genuinely bad — stop and surface it.
        final status = e.response?.statusCode ?? 0;
        if (status >= 400 && status < 500) rethrow;
        // Transient (5xx / timeout / connection) — wait for the backend to wake.
        lastErr = e;
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 700 * attempt));
        }
      }
    }
    throw lastErr!;
  }

  Future<void> _replay(_PendingRequest pending, String newAccess) async {
    final opts = pending.options;
    opts.extra['__retried'] = true;
    opts.headers['Authorization'] = 'Bearer $newAccess';
    try {
      final resp = await _dio.fetch(opts);
      pending.handler.resolve(resp);
    } on DioException catch (err) {
      pending.handler.next(_withMappedError(err));
    }
  }

  // Turns Dio's raw transport errors (e.g. "Failed host lookup: '…'") into a
  // short, human message. Server errors with a JSON body override this below.
  String _friendlyNetworkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server is taking too long to respond. Please check your '
            'internet connection and try again.';
      case DioExceptionType.connectionError:
        return "Can't reach the server. Please check your internet connection "
            'and try again.';
      case DioExceptionType.badCertificate:
        return 'Secure connection to the server failed. Please try again.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        final raw = e.message ?? '';
        if (raw.contains('Failed host lookup') ||
            raw.contains('SocketException') ||
            raw.contains('XMLHttpRequest') ||
            raw.contains('Connection refused')) {
          return "Can't reach the server. Please check your internet "
              'connection and try again.';
        }
        return 'Something went wrong. Please try again.';
    }
  }

  DioException _withMappedError(DioException e) {
    final status = e.response?.statusCode ?? 0;
    final body = e.response?.data;
    String code = 'NETWORK_ERROR';
    String message = _friendlyNetworkMessage(e);
    String? traceId;
    dynamic details;
    if (body is Map) {
      code = body['code']?.toString() ?? code;
      message = body['error']?.toString() ?? message;
      traceId = body['traceId']?.toString();
      // VALIDATION_ERROR ships Joi's details[]; VERSION_CONFLICT ships
      // current_version; HAS_REFERENCES ships references{}. Keep the whole
      // body so callers can read whichever they need.
      details = body;
    }
    return e.copyWith(
      error: ApiException(
        status: status,
        code: code,
        message: message,
        traceId: traceId,
        details: details,
      ),
    );
  }
}

class _PendingRequest {
  _PendingRequest(this.options, this.handler);
  final RequestOptions options;
  final ErrorInterceptorHandler handler;
}
