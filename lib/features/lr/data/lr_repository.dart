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

  /// Options for a version-locked write: the `If-Match` precondition, plus an
  /// opt-out from ApiClient's transient retry.
  ///
  /// The retry replays a request on a connection error, treating it as "never
  /// reached the server". That holds for a DNS or connect-timeout failure but
  /// NOT for a socket dropped mid-flight, which may well have been applied. On
  /// one of these writes the replay is actively harmful: the first attempt
  /// lands and bumps `version`, then the replay re-sends the SAME now-stale
  /// `If-Match` and comes back 412 — reporting a write that succeeded as
  /// "modified by someone else", and leaving the caller holding a version the
  /// server has moved past. Every one of these carries a precondition, so a
  /// silent second attempt can never be right.
  Options _lockedWrite(int version) => Options(
    headers: {'If-Match': version.toString()},
    extra: const {kNoRetryExtra: true},
  );

  /// Loads all LRs. A small FIRST page (100) paints the list almost instantly;
  /// the rest arrive in a single large page (backend allows up to 1000/page for
  /// /lrs). [onPage] fires with each page's parsed rows as it lands so the list
  /// can render progressively — the first rows show in well under a second even
  /// when the full set is large. The complete list is still returned.
  ///
  /// Deploy-order safe: an un-upgraded backend just clamps the 1000 limit to its
  /// own max and the walk continues over the extra pages.
  Future<List<LorryReceipt>> list({
    LrFilterParams filter = const LrFilterParams(),
    void Function(List<LorryReceipt> page)? onPage,
  }) async {
    List<LorryReceipt> mapRows(List<Map<String, dynamic>> raw) => raw
        .map((e) => LorryReceipt.fromJson(e, resolveLookup: _resolver))
        .toList();
    final rows = await fetchAllPages(
      _api,
      '/lrs',
      query: filter.toQuery(),
      firstPageSize: 100,
      pageSize: 1000,
      onPage: onPage == null ? null : (page) => onPage(mapRows(page)),
    );
    return mapRows(rows);
  }

  /// Backend-authoritative next LR number (mirrors the atomic counter, incl.
  /// the auto-heal max-used bump). Preferred over the local-list heuristic on
  /// the Create LR screen — the local heuristic drifts after a DB migration.
  Future<String> nextNumber() async {
    final res = await _api.dio.get('/lrs/next-number');
    return ((res.data['data'] as Map)['next_number'] ?? '').toString();
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
    String? idempotencyKey,
  }) async {
    final res = await _api.dio.post(
      '/lrs',
      data: payload,
      options: Options(
        headers: {'Idempotency-Key': idempotencyKey ?? _uuid.v4()},
      ),
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
      options: _lockedWrite(version),
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

  /// Releases the standard 90% transporter advance. The backend computes the
  /// amount (90% of transporter freight) and emails the LR creator + admins, so
  /// the client only needs to send the current version for the optimistic lock.
  Future<LorryReceipt> markAdvancePaid(String id, int version) async {
    await _api.dio.post(
      '/lrs/$id/advance-paid',
      options: _lockedWrite(version),
    );
    return getById(id);
  }

  /// Completes the payment: releases the balance held against POD so the
  /// transporter is paid in full. The backend settles the amount (full
  /// transporter freight) and emails the LR creator + admins.
  Future<LorryReceipt> completePayment(String id, int version) async {
    await _api.dio.post(
      '/lrs/$id/payment-complete',
      options: _lockedWrite(version),
    );
    return getById(id);
  }

  /// Sends the LR to Accounts for payment: flips `sent_for_payment` server-side
  /// and triggers the Accounts notification email. Until this is called the LR
  /// is NOT emailed and does NOT appear in the Accounts payment queue. Idempotent
  /// server-side (re-sending an already-sent LR must not email twice).
  Future<LorryReceipt> sendForPayment(String id, int version) async {
    await _api.dio.post(
      '/lrs/$id/send-for-payment',
      options: _lockedWrite(version),
    );
    return getById(id);
  }

  /// "Request for balance payment": uploads the POD and asks Accounts for the
  /// balance in one call (POST /lrs/:id/request-balance, multipart "file").
  /// Calling it again replaces the POD. Locked by `If-Match` like the other
  /// payment steps, and never retried — a replay would upload the POD twice.
  Future<LorryReceipt> requestBalance(
    String id,
    int version, {
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
    await _api.dio.post(
      '/lrs/$id/request-balance',
      data: FormData.fromMap({'file': multipart}),
      options: _lockedWrite(version),
    );
    return getById(id);
  }

  /// Moves the LR along the status graph. Carries no `If-Match` — the backend
  /// route deliberately omits `requireIfMatch` — but it DOES bump the LR's
  /// version and append a `lr_status_history` row, so a silent replay would
  /// double-count both. Opted out of the transient retry for that reason.
  Future<void> changeStatus(String id, String toCode, {String? reason}) async {
    await _api.dio.post(
      '/lrs/$id/status',
      data: {
        'to': toCode,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      options: Options(extra: const {kNoRetryExtra: true}),
    );
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/lrs/$id');
  }

  Future<void> _createEwb(String lrId, EwbInput ewb) async {
    await _api.dio.post(
      '/ewb',
      data: {
        'number': ewb.number.trim(),
        'lr_id': lrId,
        if (ewb.expiryAt != null)
          'expiry_at': ewb.expiryAt!.toIso8601String().substring(0, 10),
        if (ewb.loadTypeId != null && ewb.loadTypeId!.isNotEmpty)
          'load_type_id': ewb.loadTypeId,
      },
      // A replay would attach a SECOND e-way bill to the same LR.
      options: Options(extra: const {kNoRetryExtra: true}),
    );
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
      options: _lockedWrite(version),
    );
  }

  Future<void> uploadAttachment(
    String lrId, {
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
    await _api.dio.post(
      '/lrs/$lrId/attachments',
      data: form,
      // A replay would attach the same file twice. Dio also cannot re-send a
      // consumed FormData stream, so the retry would fail anyway — opting out
      // turns a confusing second error into the original one.
      options: Options(extra: const {kNoRetryExtra: true}),
    );
  }

  /// Downloads an attachment's raw bytes (auth header applied by the client).
  Future<List<int>> downloadAttachmentBytes(
    String lrId,
    String attachmentId,
  ) async {
    final res = await _api.dio.get(
      '/lrs/$lrId/attachments/$attachmentId/file',
      options: Options(responseType: ResponseType.bytes),
    );
    return (res.data as List).cast<int>();
  }

  /// Downloads an attachment with the name and type the server stored, for a
  /// caller that has only its id (the LR list carries no attachments — e.g.
  /// the POD a balance request points at). Falls back to [fallbackName].
  Future<({List<int> bytes, String fileName, String mimeType})>
  downloadAttachment(
    String lrId,
    String attachmentId, {
    String fallbackName = 'file',
  }) async {
    final res = await _api.dio.get(
      '/lrs/$lrId/attachments/$attachmentId/file',
      options: Options(responseType: ResponseType.bytes),
    );
    final type = res.headers.value('content-type') ?? '';
    // Content-Disposition: inline; filename="<url-encoded name>"
    final disposition = res.headers.value('content-disposition') ?? '';
    final match = RegExp(r'filename="([^"]*)"').firstMatch(disposition);
    var name = fallbackName;
    if (match != null && match.group(1)!.isNotEmpty) {
      try {
        name = Uri.decodeComponent(match.group(1)!);
      } catch (_) {
        name = match.group(1)!;
      }
    }
    return (
      bytes: (res.data as List).cast<int>(),
      fileName: name,
      mimeType: type.split(';').first.trim(),
    );
  }

  Future<void> deleteAttachment(String lrId, String attachmentId) async {
    await _api.dio.delete('/lrs/$lrId/attachments/$attachmentId');
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
    case 'xls':
      return DioMediaType('application', 'vnd.ms-excel');
    case 'xlsx':
      return DioMediaType(
        'application',
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    case 'doc':
      return DioMediaType('application', 'msword');
    case 'docx':
      return DioMediaType(
        'application',
        'vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    case 'csv':
      return DioMediaType('text', 'csv');
    default:
      return DioMediaType('application', 'octet-stream');
  }
}
