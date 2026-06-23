import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_card.dart';
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
              data: (entries) => SingleChildScrollView(
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
                          DataRow(cells: [
                            DataCell(Text(formatDateTime(e.timestamp))),
                            DataCell(Text(e.user)),
                            DataCell(_ActionBadge(action: e.action)),
                            DataCell(Text(e.entity)),
                            DataCell(Text(e.entityRef ?? '—')),
                            DataCell(Text(e.details ?? '—')),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
