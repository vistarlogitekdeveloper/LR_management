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
        handler.next(options);
      },
      onError: (e, handler) async {
        final isAuthFailure = e.response?.statusCode == 401;
        final alreadyRetried = e.requestOptions.extra['__retried'] == true;
        if (!isAuthFailure || alreadyRetried) {
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
        } catch (_) {
          _refreshing = false;
          await _tokens.clear();
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

  Future<String> _refreshTokens(String refreshToken) async {
    // Bare Dio to avoid recursing through this interceptor.
    final raw = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
    final res = await raw.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    final data = (res.data['data'] as Map).cast<String, dynamic>();
    final access = data['access_token'] as String;
    final refresh = (data['refresh_token'] as String?) ?? refreshToken;
    await _tokens.write(access: access, refresh: refresh);
    return access;
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

  DioException _withMappedError(DioException e) {
    final status = e.response?.statusCode ?? 0;
    final body = e.response?.data;
    String code = 'NETWORK_ERROR';
    String message = e.message ?? 'Network error';
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
