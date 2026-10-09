import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../data/fleet_filter.dart';
import '../data/tracking_repository.dart';
import '../providers/tracking_providers.dart';

/// Scope chips (with counts), region and search for the Active tab. Everything
/// filters the already-loaded fleet, so results land on the tap / keystroke.
class FleetFilters extends ConsumerWidget {
  /// Every trip the server listed, before filtering.
  final List<FleetVehicle> all;
  const FleetFilters({super.key, required this.all});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(fleetFilterProvider);
    final counts = fleetScopeCounts(all, filter.region);
    final regions = fleetRegions(all);

    return Container(
      color: AppColors.mist,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 700;
          final gutter = c.maxWidth < 600 ? 12.0 : 24.0;
          final search = _SearchField(compact: compact);
          final region = regions.length > 1
              ? _RegionField(regions: regions, value: filter.region)
              : null;

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) ...[
                  search,
                  if (region != null) ...[const SizedBox(height: 8), region],
                ] else
                  Row(
                    children: [
                      Expanded(flex: 6, child: search),
                      if (region != null) ...[
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: region),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in FleetScope.values)
                      ChoiceChip(
                        label: Text('${s.label} (${counts[s] ?? 0})'),
                        selected: filter.scope == s,
                        visualDensity: VisualDensity.compact,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: filter.scope == s
                              ? AppColors.white
                              : ((s == FleetScope.noSignal ||
                                            s == FleetScope.halted) &&
                                        (counts[s] ?? 0) > 0
                                    ? AppColors.danger
                                    : AppColors.ink),
                        ),
                        selectedColor: AppColors.plum,
                        backgroundColor: AppColors.white,
                        showCheckmark: false,
                        side: const BorderSide(color: AppColors.line),
                        onSelected: (_) => ref
                            .read(fleetFilterProvider.notifier)
                            .update((f) => f.copyWith(scope: s)),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RegionField extends ConsumerWidget {
  final List<String> regions;
  final String? value;
  const _RegionField({required this.regions, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SearchableField<String>(
      value: value,
      options: regions,
      labelOf: (r) => r,
      hintText: 'All regions',
      dialogTitle: 'Select region',
      clearable: true,
      onChanged: (v) => ref
          .read(fleetFilterProvider.notifier)
          .update(
            (f) => v == null
                ? f.copyWith(clearRegion: true)
                : f.copyWith(region: v),
          ),
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
    // Seeded from the provider: the filter outlives this widget.
    _controller = TextEditingController(
      text: ref.read(fleetFilterProvider).query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String v) => ref
      .read(fleetFilterProvider.notifier)
      .update((f) => f.copyWith(query: v));

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(fleetFilterProvider.select((f) => f.query));

    // The empty state's "Clear search" resets the query from outside the box.
    ref.listen<String>(fleetFilterProvider.select((f) => f.query), (_, next) {
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
            : 'Search LR, vehicle, driver, city…',
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
