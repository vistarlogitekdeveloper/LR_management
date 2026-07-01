import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/lr_number_format.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/section_title.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/system_config_provider.dart';

class NumberingScreen extends ConsumerStatefulWidget {
  const NumberingScreen({super.key});

  @override
  ConsumerState<NumberingScreen> createState() => _NumberingScreenState();
}

class _NumberingScreenState extends ConsumerState<NumberingScreen> {
  late TextEditingController _prefixCtrl;
  late TextEditingController _formatCtrl;
  late TextEditingController _nextCtrl;

  // The config the controllers were last seeded from — lets us re-seed when the
  // backend row lands without clobbering edits the admin has already made.
  SystemConfig? _seeded;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(systemConfigProvider);
    _prefixCtrl = TextEditingController(text: cfg.lrPrefix);
    _formatCtrl = TextEditingController(text: cfg.lrFormat);
    _nextCtrl = TextEditingController(text: '${cfg.nextLrNumber}');
    _seeded = cfg;
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _formatCtrl.dispose();
    _nextCtrl.dispose();
    super.dispose();
  }

  /// The numbering row is fetched asynchronously (and is region-specific), so it
  /// can arrive after this screen is built. Sync the fields to it, but only
  /// overwrite prefix/format if the admin hasn't started editing them.
  void _onConfig(SystemConfig next) {
    if (!mounted) return;
    final untouched = _prefixCtrl.text == (_seeded?.lrPrefix ?? '') &&
        _formatCtrl.text == (_seeded?.lrFormat ?? '');
    setState(() {
      _nextCtrl.text = '${next.nextLrNumber}';
      if (untouched) {
        _prefixCtrl.text = next.lrPrefix;
        _formatCtrl.text = next.lrFormat;
      }
      _seeded = next;
    });
  }

  Future<void> _save() async {
    final cfg = ref.read(systemConfigProvider);
    final next = cfg.copyWith(
      lrPrefix: _prefixCtrl.text.trim(),
      lrFormat: _formatCtrl.text.trim(),
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(systemConfigProvider.notifier).saveNumbering(next);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('LR numbering updated')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  String _preview(SystemConfig cfg) {
    final seq = int.tryParse(_nextCtrl.text.trim()) ?? cfg.nextLrNumber;
    final template =
        _formatCtrl.text.trim().isEmpty ? cfg.lrFormat : _formatCtrl.text;
    return formatLrNumber(
      template,
      prefix: _prefixCtrl.text,
      region: cfg.lrRegionCode,
      seq: seq,
    );
  }

  String _resetLabel(String period) => switch (period) {
        'FINANCIAL_YEAR' => 'Resets every financial year (Apr–Mar)',
        'YEARLY' => 'Resets every calendar year',
        'MONTHLY' => 'Resets every month',
        'NEVER' => 'Never resets',
        _ => period,
      };

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(systemConfigProvider);
    ref.listen<SystemConfig>(systemConfigProvider, (_, next) => _onConfig(next));

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'LR Numbering',
            subtitle: 'Configure prefix, format & next sequence',
            actions: [
              AppButton(
                label: 'Save',
                icon: Icons.save_outlined,
                onPressed: _save,
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      icon: Icons.tag_rounded,
                      title: 'Numbering scheme',
                    ),
                    _regionBanner(cfg),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth >= 700 ? 3 : 1;
                        return Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final f in [
                              LabeledField(
                                label: 'Prefix',
                                required: true,
                                child: TextField(
                                  controller: _prefixCtrl,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Format',
                                child: TextField(
                                  controller: _formatCtrl,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              LabeledField(
                                label: 'Next number (managed by system)',
                                child: TextField(
                                  controller: _nextCtrl,
                                  readOnly: true,
                                  enabled: false,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ])
                              SizedBox(
                                width: (c.maxWidth - 14 * (cols - 1)) / cols,
                                child: f,
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tokens:  {prefix}   {REGION}   {FY}   {YY}   {MM}   {seq:05d}',
                      style: TextStyle(color: AppColors.slate, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.plum.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.preview_outlined,
                              color: AppColors.plum),
                          const SizedBox(width: 12),
                          const Text(
                            'Next LR will be:',
                            style: TextStyle(
                              color: AppColors.slate,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _preview(cfg),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.plum,
                                fontSize: 15,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows which numbering row is being edited — a specific region, or the
  /// tenant-wide fallback (super admins creating region-less LRs).
  Widget _regionBanner(SystemConfig cfg) {
    final hasRegion =
        (cfg.lrRegionId ?? '').isNotEmpty || cfg.lrRegionCode.isNotEmpty;
    final title = hasRegion
        ? [
            if (cfg.lrRegionCode.isNotEmpty) cfg.lrRegionCode,
            if (cfg.lrRegionName.isNotEmpty) cfg.lrRegionName,
          ].join(' · ')
        : 'Tenant-wide (no region)';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(hasRegion ? Icons.public_outlined : Icons.apartment_outlined,
              size: 18, color: AppColors.plum),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  _resetLabel(cfg.lrResetPeriod),
                  style: const TextStyle(color: AppColors.slate, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
