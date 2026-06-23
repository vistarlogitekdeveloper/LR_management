import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../admin/providers/system_config_provider.dart';
import '../../masters/widgets/master_actions.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';
import '../widgets/lr_copy_view.dart';

class PrintLrScreen extends ConsumerWidget {
  final String id;
  const PrintLrScreen({super.key, required this.id});

  static const _copies = [
    'Consignor Copy',
    'Consignee Copy',
    'Lorry Copy',
    'Office Copy'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLr = ref.watch(lrDetailProvider(id));
    final cfg = ref.watch(systemConfigProvider);

    final format = LrCopyFormat(
      companyName: cfg.companyName,
      tagline: cfg.companyTagline,
      terms: cfg.termsText,
      footer: cfg.footerText,
      showEwb: cfg.showEwb,
      showInsurance: cfg.showInsurance,
      showMathadi: cfg.showMathadi,
      showVistarMargin: cfg.showVistarMargin,
    );

    return asyncLr.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.mist,
        body: Column(
          children: [
            AppTopbar(title: 'Print LR'),
            Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.mist,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(MasterActions.messageFor(e)),
              const SizedBox(height: 12),
              AppButton(label: 'Back', onPressed: () => context.go('/lrs')),
            ],
          ),
        ),
      ),
      data: (lr) => Scaffold(
        backgroundColor: AppColors.mist,
        body: Column(
          children: [
            AppTopbar(
              title: 'Print LR ${lr.number}',
              subtitle: '4 copies will be generated',
              actions: [
                AppButton(
                  label: 'Back',
                  kind: BtnKind.ghost,
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => context.go('/lrs/${lr.id}'),
                ),
                AppButton(
                  label: 'Print',
                  icon: Icons.print_outlined,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Use your browser/system print dialog to print these copies'),
                      ),
                    );
                  },
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Column(
                    children: [
                      for (final copyName in _copies) ...[
                        LrCopyView(
                            lr: lr, copyName: copyName, format: format),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
