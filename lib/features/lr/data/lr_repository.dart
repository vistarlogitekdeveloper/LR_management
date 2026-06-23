import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../features/lookups/data/lookup_value.dart';
import '../../../shared/models/lr_models.dart';

/// Optional E-way bill payload attached to an LR on create/update. EWBs live in
/// their own backend table (`/ewb`) linked by `lr_id`, so the repository creates
/// or patches them as a follow-up step to the LR write.
class EwbInput {
  final String number;
  final DateTime? expiryAt;
  final String? loadTypeId;
  const EwbInput({required this.number, this.expiryAt, this.loadTypeId});

  bool get isEmpty => number.trim().isEmpty;
}

class LrFilterParams {
  final String? query;
  final String? statusId;
  final String? consignorId;
  final String? consigneeId;
  final String? vehicleId;
  final String? routeId;
  final String? fromDate; // YYYY-MM-DD
  final String? toDate;
  const LrFilterParams({
    this.query,
    this.statusId,
    this.consignorId,
    this.consigneeId,
    this.vehicleId,
    this.routeId,
    this.fromDate,
    this.toDate,
  });

  Map<String, dynamic> toQuery() => {
        if (query != null && query!.isNotEmpty) 'q': query,
        if (statusId != null && statusId!.isNotEmpty) 'status_id': statusId,
        if (consignorId != null && consignorId!.isNotEmpty)
          'consignor_id': consignorId,
        if (consigneeId != null && consigneeId!.isNotEmpty)
          'consignee_id': consigneeId,
        if (vehicleId != null && vehicleId!.isNotEmpty) 'vehicle_id': vehicleId,
        if (routeId != null && routeId!.isNotEmpty) 'route_id': routeId,
        if (fromDate != null && fromDate!.isNotEmpty) 'from_date': fromDate,
        if (toDate != null && toDate!.isNotEmpty) 'to_date': toDate,
      };
}

class LrRepository {
  LrRepository(this._api, this._lookups);
  final ApiClient _api;
  final Map<String, List<LookupValue>> _lookups;

  static const _uuid = Uuid();

  /// Resolves a lookup id to its human label using the live lookups map.
  String _resolve(String category, String? id) {
    if (id == null || id.isEmpty) return '';
    for (final v in _lookups[category] ?? const <LookupValue>[]) {
      if (v.id == id) return v.label;
    }
    return '';
  }

  LookupResolver get _resolver => _resolve;

  Future<List<LorryReceipt>> list([LrFilterParams filter = const LrFilterParams()]) async {
    final rows = await fetchAllPages(_api, '/lrs', query: filter.toQuery());
    return rows
        .map((e) => LorryReceipt.fromJson(e, resolveLookup: _resolver))
        .toList();
  }

  Future<LorryReceipt> getById(String id) async {
    final res = await _api.dio.get('/lrs/$id');
    return LorryReceipt.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
      resolveLookup: _resolver,
    );
  }

  Future<LorryReceipt> create(
    Map<String, dynamic> payload, {
    EwbInput? ewb,
  }) async {
    final res = await _api.dio.post(
      '/lrs',
      data: payload,
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
    final created = (res.data['data'] as Map).cast<String, dynamic>();
    final id = created['id'] as String;
    if (ewb != null && !ewb.isEmpty) {
      await _createEwb(id, ewb);
    }
    return getById(id);
  }

  Future<LorryReceipt> update(
    String id,
    int version,
    Map<String, dynamic> payload, {
    EwbInput? ewb,
    String? existingEwbId,
    int existingEwbVersion = 0,
  }) async {
    await _api.dio.patch(
      '/lrs/$id',
      data: payload,
      options: Options(headers: {'If-Match': version.toString()}),
    );
    if (ewb != null && !ewb.isEmpty) {
      if (existingEwbId != null && existingEwbId.isNotEmpty) {
        await _updateEwb(existingEwbId, existingEwbVersion, ewb);
      } else {
        await _createEwb(id, ewb);
      }
    }
    return getById(id);
  }

  Future<void> changeStatus(String id, String toCode, {String? reason}) async {
    await _api.dio.post('/lrs/$id/status', data: {
      'to': toCode,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/lrs/$id');
  }

  Future<void> _createEwb(String lrId, EwbInput ewb) async {
    await _api.dio.post('/ewb', data: {
      'number': ewb.number.trim(),
      'lr_id': lrId,
      if (ewb.expiryAt != null)
        'expiry_at': ewb.expiryAt!.toIso8601String().substring(0, 10),
      if (ewb.loadTypeId != null && ewb.loadTypeId!.isNotEmpty)
        'load_type_id': ewb.loadTypeId,
    });
  }

  Future<void> _updateEwb(String ewbId, int version, EwbInput ewb) async {
    await _api.dio.patch(
      '/ewb/$ewbId',
      data: {
        if (ewb.expiryAt != null)
          'expiry_at': ewb.expiryAt!.toIso8601String().substring(0, 10),
        if (ewb.loadTypeId != null && ewb.loadTypeId!.isNotEmpty)
          'load_type_id': ewb.loadTypeId,
      },
      options: Options(headers: {'If-Match': version.toString()}),
    );
  }

  Future<void> uploadAttachment(
    String lrId, {
    required String fileName,
    List<int>? bytes,
    String? filePath,
  }) async {
    final MultipartFile multipart;
    if (bytes != null) {
      multipart = MultipartFile.fromBytes(bytes, filename: fileName);
    } else if (filePath != null) {
      multipart = await MultipartFile.fromFile(filePath, filename: fileName);
    } else {
      throw ArgumentError('Either bytes or filePath is required');
    }
    final form = FormData.fromMap({'file': multipart});
    await _api.dio.post('/lrs/$lrId/attachments', data: form);
  }

  Future<void> deleteAttachment(String lrId, String attachmentId) async {
    await _api.dio.delete('/lrs/$lrId/attachments/$attachmentId');
  }
}
