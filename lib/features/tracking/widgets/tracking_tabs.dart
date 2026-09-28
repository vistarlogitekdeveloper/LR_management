import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../data/trip_history.dart';

/// Segmented switch between the live fleet map and finished-trip history.
///
/// Counts are optional: they are omitted while the underlying load is still in
/// flight rather than shown as a placeholder zero, which would read as "nothing
/// here" for the second or two before the real number lands.
class TrackingTabs extends StatelessWidget {
  final TrackingTab selected;
  final ValueChanged<TrackingTab> onChanged;
  final int? activeCount;
  final int? historyCount;

  const TrackingTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    this.activeCount,
    this.historyCount,
  });

  static const _icons = {
    TrackingTab.active: Icons.near_me_rounded,
    TrackingTab.history: Icons.history_rounded,
  };

  /// Ceiling on the pill's width when the parent imposes none, as a share of
  /// the viewport. AppTopbar lays its actions out in a plain Row above 900 px,
  /// which hands each action `maxWidth: Infinity` — so the pill would take its
  /// full natural width and, at large text scales, push the row into overflow.
  /// Anything past this scrolls instead. The remainder always leaves the title
  /// and Refresh room: at 900 px and textScaler 2.0 they need well under half.
  static const _maxShareOfViewport = 0.45;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).width;
    final compact = viewport < 600;
    // Sized by its own labels so it can sit among the header's actions, and
    // horizontally scrollable so a tight header row (360 px at textScaler 2.0)
    // scrolls the pill instead of striping it.
    return LayoutBuilder(
      builder: (context, c) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: c.maxWidth.isFinite
              ? c.maxWidth
              : viewport * _maxShareOfViewport,
        ),
        child: _TabPill(
          selected: selected,
          onChanged: onChanged,
          activeCount: activeCount,
          historyCount: historyCount,
          compact: compact,
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final TrackingTab selected;
  final ValueChanged<TrackingTab> onChanged;
  final int? activeCount;
  final int? historyCount;
  final bool compact;

  const _TabPill({
    required this.selected,
    required this.onChanged,
    required this.activeCount,
    required this.historyCount,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          // A mist track on the white topbar, so the unselected segment reads
          // as the groove the selected one sits in.
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tab in TrackingTab.values)
              _Segment(
                label: tab.label,
                icon: TrackingTabs._icons[tab]!,
                count: tab == TrackingTab.active ? activeCount : historyCount,
                selected: tab == selected,
                compact: compact,
                onTap: () {
                  if (tab == selected) return;
                  HapticFeedback.selectionClick();
                  onChanged(tab);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? count;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.slate;
    // Merged so a screen reader announces the tab as one control — its name,
    // its count and whether it is the one showing — instead of three fragments.
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
            decoration: BoxDecoration(
              color: selected ? AppColors.plum : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 7),
                  _CountBadge(count: count!, selected: selected),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final bool selected;
  const _CountBadge({required this.count, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.white.withValues(alpha: 0.22)
            : AppColors.line,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: selected ? AppColors.white : AppColors.slate,
        ),
      ),
    );
  }
}
