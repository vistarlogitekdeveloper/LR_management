// "Stop tracking" on the Track LR screen calls POST /tracking/lr/:id/stop
// (backend trackingController.stopTracking) and reads how many other LRs on
// the same truck keep the trip running.
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/core/network/api_client.dart';
import 'package:lr_management/core/network/token_storage.dart';
import 'package:lr_management/features/tracking/data/tracking_repository.dart';

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage() : super(const FlutterSecureStorage());
  @override
  Future<String?> readAccess() async => null;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> write({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

TrackingRepository _repo(List<RequestOptions> seen, Map<String, dynamic> data) {
  final api = ApiClient(_FakeTokenStorage());
  api.dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (o, h) {
        seen.add(o);
        h.resolve(
          Response(
            requestOptions: o,
            statusCode: 200,
            data: {'success': true, 'data': data},
          ),
        );
      },
    ),
  );
  return TrackingRepository(api);
}

void main() {
  test('posts to the stop endpoint of that LR', () async {
    final seen = <RequestOptions>[];
    final others = await _repo(seen, {
      'stopped': true,
      'other_lrs_on_trip': 0,
    }).stopTracking('lr-1');
    expect(seen.single.method, 'POST');
    expect(seen.single.path, '/tracking/lr/lr-1/stop');
    expect(others, 0);
  });

  test('reports the other LRs still riding the trip', () async {
    final others = await _repo([], {
      'stopped': true,
      'detached_only': true,
      'other_lrs_on_trip': 2,
    }).stopTracking('lr-1');
    expect(others, 2);
  });
}
