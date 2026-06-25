import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A form-field-styled selector that opens a searchable, alphabetically-sorted
/// picker dialog. A "smart search" drop-in replacement for
/// DropdownButtonFormField for any list where typing to filter helps — the
/// options are always shown A→Z and can be filtered by label (and optional
/// subtitle). Works the same on web and mobile.
class SearchableField<T> extends StatelessWidget {
  final T? value;
  final List<T> options;

  /// Primary text — shown in the field, used as the search key AND sort key.
  final String Function(T option) labelOf;

  /// Optional secondary line shown (and searched) in the picker — e.g. GST/city.
  final String Function(T option)? subtitleOf;

  final ValueChanged<T?> onChanged;
  final String hintText;
  final String? dialogTitle;

  /// When true the picker offers a "— None —" entry that clears the selection.
  final bool clearable;

  const SearchableField({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.subtitleOf,
    this.hintText = 'Select',
    this.dialogTitle,
    this.clearable = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final text = hasValue ? labelOf(value as T) : hintText;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final result = await showDialog<_PickResult<T>>(
          context: context,
          builder: (_) => _SearchPicker<T>(
            title: dialogTitle ?? hintText,
            options: options,
            labelOf: labelOf,
            subtitleOf: subtitleOf,
            clearable: clearable,
            current: value,
          ),
        );
        if (result != null) onChanged(result.value);
      },
      child: InputDecorator(
        isEmpty: !hasValue,
        decoration: const InputDecoration(
          suffixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.slate,
            size: 20,
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: hasValue ? AppColors.ink : AppColors.slate,
          ),
        ),
      ),
    );
  }
}

/// Distinguishes a real pick / clear (returns a result) from a dismissal (null).
class _PickResult<T> {
  final T? value;
  const _PickResult(this.value);
}

class _SearchPicker<T> extends StatefulWidget {
  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final bool clearable;
  final T? current;

  const _SearchPicker({
    required this.title,
    required this.options,
    required this.labelOf,
    required this.subtitleOf,
    required this.clearable,
    required this.current,
  });

  @override
  State<_SearchPicker<T>> createState() => _SearchPickerState<T>();
}

class _SearchPickerState<T> extends State<_SearchPicker<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // Always present alphabetically (case-insensitive) by the primary label.
    final sorted = [...widget.options]
      ..sort(
        (a, b) => widget
            .labelOf(a)
            .toLowerCase()
            .compareTo(widget.labelOf(b).toLowerCase()),
      );
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? sorted
        : sorted.where((o) {
            final l = widget.labelOf(o).toLowerCase();
            final s = widget.subtitleOf?.call(o).toLowerCase() ?? '';
            return l.contains(q) || s.contains(q);
          }).toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search, color: AppColors.slate),
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Flexible(
              child: filtered.isEmpty && !widget.clearable
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(color: AppColors.slate),
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        if (widget.clearable)
                          ListTile(
                            dense: true,
                            title: const Text(
                              '— None —',
                              style: TextStyle(
                                color: AppColors.slate,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            onTap: () =>
                                Navigator.pop(context, _PickResult<T>(null)),
                          ),
                        for (final o in filtered)
                          ListTile(
                            dense: true,
                            selected: o == widget.current,
                            selectedTileColor: AppColors.plum.withValues(
                              alpha: 0.06,
                            ),
                            title: Text(
                              widget.labelOf(o),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: widget.subtitleOf != null
                                ? Text(
                                    widget.subtitleOf!(o),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5),
                                  )
                                : null,
                            onTap: () =>
                                Navigator.pop(context, _PickResult<T>(o)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
