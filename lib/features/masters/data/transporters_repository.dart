import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/transporter.dart';

class TransportersRepository {
  TransportersRepository(this._api);
  final ApiClient _api;

  Future<List<Transporter>> list({String? query}) async {
    final rows = await fetchAllPages(
      _api,
      '/transporters',
      query: {if (query != null && query.isNotEmpty) 'q': query},
    );
    return rows.map(Transporter.fromJson).toList();
  }

  Future<Transporter> create(Transporter t) async {
    final res = await _api.dio.post('/transporters', data: t.toJson());
    return Transporter.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<Transporter> update(Transporter t) async {
    Future<Transporter> patch(int version) async {
      final res = await _api.dio.patch(
        '/transporters/${t.id}',
        data: t.toJson(),
        options: Options(headers: {'If-Match': version.toString()}),
      );
      return Transporter.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>(),
      );
    }

    try {
      return await patch(t.version);
    } on DioException catch (e) {
      // A transporter's version moves out-of-band when its cheque/passbook
      // document is uploaded or removed (those bump the version), so the form's
      // loaded version can be behind by the time the user saves. The 412 body
      // carries the server's current version — retry once against it so a
      // self-inflicted conflict doesn't reject the user's edit. The backend
      // deep-merges bank_account, so the stored document/OCR data survives.
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
    await _api.dio.delete('/transporters/$id');
  }

  /// Uploads a transporter document and returns the updated transporter.
  /// [type] is 'cheque' (blank cheque / passbook, default) or 'tds' (TDS
  /// attachment). Works on web (bytes) and native (filePath).
  Future<Transporter> uploadDocument(
    String id, {
    required String fileName,
    List<int>? bytes,
    String? filePath,
    String type = 'cheque',
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
      '/transporters/$id/document',
      data: form,
      queryParameters: {'type': type},
    );
    return Transporter.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  /// Downloads the document bytes ([type] 'cheque' or 'tds').
  Future<List<int>> downloadDocument(
    String id, {
    String type = 'cheque',
  }) async {
    final res = await _api.dio.get(
      '/transporters/$id/document',
      queryParameters: {'type': type},
      options: Options(responseType: ResponseType.bytes),
    );
    return (res.data as List).cast<int>();
  }

  Future<Transporter> deleteDocument(
    String id, {
    String type = 'cheque',
  }) async {
    final res = await _api.dio.delete(
      '/transporters/$id/document',
      queryParameters: {'type': type},
    );
    return Transporter.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
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
