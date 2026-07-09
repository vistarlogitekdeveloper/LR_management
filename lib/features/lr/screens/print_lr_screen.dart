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

class PrintLrScreen extends ConsumerStatefulWidget {
  final String id;
  const PrintLrScreen({super.key, required this.id});

  @override
  ConsumerState<PrintLrScreen> createState() => _PrintLrScreenState();
}

class _PrintLrScreenState extends ConsumerState<PrintLrScreen> {
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final asyncLr = ref.watch(lrDetailProvider(widget.id));
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
        // An LR can only be printed once it has been sent for payment (which
        // notifies the accounts team). Guards against a direct /print deep-link
        // before the Print action is unlocked on the list/detail screens.
        if (!lr.sentForPayment) {
          return Scaffold(
            backgroundColor: AppColors.mist,
            body: Column(
              children: [
                AppTopbar(
                  title: 'Print LR ${lr.number}',
                  subtitle: 'Goods Consignment Note',
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_clock_outlined,
                          size: 40,
                          color: AppColors.slate,
                        ),
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'This LR can be printed only after it is sent for '
                            'payment, which notifies the accounts team.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.slate),
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Back to LR',
                          icon: Icons.arrow_back_rounded,
                          onPressed: () => context.go('/lrs/${lr.id}'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        Future<void> doPrint() async {
          if (_printing) return;
          setState(() => _printing = true);
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
          } finally {
            if (mounted) setState(() => _printing = false);
          }
        }

        return Scaffold(
          backgroundColor: AppColors.mist,
          body: Column(
            children: [
              AppTopbar(
                title: 'Print LR ${lr.number}',
                subtitle: 'Goods Consignment Note',
                actions: [
                  AppButton(
                    label: 'Back',
                    kind: BtnKind.ghost,
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => context.go('/lrs/${lr.id}'),
                  ),
                  AppButton(
                    label: _printing ? 'Preparing…' : 'Print',
                    icon: Icons.print_outlined,
                    loading: _printing,
                    onPressed: doPrint,
                  ),
                ],
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) => buildLrSlipPdf(
                    lr: lr,
                    company: company,
                    pageFormat: format,
                  ),
                  useActions: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  scrollViewDecoration: const BoxDecoration(
                    color: AppColors.mist,
                  ),
                  loadingWidget: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
