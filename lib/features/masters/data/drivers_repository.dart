import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/driver.dart';

class DriversRepository {
  DriversRepository(this._api);
  final ApiClient _api;

  Future<List<Driver>> list({String? query}) async {
    final rows = await fetchAllPages(
      _api,
      '/drivers',
      query: {if (query != null && query.isNotEmpty) 'q': query},
    );
    return rows.map(Driver.fromJson).toList();
  }

  Future<Driver> create(Driver d) async {
    final res = await _api.dio.post('/drivers', data: d.toJson());
    return Driver.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Driver> update(Driver d) async {
    Future<Driver> patch(int version) async {
      final res = await _api.dio.patch(
        '/drivers/${d.id}',
        data: d.toJson(),
        options: Options(headers: {'If-Match': version.toString()}),
      );
      return Driver.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    }

    try {
      return await patch(d.version);
    } on DioException catch (e) {
      // Same conflict as the transporter master: a driver's version now moves
      // out-of-band whenever an Aadhaar/PAN scan is attached or removed (those
      // endpoints bump it), so the version the form loaded can be behind by the
      // time the user saves — most easily when an upload failed after the row
      // itself had already been patched, and the user hits Save again. The 412
      // body carries the server's current version; retry once against it rather
      // than rejecting the edit. Nothing is lost by the retry: `documents` is
      // its own column and Driver.toJson never sends it.
      final data = e.response?.data;
      final raw = data is Map ? data['current_version'] : null;
      final current = raw is num
          ? raw.toInt()
          : (raw is String ? int.tryParse(raw) : null);
      if (e.response?.statusCode == 412 && current != null) {
        return patch(current);
      }
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/drivers/$id');
  }

  /// Uploads a driver KYC scan and returns the updated driver.
  ///
  /// [type] is 'aadhaar' or 'pan' — unlike the transporter endpoint there is no
  /// default on the server, so it is always sent. The response carries the new
  /// `documents` blob, so the caller needs no refetch. Works on web (bytes) and
  /// native (filePath).
  Future<Driver> uploadDocument(
    String id, {
    required String type,
    required String fileName,
    List<int>? bytes,
    String? filePath,
  }) async {
    final contentType = _mediaTypeForName(fileName);
    final MultipartFile multipart;
    if (bytes != null) {
      multipart = MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: contentType,
      );
    } else if (filePath != null) {
      multipart = await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: contentType,
      );
    } else {
      throw ArgumentError('Either bytes or filePath is required');
    }
    final form = FormData.fromMap({'file': multipart});
    final res = await _api.dio.post(
      '/drivers/$id/document',
      data: form,
      queryParameters: {'type': type},
    );
    return Driver.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  /// Downloads a driver KYC scan ([type] 'aadhaar' or 'pan').
  Future<List<int>> downloadDocument(
    String id, {
    required String type,
  }) async {
    final res = await _api.dio.get(
      '/drivers/$id/document',
      queryParameters: {'type': type},
      options: Options(responseType: ResponseType.bytes),
    );
    return (res.data as List).cast<int>();
  }
}

/// Maps a filename extension to a content type so the server's MIME allowlist
/// accepts the upload (Dio otherwise defaults to application/octet-stream).
DioMediaType _mediaTypeForName(String fileName) {
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  switch (ext) {
    case 'pdf':
      return DioMediaType('application', 'pdf');
    case 'jpg':
    case 'jpeg':
      return DioMediaType('image', 'jpeg');
    case 'png':
      return DioMediaType('image', 'png');
    case 'webp':
      return DioMediaType('image', 'webp');
    case 'heic':
      return DioMediaType('image', 'heic');
    default:
      return DioMediaType('application', 'octet-stream');
  }
}
