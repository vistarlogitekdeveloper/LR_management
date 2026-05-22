import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/system_config_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(systemConfigProvider);
    final notifier = ref.read(systemConfigProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(
            title: 'System Settings',
            subtitle: 'Backup · Security · Policies',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.backup_outlined,
                          title: 'Backup',
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: cfg.dailyBackup,
                          onChanged: (v) => notifier
                              .update(cfg.copyWith(dailyBackup: v)),
                          title: const Text('Daily backup',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          subtitle: Text('Scheduled at ${cfg.backupTime}',
                              style: const TextStyle(color: AppColors.slate)),
                          activeThumbColor: AppColors.plum,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          icon: Icons.shield_outlined,
                          title: 'Security',
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: cfg.auditTrail,
                          onChanged: (v) => notifier
                              .update(cfg.copyWith(auditTrail: v)),
                          title: const Text('Audit trail',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          subtitle: const Text(
                              'Log all create / update / delete events',
                              style: TextStyle(color: AppColors.slate)),
                          activeThumbColor: AppColors.plum,
                        ),
                        const Divider(),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Password policy',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              Text(
                                cfg.passwordPolicy,
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SectionTitle(
                          icon: Icons.dns_outlined,
                          title: 'Environment',
                        ),
                        _ConfigRow(
                            label: 'App version', value: '1.0.0'),
                        _ConfigRow(
                            label: 'Database',
                            value: 'In-memory (mock) · swap to MySQL/PostgreSQL'),
                        _ConfigRow(
                            label: 'Hosting target',
                            value: 'Web · Windows · Android'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final String label;
  final String value;
  const _ConfigRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
