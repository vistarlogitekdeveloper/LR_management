import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Optional "create one from here" hook. When given, the picker shows an
  /// "Add new …" entry above the options; tapping it closes the picker and
  /// calls this with whatever was typed in the search box (so the create form
  /// can pre-fill the name). Return the created option to select it on the
  /// field, or null if the user backed out. Left null — e.g. when the signed-in
  /// user lacks that master's manage permission — no add entry is shown.
  final Future<T?> Function(String query)? onAddNew;

  /// Label for the add entry, e.g. 'Add new vehicle'.
  final String addNewLabel;

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
    this.onAddNew,
    this.addNewLabel = 'Add new',
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
            addNewLabel: onAddNew == null ? null : addNewLabel,
          ),
        );
        if (result == null) return; // dismissed
        if (result.addNew) {
          final created = await onAddNew!(result.query);
          if (created != null) onChanged(created);
          return;
        }
        onChanged(result.value);
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

  /// True when the user tapped the "Add new …" entry instead of picking.
  final bool addNew;

  /// The search text at that moment — a head start for the create form.
  final String query;

  const _PickResult(this.value) : addNew = false, query = '';
  const _PickResult.addNew(this.query) : value = null, addNew = true;
}

class _SearchPicker<T> extends StatefulWidget {
  final String title;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final bool clearable;
  final T? current;

  /// Null when the caller passed no onAddNew (or the user may not create one).
  final String? addNewLabel;

  const _SearchPicker({
    required this.title,
    required this.options,
    required this.labelOf,
    required this.subtitleOf,
    required this.clearable,
    required this.current,
    required this.addNewLabel,
  });

  @override
  State<_SearchPicker<T>> createState() => _SearchPickerState<T>();
}

/// One row of the picker: the "Add new …" entry, "— None —", or an option.
enum _EntryKind { addNew, none, option }

class _Entry<T> {
  final _EntryKind kind;
  final T? value;
  const _Entry(this.kind, [this.value]);
}

class _SearchPickerState<T> extends State<_SearchPicker<T>> {
  String _q = '';

  /// Row picked with the arrow keys; null = the default row ([_defaultIndex]).
  /// Reset whenever the search text changes.
  int? _highlight;

  /// One key per row, so the highlighted row can be scrolled into view.
  final List<GlobalKey> _rowKeys = [];

  /// The secondary line, or null when there is nothing to say.
  ///
  /// An empty string is treated as absent rather than rendered: subtitleOf is
  /// usually built from optional fields (a party with no GST or city, a route
  /// with no vehicle type), and a blank Text still claims a line, leaving one
  /// tile taller than its neighbours for no reason.
  Widget? _subtitle(T option) {
    final value = widget.subtitleOf?.call(option).trim() ?? '';
    if (value.isEmpty) return null;
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11.5),
    );
  }

  List<T> _filtered() {
    // Always present alphabetically (case-insensitive) by the primary label.
    final sorted = [...widget.options]
      ..sort(
        (a, b) => widget
            .labelOf(a)
            .toLowerCase()
            .compareTo(widget.labelOf(b).toLowerCase()),
      );
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return sorted;
    return sorted.where((o) {
      final l = widget.labelOf(o).toLowerCase();
      final s = widget.subtitleOf?.call(o).toLowerCase() ?? '';
      return l.contains(q) || s.contains(q);
    }).toList();
  }

  List<_Entry<T>> _entries(List<T> filtered) => [
    if (widget.addNewLabel != null) _Entry<T>(_EntryKind.addNew),
    if (widget.clearable) _Entry<T>(_EntryKind.none),
    for (final o in filtered) _Entry<T>(_EntryKind.option, o),
  ];

  /// The row Enter picks before any arrow key is pressed: the current value
  /// (with no search typed), else the first match, else "Add new" — so typing
  /// a few letters and pressing Enter picks the top match, and Enter on a
  /// search with no match opens the add form with that text.
  int _defaultIndex(List<_Entry<T>> entries) {
    if (entries.isEmpty) return -1;
    if (_q.trim().isEmpty && widget.current != null) {
      final i = entries.indexWhere(
        (e) => e.kind == _EntryKind.option && e.value == widget.current,
      );
      if (i >= 0) return i;
    }
    final firstOption = entries.indexWhere((e) => e.kind == _EntryKind.option);
    if (firstOption >= 0) return firstOption;
    return 0;
  }

  int _active(List<_Entry<T>> entries) {
    final h = _highlight;
    if (h != null && h >= 0 && h < entries.length) return h;
    return _defaultIndex(entries);
  }

  void _move(int delta) {
    final entries = _entries(_filtered());
    if (entries.isEmpty) return;
    final next = (_active(entries) + delta).clamp(0, entries.length - 1);
    setState(() => _highlight = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next >= _rowKeys.length) return;
      final ctx = _rowKeys[next].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 90),
        alignmentPolicy: delta > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  void _pick(_Entry<T> e) {
    switch (e.kind) {
      case _EntryKind.addNew:
        Navigator.pop(context, _PickResult<T>.addNew(_q.trim()));
      case _EntryKind.none:
        Navigator.pop(context, _PickResult<T>(null));
      case _EntryKind.option:
        Navigator.pop(context, _PickResult<T>(e.value));
    }
  }

  void _pickActive() {
    final entries = _entries(_filtered());
    final i = _active(entries);
    if (i >= 0) _pick(entries[i]);
  }

  Widget _row(_Entry<T> e, {required bool active}) {
    final highlight = AppColors.plum.withValues(alpha: 0.10);
    switch (e.kind) {
      case _EntryKind.addNew:
        final addLabel = widget.addNewLabel!;
        return ListTile(
          dense: true,
          tileColor: active ? highlight : null,
          leading: const Icon(
            Icons.add_circle_outline,
            size: 20,
            color: AppColors.plum,
          ),
          title: Text(
            _q.trim().isEmpty ? addLabel : '$addLabel "${_q.trim()}"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.plum,
              fontWeight: FontWeight.w800,
            ),
          ),
          onTap: () => _pick(e),
        );
      case _EntryKind.none:
        return ListTile(
          dense: true,
          tileColor: active ? highlight : null,
          title: const Text(
            '— None —',
            style: TextStyle(
              color: AppColors.slate,
              fontStyle: FontStyle.italic,
            ),
          ),
          onTap: () => _pick(e),
        );
      case _EntryKind.option:
        final o = e.value as T;
        return ListTile(
          dense: true,
          selected: o == widget.current,
          tileColor: active ? highlight : null,
          selectedTileColor: active
              ? highlight
              : AppColors.plum.withValues(alpha: 0.06),
          title: Text(
            widget.labelOf(o),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: _subtitle(o),
          onTap: () => _pick(e),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    final entries = _entries(filtered);
    final active = _active(entries);
    while (_rowKeys.length < entries.length) {
      _rowKeys.add(GlobalKey());
    }
    final addLabel = widget.addNewLabel;

    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      rows.add(
        KeyedSubtree(
          key: _rowKeys[i],
          child: _row(e, active: i == active),
        ),
      );
      // "Add new" sits above the options (and stays visible when nothing
      // matches, which is exactly when it's needed) — the typed text rides
      // along to the form.
      if (e.kind == _EntryKind.addNew) {
        rows.add(const Divider(height: 1, color: AppColors.line));
        if (filtered.isEmpty) {
          rows.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Text(
                'No matches',
                style: TextStyle(color: AppColors.slate),
              ),
            ),
          );
        }
      }
    }

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
                  // Keyboard: type to filter, Up / Down to move, Enter to
                  // pick, Esc to close (the dialog's own). Focus stays in the
                  // search box the whole time.
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                          _move(1),
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                          _move(-1),
                      const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                          _move(8),
                      const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                          _move(-8),
                    },
                    child: TextField(
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search…',
                        prefixIcon: Icon(Icons.search, color: AppColors.slate),
                      ),
                      onChanged: (v) => setState(() {
                        _q = v;
                        _highlight = null;
                      }),
                      onSubmitted: (_) => _pickActive(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Flexible(
              child: filtered.isEmpty && !widget.clearable && addLabel == null
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
                      children: rows,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
