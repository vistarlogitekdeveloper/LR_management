import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/lr_models.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../data/trip_history.dart';
import '../providers/tracking_providers.dart';

/// Search + period + outcome narrowing for the History tab, with a live result
/// count. Every control filters an already-loaded list, so results land on the
/// keystroke — no request, no debounce needed.
class TripHistoryFilters extends ConsumerWidget {
  const TripHistoryFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(tripHistoryFilterProvider);
    final count = ref.watch(tripHistoryProvider).valueOrNull?.length;

    return Container(
      color: AppColors.mist,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 700;
          final gutter = c.maxWidth < 600 ? 12.0 : 24.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: _FilterRow(compact: compact),
              ),
              if (count != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 0),
                  child: _ResultLine(
                    count: count,
                    filtered: !filter.isUnfiltered,
                    onClear: () =>
                        ref.read(tripHistoryFilterProvider.notifier).state =
                            const TripHistoryFilter(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The three controls. Stacked on narrow viewports so nothing is cramped; one
/// flexed row from 700 px up.
class _FilterRow extends StatelessWidget {
  final bool compact;
  const _FilterRow({required this.compact});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchField(compact: true),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _PeriodField()),
              SizedBox(width: 8),
              Expanded(child: _OutcomeField()),
            ],
          ),
        ],
      );
    }
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 6, child: _SearchField(compact: false)),
        SizedBox(width: 12),
        Expanded(flex: 3, child: _PeriodField()),
        SizedBox(width: 12),
        Expanded(flex: 3, child: _OutcomeField()),
      ],
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  final bool compact;
  const _SearchField({required this.compact});

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Seeded from the provider so the box still shows the query after the user
    // opens a trip and comes back — the filter outlives this widget.
    _controller = TextEditingController(
      text: ref.read(tripHistoryFilterProvider).query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String v) => ref
      .read(tripHistoryFilterProvider.notifier)
      .update((s) => s.copyWith(query: v));

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(tripHistoryFilterProvider.select((f) => f.query));

    // "Clear filters" is offered from the empty state too, so the text box has
    // to follow a reset it did not originate.
    ref.listen<String>(tripHistoryFilterProvider.select((f) => f.query), (
      _,
      next,
    ) {
      if (next != _controller.text) _controller.text = next;
    });

    return TextField(
      controller: _controller,
      style: TextStyle(
        fontSize: widget.compact ? 13 : 14,
        color: AppColors.ink,
      ),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: widget.compact,
        hintText: widget.compact
            ? 'Search…'
            : 'Search LR, vehicle, driver, city, party…',
        prefixIcon: const Icon(Icons.search, color: AppColors.slate),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _controller.clear();
                  _set('');
                },
              ),
      ),
      onChanged: _set,
    );
  }
}

class _PeriodField extends ConsumerWidget {
  const _PeriodField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(tripHistoryFilterProvider.select((f) => f.period));
    return SearchableField<TripPeriod>(
      // TripPeriod.all is the "no filter" state, so it reads as the hint rather
      // than a selected value.
      value: period == TripPeriod.all ? null : period,
      options: TripPeriod.values.where((p) => p != TripPeriod.all).toList(),
      labelOf: (p) => p.label,
      hintText: TripPeriod.all.label,
      dialogTitle: 'Select period',
      clearable: true,
      onChanged: (v) => ref
          .read(tripHistoryFilterProvider.notifier)
          .update((s) => s.copyWith(period: v ?? TripPeriod.all)),
    );
  }
}

class _OutcomeField extends ConsumerWidget {
  const _OutcomeField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(tripHistoryFilterProvider.select((f) => f.status));
    return SearchableField<LrStatus>(
      value: status,
      options: const [LrStatus.delivered, LrStatus.cancelled],
      labelOf: (s) => s.label,
      hintText: 'All outcomes',
      dialogTitle: 'Select outcome',
      clearable: true,
      onChanged: (v) => ref
          .read(tripHistoryFilterProvider.notifier)
          .update(
            (s) => v == null
                ? s.copyWith(clearStatus: true)
                : s.copyWith(status: v),
          ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  final int count;
  final bool filtered;
  final VoidCallback onClear;
  const _ResultLine({
    required this.count,
    required this.filtered,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            count == 1 ? '1 finished trip' : '$count finished trips',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.slate,
            ),
          ),
        ),
        if (filtered)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 15),
            label: const Text('Clear filters'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.plum,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
      ],
    );
  }
}
