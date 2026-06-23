import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/audit_entry.dart';
import '../../auth/providers/auth_provider.dart';
import 'users_provider.dart';

/// Read-only audit trail sourced from the backend `audit_logs` table. Every
/// mutating API call is recorded server-side, so the client no longer logs
/// entries itself — it just reads them here.
final auditProvider = FutureProvider<List<AuditEntry>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(adminRepositoryProvider).listAudit();
});
