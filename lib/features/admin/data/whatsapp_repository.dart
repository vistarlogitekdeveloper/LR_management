import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';

/// One WhatsApp alert kind and whether it is on (server: /whatsapp/status).
class WhatsappAlertKind {
  final String kind;
  final String label;
  final String template;
  final bool on;
  const WhatsappAlertKind({
    required this.kind,
    required this.label,
    required this.template,
    required this.on,
  });

  factory WhatsappAlertKind.fromJson(Map<String, dynamic> j) =>
      WhatsappAlertKind(
        kind: (j['kind'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        template: (j['template'] ?? '').toString(),
        on: j['on'] != false,
      );
}

class WhatsappStatus {
  /// The server has a token and a phone number id.
  final bool configured;

  /// …and WHATSAPP_ENABLED is true: alerts are being sent.
  final bool enabled;
  final List<WhatsappAlertKind> alerts;
  const WhatsappStatus({
    required this.configured,
    required this.enabled,
    required this.alerts,
  });

  factory WhatsappStatus.fromJson(Map<String, dynamic> j) => WhatsappStatus(
    configured: j['configured'] == true,
    enabled: j['enabled'] == true,
    alerts: (j['alerts'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => WhatsappAlertKind.fromJson(m.cast<String, dynamic>()))
        .toList(),
  );
}

/// One sent alert in the log (server: lr_management.whatsapp_messages).
class WhatsappMessage {
  final String id;
  final String kind;
  final String toPhone;
  final String template;
  final String status;
  final String? error;
  final DateTime? createdAt;
  final DateTime? statusAt;
  const WhatsappMessage({
    required this.id,
    required this.kind,
    required this.toPhone,
    required this.template,
    required this.status,
    this.error,
    this.createdAt,
    this.statusAt,
  });

  factory WhatsappMessage.fromJson(Map<String, dynamic> j) {
    DateTime? dt(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return WhatsappMessage(
      id: (j['id'] ?? '').toString(),
      kind: (j['kind'] ?? '').toString(),
      toPhone: (j['to_phone'] ?? '').toString(),
      template: (j['template'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      error: j['error'] as String?,
      createdAt: dt(j['created_at']),
      statusAt: dt(j['status_at']),
    );
  }
}

class WhatsappRepository {
  WhatsappRepository(this._api);
  final ApiClient _api;

  Future<WhatsappStatus> status() async {
    final res = await _api.dio.get('/whatsapp/status');
    return WhatsappStatus.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> setAlert(String kind, bool on) =>
      _api.dio.put('/whatsapp/settings', data: {kind: on});

  Future<void> sendTest(String mobile) =>
      _api.dio.post('/whatsapp/test', data: {'mobile': mobile});

  Future<List<WhatsappMessage>> messages({int limit = 100}) async {
    final res = await _api.dio.get(
      '/whatsapp/messages',
      queryParameters: {'limit': limit},
    );
    return (res.data['data'] as List)
        .whereType<Map>()
        .map((m) => WhatsappMessage.fromJson(m.cast<String, dynamic>()))
        .toList();
  }
}

final whatsappRepositoryProvider = Provider<WhatsappRepository>(
  (ref) => WhatsappRepository(ref.watch(apiClientProvider)),
);

final whatsappStatusProvider = FutureProvider.autoDispose<WhatsappStatus>(
  (ref) => ref.watch(whatsappRepositoryProvider).status(),
);

final whatsappMessagesProvider =
    FutureProvider.autoDispose<List<WhatsappMessage>>(
      (ref) => ref.watch(whatsappRepositoryProvider).messages(),
    );
