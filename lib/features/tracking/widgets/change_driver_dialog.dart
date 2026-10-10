import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/driver.dart';
import '../../masters/providers/master_providers.dart';
import '../data/driver_change.dart';
import '../data/driver_change_rules.dart';
import '../providers/tracking_providers.dart';
import 'change_driver_effects.dart';

/// Change the driver of a running trip: pick the new driver, add a note, and
/// the server switches the LR and moves tracking to the new phone. Returns the
/// result, or null when cancelled.
Future<DriverChangeResult?> showChangeDriverDialog(
  BuildContext context, {
  required String lrId,
  required String? currentDriverId,
  required String? currentDriverName,
}) {
  return showDialog<DriverChangeResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChangeDriverDialog(
      lrId: lrId,
      currentDriverId: currentDriverId,
      currentDriverName: currentDriverName,
    ),
  );
}

class _ChangeDriverDialog extends ConsumerStatefulWidget {
  final String lrId;
  final String? currentDriverId;
  final String? currentDriverName;
  const _ChangeDriverDialog({
    required this.lrId,
    required this.currentDriverId,
    required this.currentDriverName,
  });

  @override
  ConsumerState<_ChangeDriverDialog> createState() =>
      _ChangeDriverDialogState();
}

class _ChangeDriverDialogState extends ConsumerState<_ChangeDriverDialog> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  Driver? _picked;
  bool _loadingDrivers = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The drivers master loads with its own screen; reaching here straight
    // from Live Tracking it may not have been fetched yet.
    if (ref.read(driversProvider).isEmpty) {
      _loadingDrivers = true;
      ref.read(driversProvider.notifier).refresh().whenComplete(() {
        if (mounted) setState(() => _loadingDrivers = false);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final d = _picked;
    if (d == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(trackingRepositoryProvider)
          .changeDriver(widget.lrId, driverId: d.id, note: _note.text);
      if (!mounted) return;
      Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = changeDriverCandidates(
      ref.watch(driversProvider),
      currentDriverId: widget.currentDriverId,
      query: _search.text,
    );
    final from = (widget.currentDriverName ?? '').isEmpty
        ? 'the current driver'
        : widget.currentDriverName!;
    return AlertDialog(
      icon: const Icon(
        Icons.swap_horiz_rounded,
        color: AppColors.plum,
        size: 30,
      ),
      title: const Text('Change driver'),
      // A short window (a laptop at 700 px) must still reach the buttons, so
      // the content scrolls inside the fixed width. Not AlertDialog.scrollable:
      // that measures the content intrinsically, which the lazy driver list
      // cannot answer (it asserts in debug builds).
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The driver of this trip changed on the way? Pick who drives now. '
                'Currently: $from.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.slate,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  hintText: 'Search name, mobile or licence',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _DriverList(
                loading: _loadingDrivers && candidates.isEmpty,
                drivers: candidates,
                picked: _picked,
                enabled: !_saving,
                onPick: (d) => setState(() {
                  _picked = d;
                  _error = null;
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                enabled: !_saving,
                maxLength: 500,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Driver changed at Khalghat after his shift',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_picked != null)
                ChangeDriverEffects(from: from, to: _picked!.name),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _picked == null || _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_saving ? 'Changing…' : 'Change driver'),
        ),
      ],
    );
  }
}

/// The candidates, each a tap target; untrackable ones shown but disabled with
/// the reason, so a missing driver is explained rather than just absent.
class _DriverList extends StatelessWidget {
  final bool loading;
  final List<Driver> drivers;
  final Driver? picked;
  final bool enabled;
  final ValueChanged<Driver> onPick;
  const _DriverList({
    required this.loading,
    required this.drivers,
    required this.picked,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (drivers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No matching driver. Add the new driver in Masters → Drivers first.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.slate, fontSize: 12.5),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: drivers.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.line),
        itemBuilder: (_, i) {
          final d = drivers[i];
          final blocker = changeDriverBlocker(d);
          final selected = picked?.id == d.id;
          return ListTile(
            dense: true,
            enabled: enabled && blocker == null,
            selected: selected,
            selectedTileColor: AppColors.plum.withValues(alpha: 0.08),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.plum.withValues(alpha: 0.12),
              child: Text(
                d.name.isEmpty ? '?' : d.name[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.plum,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              d.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              blocker ?? d.mobile,
              style: TextStyle(
                color: blocker == null ? AppColors.slate : AppColors.danger,
              ),
            ),
            trailing: selected
                ? const Icon(Icons.check_circle_rounded, color: AppColors.plum)
                : null,
            onTap: () => onPick(d),
          );
        },
      ),
    );
  }
}
