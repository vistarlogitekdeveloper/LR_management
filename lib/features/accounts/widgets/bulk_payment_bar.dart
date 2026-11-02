import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/app_button.dart';
import '../../lr/providers/lr_providers.dart';
import '../data/bulk_payment.dart';

/// The bar above the Accounts list: tick all in view, and pay every ticked LR
/// at once (bulk_payment.dart). Only the LRs in the current view count, so a
/// filter change never pays something the user can no longer see.
class BulkPaymentBar extends ConsumerWidget {
  final List<LorryReceipt> items;

  /// The user may see transporter amounts (VIEW_TRANSPORTER_RATE).
  final bool showAmounts;
  const BulkPaymentBar({
    super.key,
    required this.items,
    required this.showAmounts,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticked = ref.watch(accountsSelectionProvider);
    final selected = items.where((l) => ticked.contains(l.id)).toList();
    final all = items.isNotEmpty && selected.length == items.length;
    int count(BulkPayAction a) =>
        selected.where((l) => bulkEligible(l, a)).length;
    final advance = count(BulkPayAction.advance);
    final complete = count(BulkPayAction.complete);
    void setTicked(Set<String> s) =>
        ref.read(accountsSelectionProvider.notifier).state = s;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected.isEmpty
            ? AppColors.white
            : AppColors.plum.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected.isEmpty
              ? AppColors.line
              : AppColors.plum.withValues(alpha: 0.35),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: const ValueKey('bulk-select-all'),
                tristate: true,
                value: all ? true : (selected.isEmpty ? false : null),
                activeColor: AppColors.plum,
                onChanged: (_) => setTicked(
                  all ? <String>{} : {...ticked, for (final l in items) l.id},
                ),
              ),
              Text(
                selected.isEmpty
                    ? 'Select LRs to pay several at once'
                    : '${selected.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected.isEmpty ? AppColors.slate : AppColors.plum,
                ),
              ),
            ],
          ),
          if (selected.isNotEmpty) ...[
            AppButton(
              key: const ValueKey('bulk-advance'),
              label: '${BulkPayAction.advance.label} ($advance)',
              kind: BtnKind.soft,
              icon: Icons.savings_outlined,
              small: true,
              onPressed: advance == 0
                  ? null
                  : () => _run(context, ref, selected, BulkPayAction.advance),
            ),
            AppButton(
              key: const ValueKey('bulk-complete'),
              label: '${BulkPayAction.complete.label} ($complete)',
              kind: BtnKind.primary,
              icon: Icons.check_circle_outline,
              small: true,
              onPressed: complete == 0
                  ? null
                  : () => _run(context, ref, selected, BulkPayAction.complete),
            ),
            TextButton(
              onPressed: () => setTicked(<String>{}),
              child: const Text('Clear'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    List<LorryReceipt> selected,
    BulkPayAction action,
  ) async {
    final todo = selected.where((l) => bulkEligible(l, action)).toList();
    final total = todo.fold<double>(0, (s, l) => s + bulkAmount(l, action));
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              '${action.label} · ${todo.length} LR${todo.length == 1 ? '' : 's'}',
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAmounts)
                    Text(
                      'Total to release: ${inr(total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  if (selected.length > todo.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${selected.length - todo.length} selected LR(s) do not need this and will be skipped.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.slate,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final l in todo)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${l.number} · ${l.transporter.name.isEmpty ? '-' : l.transporter.name}'
                              '${showAmounts ? ' · ${inr(bulkAmount(l, action))}' : ''}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Each LR is paid one by one, exactly as with its own button, and '
                    'each sends its usual notification email.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('bulk-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Pay ${todo.length} & Notify'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    // The bar can leave the tree while the batch runs (the last LR of a
    // filtered view gets paid): work through the container, not this ref.
    final container = ProviderScope.containerOf(context, listen: false);

    final progress = ValueNotifier<(int, int)>((0, todo.length));
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
                const SizedBox(height: 12),
                Text(
                  'Paying ${p.$1 < p.$2 ? p.$1 + 1 : p.$2} of ${p.$2}… please keep this open.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final notifier = container.read(lrListProvider.notifier);
    final result = await runBulkPay(
      selected: todo,
      action: action,
      fresh: (lr) {
        for (final l in container.read(lrListProvider)) {
          if (l.id == lr.id) return l;
        }
        return lr;
      },
      pay: (lr) => action == BulkPayAction.advance
          ? notifier.markAdvancePaid(lr.id, lr.version)
          : notifier.completePayment(lr.id, lr.version),
      describe: friendlyErrorMessage,
      onProgress: (done, total) => progress.value = (done, total),
    );
    navigator.pop();
    progress.dispose();
    // Failures stay ticked for a retry; the rest are cleared.
    container.read(accountsSelectionProvider.notifier).state = {
      for (final f in result.failed) f.lr.id,
    };
    if (!navigator.mounted) return;
    await showDialog<void>(
      context: navigator.context,
      builder: (ctx) => AlertDialog(
        title: Text(
          result.failed.isEmpty
              ? 'Done'
              : 'Done, with ${result.failed.length} failed',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${action.done}: ${result.paid.length} LR${result.paid.length == 1 ? '' : 's'}.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ok,
                  ),
                ),
                if (result.skipped.isNotEmpty)
                  Text(
                    '${result.skipped.length} were already paid by someone else and were skipped.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.slate,
                    ),
                  ),
                for (final f in result.failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '✗ ${f.lr.number}: ${f.message}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                if (result.failed.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'The failed LRs are still selected — fix the reason and try again.',
                      style: TextStyle(fontSize: 12, color: AppColors.slate),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
