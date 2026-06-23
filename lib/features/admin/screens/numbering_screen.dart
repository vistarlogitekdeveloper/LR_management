import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(systemConfigProvider);
    _prefixCtrl = TextEditingController(text: cfg.lrPrefix);
    _formatCtrl = TextEditingController(text: cfg.lrFormat);
    _nextCtrl = TextEditingController(text: '${cfg.nextLrNumber}');
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _formatCtrl.dispose();
    _nextCtrl.dispose();
    super.dispose();
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

  String _preview() {
    final now = DateTime.now();
    final num = (int.tryParse(_nextCtrl.text.trim()) ?? 1)
        .toString()
        .padLeft(5, '0');
    return '${_prefixCtrl.text}/${now.year.toString().substring(2)}/${now.month.toString().padLeft(2, '0')}/$num';
  }

  @override
  Widget build(BuildContext context) {
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
                          Text(
                            _preview(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.plum,
                              fontSize: 15,
                              letterSpacing: 0.4,
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
}
