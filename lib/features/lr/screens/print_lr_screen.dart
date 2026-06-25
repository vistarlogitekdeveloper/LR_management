import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../admin/providers/system_config_provider.dart';
import '../../masters/widgets/master_actions.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';
import '../widgets/lr_slip_pdf.dart';

class PrintLrScreen extends ConsumerWidget {
  final String id;
  const PrintLrScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLr = ref.watch(lrDetailProvider(id));
    final cfg = ref.watch(systemConfigProvider);

    final company = LrSlipCompany(
      name: cfg.companyName,
      tagline: cfg.companyTagline,
      address: cfg.companyAddress,
      gstin: cfg.companyGstin,
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
      data: (lr) {
        Future<void> doPrint() async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await Printing.layoutPdf(
              name: 'LR_${lr.number}.pdf',
              onLayout: (format) =>
                  buildLrSlipPdf(lr: lr, company: company, pageFormat: format),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text(MasterActions.messageFor(e))),
            );
          }
        }

        return Scaffold(
          backgroundColor: AppColors.mist,
          body: Column(
            children: [
              AppTopbar(
                title: 'Print LR ${lr.number}',
                subtitle: 'Goods Consignment Note · 4 copies',
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
                    onPressed: doPrint,
                  ),
                ],
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) =>
                      buildLrSlipPdf(lr: lr, company: company, pageFormat: format),
                  useActions: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  scrollViewDecoration:
                      const BoxDecoration(color: AppColors.mist),
                  loadingWidget: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
