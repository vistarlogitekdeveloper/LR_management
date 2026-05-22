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
}
