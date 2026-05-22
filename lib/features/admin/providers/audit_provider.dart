import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/audit_entry.dart';

class AuditNotifier extends StateNotifier<List<AuditEntry>> {
  AuditNotifier() : super(_seed());

  static List<AuditEntry> _seed() {
    final now = DateTime.now();
    return [
      AuditEntry(
        id: const Uuid().v4(),
        user: 'admin',
        action: 'LOGIN',
        entity: 'Session',
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      AuditEntry(
        id: const Uuid().v4(),
        user: 'anita',
        action: 'CREATE',
        entity: 'LR',
        entityRef: 'VLL/25/11/00057',
        timestamp: now.subtract(const Duration(hours: 4)),
      ),
      AuditEntry(
        id: const Uuid().v4(),
        user: 'admin',
        action: 'UPDATE',
        entity: 'Consignor',
        entityRef: 'LUMINAZ SAFETY GLASS',
        timestamp: now.subtract(const Duration(days: 1)),
        details: 'GST updated',
      ),
    ];
  }

  void log({
    required String user,
    required String action,
    required String entity,
    String? entityRef,
    String? details,
  }) {
    state = [
      AuditEntry(
        id: const Uuid().v4(),
        user: user,
        action: action,
        entity: entity,
        entityRef: entityRef,
        details: details,
        timestamp: DateTime.now(),
      ),
      ...state,
    ];
  }
}

final auditProvider =
    StateNotifierProvider<AuditNotifier, List<AuditEntry>>(
        (ref) => AuditNotifier());
