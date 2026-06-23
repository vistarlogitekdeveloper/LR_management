import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';

class EwbRecord {
  final String id;
  final String number;
  final String? lrId;
  final String lrNumber;
  final String loadType;
  final DateTime? expiry;
  final DateTime? issuedAt;
  final String validationStatus;
  final int version;

  const EwbRecord({
    required this.id,
    required this.number,
    this.lrId,
    this.lrNumber = '',
    this.loadType = '',
    this.expiry,
    this.issuedAt,
    this.validationStatus = 'pending',
    this.version = 0,
  });

  factory EwbRecord.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      return v is Map ? v.cast<String, dynamic>() : null;
    }

    final lr = nested('lr') ?? nested('lorryReceipt');
    final load = nested('loadType');
    return EwbRecord(
      id: (json['id'] as String?) ?? '',
      number: (json['number'] as String?) ?? '',
      lrId: json['lr_id'] as String?,
      lrNumber: (lr?['number'] as String?) ?? '',
      loadType: (load?['label'] as String?) ?? '',
      expiry: DateTime.tryParse(json['expiry_at']?.toString() ?? ''),
      issuedAt: DateTime.tryParse(json['issued_at']?.toString() ?? ''),
      validationStatus: (json['validation_status'] as String?) ?? 'pending',
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }
}

class EwbRepository {
  EwbRepository(this._api);
  final ApiClient _api;

  Future<List<EwbRecord>> list() async {
    final rows = await fetchAllPages(_api, '/ewb');
    return rows.map(EwbRecord.fromJson).toList();
  }

  Future<void> validate(String id) async {
    await _api.dio.post('/ewb/$id/validate');
  }
}
