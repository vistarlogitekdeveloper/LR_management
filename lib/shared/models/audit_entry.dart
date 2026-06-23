class AuditEntry {
  final String id;
  final String user;
  final String action;
  final String entity;
  final String? entityRef;
  final DateTime timestamp;
  final String? details;

  const AuditEntry({
    required this.id,
    required this.user,
    required this.action,
    required this.entity,
    this.entityRef,
    required this.timestamp,
    this.details,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? nested(String key) {
      final v = json[key];
      return v is Map ? v.cast<String, dynamic>() : null;
    }

    final changedBy = nested('changedBy') ?? nested('user');
    return AuditEntry(
      id: (json['id'] as String?) ?? '',
      user: (changedBy?['username'] as String?) ??
          (changedBy?['name'] as String?) ??
          (json['changed_by'] as String?) ??
          'system',
      action: (json['action'] as String?) ?? '',
      entity: (json['entity_type'] as String?) ??
          (json['entity'] as String?) ??
          '',
      entityRef:
          (json['entity_ref'] as String?) ?? (json['entity_id'] as String?),
      timestamp: DateTime.tryParse(
              (json['changed_at'] ?? json['created_at'])?.toString() ?? '') ??
          DateTime.now(),
      details: json['details'] as String?,
    );
  }
}
