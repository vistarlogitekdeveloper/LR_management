import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/models/transporter.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/searchable_field.dart';
import '../../masters/providers/master_providers.dart';
import '../data/vehicle_bank_models.dart';
import '../providers/vehicle_bank_providers.dart';

/// How long the typing has to stop before a text filter is applied. Every
/// filter change refetches the whole directory, so a request per keystroke
/// would queue a dozen full scans for one search term.
const Duration _textDebounce = Duration(milliseconds: 300);

/// The Vehicle Bank filter bar: free text, region, route endpoints (from city
/// and to city as separate inputs), transporter, active state and a
/// document-expiry window.
///
/// The filter itself lives in [vehicleBankFilterProvider] rather than in this
/// widget, so it survives a navigation away and back and so the export button
/// in the top bar exports exactly what the table is showing.
class VehicleBankFilters extends ConsumerStatefulWidget {
  const VehicleBankFilters({super.key});

  @override
  ConsumerState<VehicleBankFilters> createState() => _VehicleBankFiltersState();
}

class _VehicleBankFiltersState extends ConsumerState<VehicleBankFilters> {
  final TextEditingController _q = TextEditingController();
  final TextEditingController _fromCity = TextEditingController();
  final TextEditingController _toCity = TextEditingController();
  Timer? _debounce;

  /// Every region seen in a result set so far, id to name.
  ///
  /// Deliberately built from the rows the server already returned instead of
  /// the admin region list: `/admin/regions` is gated on ADMIN_ACCESS and this
  /// directory is meant for users who do not hold it. Regions are remembered
  /// for the life of the screen because narrowing to one region shrinks the
  /// rows to that region — without the memo the picker you would use to switch
  /// to another region would empty itself the moment you used it.
  final Map<String, String> _regionsSeen = <String, String>{};

  @override
  void initState() {
    super.initState();
    // The filter outlives this widget (it is not autoDispose), so on a return
    // to the screen the boxes have to be re-seeded from it — otherwise they
    // would look empty while their terms were still being applied, and the
    // next pick would fold that emptiness back into the filter.
    final filter = ref.read(vehicleBankFilterProvider);
    _q.text = filter.q;
    _fromCity.text = filter.fromCity;
    _toCity.text = filter.toCity;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _fromCity.dispose();
    _toCity.dispose();
    super.dispose();
  }

  /// Writes [next] with whatever is currently typed folded in.
  ///
  /// Every control commits the text boxes as well, which is what stops a pick
  /// made mid-word from throwing that word away: the picker's callback carries
  /// the filter as it was at build time, so a still-debounced search term
  /// would otherwise be written back as empty and then mirrored onto the box.
  void _apply(VehicleBankFilter next) {
    _debounce?.cancel();
    ref.read(vehicleBankFilterProvider.notifier).state = next.copyWith(
      q: _q.text,
      fromCity: _fromCity.text,
      toCity: _toCity.text,
    );
  }

  /// Applies the three text boxes together once typing pauses.
  void _scheduleText() {
    _debounce?.cancel();
    _debounce = Timer(_textDebounce, () {
      if (!mounted) return;
      _apply(ref.read(vehicleBankFilterProvider));
    });
  }

  /// Pulls the boxes back in step when the filter is reset from somewhere else
  /// — the empty state's "Clear filters" — so they never keep showing a term
  /// that is no longer being applied. A value we just wrote ourselves compares
  /// equal and is skipped, which leaves the caret where the user put it.
  void _syncFromFilter(VehicleBankFilter filter) {
    var changed = false;
    if (_q.text != filter.q) {
      _q.text = filter.q;
      changed = true;
    }
    if (_fromCity.text != filter.fromCity) {
      _fromCity.text = filter.fromCity;
      changed = true;
    }
    if (_toCity.text != filter.toCity) {
      _toCity.text = filter.toCity;
      changed = true;
    }
    // An outside reset wins over a keystroke still sitting in the debounce,
    // which would otherwise put the cleared term straight back.
    if (changed) _debounce?.cancel();
  }

  void _clearAll() {
    _debounce?.cancel();
    _q.clear();
    _fromCity.clear();
    _toCity.clear();
    _apply(VehicleBankFilter.empty);
  }

  /// Merges the regions carried by the latest result set into [_regionsSeen]
  /// and returns it. Idempotent, so running it on every build is harmless.
  Map<String, String> _regionOptions(AsyncValue<List<VehicleBankRow>> rows) {
    if (rows case AsyncData(:final value)) {
      for (final row in value) {
        final id = row.regionId;
        if (id != null && row.regionName.isNotEmpty) {
          _regionsSeen[id] = row.regionName;
        }
      }
    }
    return _regionsSeen;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VehicleBankFilter>(
      vehicleBankFilterProvider,
      (_, next) => _syncFromFilter(next),
    );

    final filter = ref.watch(vehicleBankFilterProvider);
    final regions = _regionOptions(ref.watch(currentVehicleBankRowsProvider));
    final transporters = ref.watch(transportersProvider);
    final selectedTransporter = transporters
        .where((t) => t.id == filter.transporterId)
        .firstOrNull;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // One box over registration, transporter, driver and licence — the
          // server decides which of them matched.
          _FilterTextField(
            controller: _q,
            width: 280,
            hint: 'Search vehicle, driver…',
            icon: Icons.search_rounded,
            onChanged: (_) => _scheduleText(),
          ),
          // A single-region user (region-pinned, or a tenant with one region)
          // gets no picker: it could only ever offer what they already see.
          if (regions.length > 1)
            SizedBox(
              width: 170,
              child: SearchableField<String>(
                value: filter.regionId.isEmpty ? null : filter.regionId,
                // SearchableField sorts by label itself, so the ids go in
                // unordered.
                options: regions.keys.toList(),
                labelOf: (id) => regions[id] ?? id,
                hintText: 'All regions',
                dialogTitle: 'Region',
                clearable: true,
                onChanged: (v) => _apply(filter.copyWith(regionId: v ?? '')),
              ),
            ),
          _FilterTextField(
            controller: _fromCity,
            width: 150,
            hint: 'From city',
            icon: Icons.trip_origin_rounded,
            onChanged: (_) => _scheduleText(),
          ),
          _FilterTextField(
            controller: _toCity,
            width: 150,
            hint: 'To city',
            icon: Icons.place_outlined,
            onChanged: (_) => _scheduleText(),
          ),
          if (transporters.isNotEmpty)
            SizedBox(
              width: 200,
              child: SearchableField<Transporter>(
                value: selectedTransporter,
                options: transporters,
                labelOf: (t) => t.name,
                subtitleOf: (t) => t.mobile,
                hintText: 'All transporters',
                dialogTitle: 'Transporter',
                clearable: true,
                onChanged: (t) =>
                    _apply(filter.copyWith(transporterId: t?.id ?? '')),
              ),
            ),
          _ActiveToggle(
            value: filter.active,
            // clearActive is the only way back to "both": passing null to
            // copyWith means "leave unchanged", not "clear".
            onChanged: (v) => _apply(
              v == null
                  ? filter.copyWith(clearActive: true)
                  : filter.copyWith(active: v),
            ),
          ),
          _ExpiryChip(
            days: filter.expiringWithinDays,
            onChanged: (v) => _apply(
              v == null
                  ? filter.copyWith(clearExpiringWithinDays: true)
                  : filter.copyWith(expiringWithinDays: v),
            ),
          ),
          if (filter.hasFilters)
            AppButton(
              label: 'Clear (${filter.activeFilterCount})',
              icon: Icons.filter_alt_off_outlined,
              kind: BtnKind.ghost,
              small: true,
              onPressed: _clearAll,
            ),
        ],
      ),
    );
  }
}

/// A filter text box with a clear affordance that appears once something is
/// typed. Rebuilt from the controller rather than from screen state so a
/// keystroke repaints this one field, not the whole bar.
class _FilterTextField extends StatelessWidget {
  const _FilterTextField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.width,
    this.icon,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final prefix = icon;
    return SizedBox(
      width: width,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            prefixIcon: prefix == null
                ? null
                : Icon(prefix, size: 18, color: AppColors.slate),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.slate,
                    ),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Three-way active filter: both, active only, inactive only. Null is "both",
/// which is also the server's default when the parameter is absent.
class _ActiveToggle extends StatelessWidget {
  const _ActiveToggle({required this.value, required this.onChanged});

  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActiveSegment(
            label: 'All',
            selected: value == null,
            onTap: () => onChanged(null),
          ),
          _ActiveSegment(
            label: 'Active',
            selected: value == true,
            onTap: () => onChanged(true),
          ),
          _ActiveSegment(
            label: 'Inactive',
            selected: value == false,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ActiveSegment extends StatelessWidget {
  const _ActiveSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.plum.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.plum : AppColors.slate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Papers expiring within N days" — the question this directory exists to
/// answer. 0 days means already expired.
class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({required this.days, required this.onChanged});

  final int? days;
  final ValueChanged<int?> onChanged;

  /// Menu entries, days to label. A PopupMenuButton treats a null selection as
  /// a dismissal, so "no filter" travels as [_clearValue] and is translated
  /// back to null before it reaches the caller.
  static const int _clearValue = -1;
  static const Map<int, String> _options = {
    0: 'Already expired',
    15: 'Within 15 days',
    30: 'Within 30 days',
    60: 'Within 60 days',
    90: 'Within 90 days',
  };

  @override
  Widget build(BuildContext context) {
    final selected = days;
    final label = selected == null
        ? 'Any expiry'
        : (_options[selected] ?? 'Within $selected days');
    final on = selected != null;
    return PopupMenuButton<int>(
      tooltip: 'Filter by document expiry',
      position: PopupMenuPosition.under,
      onSelected: (v) => onChanged(v == _clearValue ? null : v),
      itemBuilder: (context) => [
        for (final entry in _options.entries)
          PopupMenuItem<int>(
            value: entry.key,
            child: Text(
              entry.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: entry.key == selected
                    ? FontWeight.w800
                    : FontWeight.w600,
                color: entry.key == selected ? AppColors.plum : AppColors.ink,
              ),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<int>(
          value: _clearValue,
          child: Text(
            'Any expiry',
            style: TextStyle(fontSize: 13, color: AppColors.slate),
          ),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on
              ? AppColors.warn.withValues(alpha: 0.10)
              : AppColors.inputBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? AppColors.warn.withValues(alpha: 0.45) : AppColors.line,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 16,
              color: on ? AppColors.warn : AppColors.slate,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                color: on ? AppColors.warn : AppColors.slate,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: on ? AppColors.warn : AppColors.slate,
            ),
          ],
        ),
      ),
    );
  }
}
