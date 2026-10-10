import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/tracking_repository.dart';
import '../providers/tracking_providers.dart';

/// "Halted 12 h at Nashik since 08 Oct, 9:40 PM"
String haltSummary(TripHalt h) {
  final where = (h.city ?? '').isNotEmpty ? ' at ${h.city}' : '';
  final since = h.startedAt != null
      ? ' since ${formatDateTime(h.startedAt!)}'
      : '';
  return 'Halted ${h.durationLabel}$where$since';
}

/// The red line on a Live Tracking card, with Acknowledge while it stands.
class HaltLine extends ConsumerWidget {
  final String lrId;
  final TripHalt halt;
  const HaltLine({super.key, required this.lrId, required this.halt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = halt.overAlertLimit;
    final color = alert ? AppColors.danger : AppColors.warn;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.pause_circle_filled_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              halt.acknowledged
                  ? '${haltSummary(halt)} · ${halt.ackReason?.label ?? 'acknowledged'}'
                  : haltSummary(halt),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (alert && !halt.acknowledged)
            TextButton(
              onPressed: () => showAcknowledgeHaltDialog(
                context,
                ref,
                lrId: lrId,
                halt: halt,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Acknowledge'),
            ),
        ],
      ),
    );
  }
}

/// Asks why the truck stood, then records it. Returns true when acknowledged.
Future<bool> showAcknowledgeHaltDialog(
  BuildContext context,
  WidgetRef ref, {
  required String lrId,
  required TripHalt halt,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _AckDialog(lrId: lrId, halt: halt),
  );
  if (done == true) {
    ref.invalidate(activeVehiclesProvider);
    ref.invalidate(lrTrackingProvider(lrId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Halt acknowledged — no reminder will be sent.'),
        ),
      );
    }
  }
  return done == true;
}

class _AckDialog extends ConsumerStatefulWidget {
  final String lrId;
  final TripHalt halt;
  const _AckDialog({required this.lrId, required this.halt});

  @override
  ConsumerState<_AckDialog> createState() => _AckDialogState();
}

class _AckDialogState extends ConsumerState<_AckDialog> {
  HaltReason? _reason;
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Pick why the vehicle is halted.');
      return;
    }
    if (reason == HaltReason.other && _note.text.trim().isEmpty) {
      setState(() => _error = 'Add a note for "Other".');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(trackingRepositoryProvider)
          .acknowledgeHalt(
            widget.lrId,
            widget.halt.id,
            reason: reason,
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Acknowledge halt'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              haltSummary(widget.halt),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
            if ((widget.halt.address ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.halt.address!,
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              'Why is the vehicle halted?',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in HaltReasonX.pickable)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _reason == r,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_saving,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText:
                    'e.g. spoke to the driver, tyre change, moving by 6 PM',
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        AppButton(
          label: 'Acknowledge',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

/// The LR tracking screen's banner while the truck is halted.
class HaltBanner extends ConsumerWidget {
  final String lrId;
  final TripHalt halt;

  /// Offered when the stop may be a driver handover: changing the driver
  /// closes the halt as "Driver changed" and moves tracking to the new phone,
  /// which acknowledging it does not. Null hides it.
  final VoidCallback? onChangeDriver;
  const HaltBanner({
    super.key,
    required this.lrId,
    required this.halt,
    this.onChangeDriver,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = halt.overAlertLimit;
    final color = alert ? AppColors.danger : AppColors.warn;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_filled_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  haltSummary(halt),
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  halt.acknowledged
                      ? 'Acknowledged: ${halt.ackReason?.label ?? '—'}'
                            '${(halt.ackNote ?? '').isNotEmpty ? ' — ${halt.ackNote}' : ''}'
                      : alert
                      ? 'Alert sent to the LR creator and admins. Reach the '
                            'driver, then acknowledge with the reason.'
                      : 'Alerted at $haltAlertHours h if the vehicle does not move.',
                  style: const TextStyle(fontSize: 12, color: AppColors.slate),
                ),
                if (onChangeDriver != null)
                  TextButton.icon(
                    onPressed: onChangeDriver,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Driver changed? Change driver'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.plum,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!halt.acknowledged && alert)
            AppButton(
              label: 'Acknowledge',
              small: true,
              onPressed: () => showAcknowledgeHaltDialog(
                context,
                ref,
                lrId: lrId,
                halt: halt,
              ),
            ),
        ],
      ),
    );
  }
}

/// Every halt of the trip, newest first.
class HaltHistory extends StatelessWidget {
  final List<TripHalt> halts;
  const HaltHistory({super.key, required this.halts});

  @override
  Widget build(BuildContext context) {
    if (halts.isEmpty) {
      return const Text(
        'No halts of 2 h or more on this trip.',
        style: TextStyle(fontSize: 12.5, color: AppColors.slate),
      );
    }
    return Column(
      children: [
        for (final h in halts.reversed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              h.ongoing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.pause_circle_outline_rounded,
              color: h.overAlertLimit ? AppColors.danger : AppColors.slate,
            ),
            title: Text(
              '${h.durationLabel}${(h.city ?? '').isNotEmpty ? ' at ${h.city}' : ''}'
              '${h.ongoing ? ' · now' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if (h.startedAt != null) formatDateTime(h.startedAt!),
                if (h.ackReason != null) h.ackReason!.label,
                if ((h.ackNote ?? '').isNotEmpty) h.ackNote!,
              ].join(' · '),
            ),
          ),
      ],
    );
  }
}
