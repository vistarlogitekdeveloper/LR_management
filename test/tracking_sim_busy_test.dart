import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/core/network/api_exception.dart';

/// The SIM-clash path, asserted at the seam that actually broke in production:
/// `api_client` attaches the backend error as `DioException.error` rather than
/// throwing the [ApiException] itself, so anything type-testing the thrown
/// object missed it and printed Dio's whole wrapper to the operator.
void main() {
  ApiException simBusy({bool canTakeover = true, List<String>? blocking}) =>
      ApiException(
        status: 409,
        code: 'SIM_BUSY',
        message:
            'Driver "RAFIK0323"\'s mobile 9165075556 is already being tracked '
            'for vehicle MH20EL9550 (LR/SBN/26-27/01800).',
        details: {
          'success': false,
          'code': 'SIM_BUSY',
          'can_takeover': canTakeover,
          'blocking_lrs': blocking ?? const ['LR/SBN/26-27/01800'],
          'running_truck': 'MH20EL9550',
        },
      );

  DioException wrap(ApiException api) => DioException(
    requestOptions: RequestOptions(path: '/tracking/lr/x/start'),
    response: Response(
      requestOptions: RequestOptions(path: '/tracking/lr/x/start'),
      statusCode: 409,
    ),
    type: DioExceptionType.badResponse,
    error: api,
  );

  test('asApiException unwraps the error dio actually throws', () {
    final api = simBusy();
    expect(asApiException(wrap(api)), same(api));
    expect(asApiException(api), same(api), reason: 'bare ApiException too');
    expect(asApiException('not an api error'), isNull);
    expect(asApiException(null), isNull);
  });

  test(
    'friendlyErrorMessage returns the backend sentence, never a Dio dump',
    () {
      final msg = friendlyErrorMessage(wrap(simBusy()));
      expect(msg, contains('already being tracked'));
      expect(msg, contains('MH20EL9550'));
      // The regression: Dio's wrapper text must not reach the operator.
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('validateStatus')));
      expect(msg, isNot(contains('developer.mozilla.org')));
    },
  );

  test('isSimBusy identifies only the SIM clash', () {
    expect(simBusy().isSimBusy, isTrue);
    expect(
      ApiException(
        status: 409,
        code: 'IDEMPOTENCY_CONFLICT',
        message: 'x',
      ).isSimBusy,
      isFalse,
    );
    expect(
      ApiException(status: 400, code: 'SIM_BUSY', message: 'x').isSimBusy,
      isFalse,
    );
  });

  test('takeover affordance is driven by the backend flag, not assumed', () {
    Map<String, dynamic> d(ApiException e) => e.details as Map<String, dynamic>;
    expect(d(simBusy())['can_takeover'], isTrue);
    expect(d(simBusy(canTakeover: false))['can_takeover'], isFalse);
    // The prompt names what would stop, so the operator decides knowingly.
    expect(d(simBusy())['blocking_lrs'], ['LR/SBN/26-27/01800']);
    expect(d(simBusy(blocking: []))['blocking_lrs'], isEmpty);
  });

  test('network failures get plain language instead of an exception dump', () {
    for (final entry in {
      DioExceptionType.connectionTimeout: 'took too long',
      DioExceptionType.receiveTimeout: 'took too long',
      DioExceptionType.connectionError: 'Could not reach the server',
      DioExceptionType.badCertificate: 'secure connection',
    }.entries) {
      final msg = friendlyErrorMessage(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: entry.key,
        ),
      );
      expect(msg, contains(entry.value), reason: '${entry.key}');
      expect(msg, isNot(contains('DioException')));
    }
  });

  test('401 and 403 read as session/permission problems', () {
    expect(
      friendlyErrorMessage(
        ApiException(status: 401, code: 'NO_TOKEN', message: 'raw'),
      ),
      contains('session has expired'),
    );
    expect(
      friendlyErrorMessage(
        ApiException(status: 403, code: 'FORBIDDEN', message: 'raw'),
      ),
      contains("don't have permission"),
    );
  });
}
