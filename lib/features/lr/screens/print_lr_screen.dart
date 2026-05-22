import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../shell/widgets/app_topbar.dart';
import '../providers/lr_providers.dart';
import '../widgets/lr_copy_view.dart';

class PrintLrScreen extends ConsumerWidget {
  final String id;
  const PrintLrScreen({super.key, required this.id});

  static const _copies = ['Consignor Copy', 'Consignee Copy', 'Lorry Copy', 'Office Copy'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lr = ref.watch(lrByIdProvider(id));
    if (lr == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('LR not found'),
              const SizedBox(height: 12),
              AppButton(
                label: 'Back',
                onPressed: () => context.go('/lrs'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
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
                      content:
                          Text('Use browser/system print or wire to PDF engine'),
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
                      LrCopyView(lr: lr, copyName: copyName),
                      const SizedBox(height: 20),
                    ],
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
