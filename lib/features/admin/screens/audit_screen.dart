import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/models/audit_entry.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/audit_provider.dart';

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  static Color _actionColor(String action) => switch (action) {
    'CREATE' => AppColors.ok,
    'UPDATE' => AppColors.warn,
    'DELETE' => AppColors.danger,
    'LOGIN' => AppColors.plum,
    _ => AppColors.slate,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(auditProvider);
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Audit Trail',
            subtitle: entriesAsync.maybeWhen(
              data: (entries) => '${entries.length} events recorded',
              orElse: () => 'Loading events…',
            ),
          ),
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Failed to load audit trail: $e',
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
              data: (entries) => LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 640;
                  if (isMobile) {
                    // Compact mobile cards avoid wide-table overflow.
                    return ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _AuditCard(entry: entries[i]),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: AppCard(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(
                            AppColors.plum.withValues(alpha: 0.05),
                          ),
                          columnSpacing: 28,
                          columns: const [
                            DataColumn(label: Text('When')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('Action')),
                            DataColumn(label: Text('Entity')),
                            DataColumn(label: Text('Reference')),
                            DataColumn(label: Text('Details')),
                          ],
                          rows: [
                            for (final e in entries)
                              DataRow(
                                cells: [
                                  DataCell(Text(formatDateTime(e.timestamp))),
                                  DataCell(Text(e.user)),
                                  DataCell(_ActionBadge(action: e.action)),
                                  DataCell(Text(e.entity)),
                                  DataCell(Text(e.entityRef ?? '—')),
                                  DataCell(Text(e.details ?? '—')),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Compact single-entry card for mobile; replaces the wide DataTable.
class _AuditCard extends StatelessWidget {
  final AuditEntry entry;
  const _AuditCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ActionBadge(action: entry.action),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.entity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${entry.user} · ${formatDateTime(entry.timestamp)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.slate, fontSize: 12),
          ),
          if (entry.entityRef != null && entry.entityRef!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Ref: ${entry.entityRef}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.slate, fontSize: 12),
            ),
          ],
          if (entry.details != null && entry.details!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.details!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  final String action;
  const _ActionBadge({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = AuditScreen._actionColor(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        action,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
