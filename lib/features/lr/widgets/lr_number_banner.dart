import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/lr_providers.dart';
import '../utils/manual_lr_entry.dart';
import '../utils/manual_lr_number.dart';
import 'manual_lr_status_line.dart';

/// The LR number at the top of the form. Editing: the LR's number. Creating:
/// the automatic preview, or — after "Enter manually" — a field for a number
/// starting with LR/Manual/, checked against the server as it is typed.
/// [onManualChanged] reports the entry (null = automatic).
class LrNumberBanner extends ConsumerStatefulWidget {
  final bool isEdit;
  final String number;
  final ValueChanged<ManualLrEntry?> onManualChanged;

  /// Bump to check the manual number again (the save found it taken).
  final int recheck;

  const LrNumberBanner({
    super.key,
    required this.isEdit,
    required this.number,
    required this.onManualChanged,
    this.recheck = 0,
  });

  @override
  ConsumerState<LrNumberBanner> createState() => _LrNumberBannerState();
}

class _LrNumberBannerState extends ConsumerState<LrNumberBanner> {
  final _rest = TextEditingController();
  final _focus = FocusNode();
  bool _manual = false;
  ManualLrEntry? _entry;
  Timer? _debounce;
  int _seq = 0;

  @override
  void didUpdateWidget(covariant LrNumberBanner old) {
    super.didUpdateWidget(old);
    if (_manual && widget.recheck != old.recheck) {
      // After this frame: a check publishes (setState + the parent's callback).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _manual) _onChanged(_rest.text, now: true);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _rest.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setManual(bool on) {
    _debounce?.cancel();
    _seq++;
    // Manual starts empty, which is not yet a number to save.
    final entry = on
        ? ManualLrEntry(
            manualLrPrefix,
            ManualLrStatus.invalid,
            manualLrRestError(''),
          )
        : null;
    setState(() {
      _manual = on;
      _entry = entry;
      _rest.clear();
    });
    widget.onManualChanged(entry);
    if (on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _onChanged(String typed, {bool now = false}) {
    // A pasted full number ("LR/Manual/PUN/1") keeps only its rest.
    final rest = manualLrRest(typed);
    if (rest != _rest.text) {
      _rest.value = TextEditingValue(
        text: rest,
        selection: TextSelection.collapsed(offset: rest.length),
      );
    }
    _debounce?.cancel();
    final seq = ++_seq;
    final number = '$manualLrPrefix$rest';
    final formatError = manualLrRestError(rest);
    if (formatError != null) {
      _publish(ManualLrEntry(number, ManualLrStatus.invalid, formatError));
      return;
    }
    _publish(ManualLrEntry(number, ManualLrStatus.checking));
    _debounce = Timer(
      now ? Duration.zero : const Duration(milliseconds: 400),
      () async {
        ManualLrEntry next;
        try {
          final r = await ref.read(lrRepositoryProvider).checkNumber(number);
          next = r.available
              ? ManualLrEntry(r.number ?? number, ManualLrStatus.available)
              : ManualLrEntry(
                  r.number ?? number,
                  r.code == 'LR_NUMBER_TAKEN'
                      ? ManualLrStatus.taken
                      : ManualLrStatus.invalid,
                  r.message ?? 'This number cannot be used.',
                );
        } catch (e) {
          next = ManualLrEntry(
            number,
            ManualLrStatus.unknown,
            'Could not check it now (${friendlyErrorMessage(e)}) — it is checked again on save.',
          );
        }
        // Only the answer for what is in the field now counts.
        if (!mounted || seq != _seq || !_manual) return;
        _publish(next);
      },
    );
  }

  void _publish(ManualLrEntry e) {
    setState(() => _entry = e);
    widget.onManualChanged(e);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.plum.withValues(alpha: 0.18)),
      ),
      // Manual: the field gets the full width under the header, so it fits a
      // phone as well as a desktop. On a phone the mode switch takes its own
      // line too, rather than squeezing the number.
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 440;
          final showSwitch = !widget.isEdit;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.plum.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _manual
                          ? Icons.edit_note_rounded
                          : Icons.confirmation_number_outlined,
                      color: AppColors.plum,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _manual ? _manualTitle() : _autoNumber()),
                  if (showSwitch && !narrow) ...[
                    const SizedBox(width: 8),
                    _modeSwitch(),
                  ],
                ],
              ),
              if (showSwitch && narrow)
                Align(alignment: Alignment.centerRight, child: _modeSwitch()),
              if (_manual) ...[const SizedBox(height: 10), _manualField()],
            ],
          );
        },
      ),
    );
  }

  Widget _manualTitle() => const Text(
    'LR Number (manual)',
    style: TextStyle(
      color: AppColors.slate,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _autoNumber() {
    final n = widget.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isEdit ? 'LR Number' : 'LR Number (preview)',
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          n.isEmpty ? 'Assigned automatically on save' : n,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: n.isEmpty ? AppColors.slate : AppColors.ink,
            fontWeight: FontWeight.w800,
            fontSize: n.isEmpty ? 13.5 : 18,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _manualField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('manual-lr-number'),
          controller: _rest,
          focusNode: _focus,
          onChanged: _onChanged,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9/_.\-]')),
            LengthLimitingTextInputFormatter(
              manualLrPrefix.length + manualLrRestMaxLength,
            ),
          ],
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: AppColors.ink,
          ),
          decoration: const InputDecoration(
            isDense: true,
            prefixText: manualLrPrefix,
            prefixStyle: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.plum,
            ),
            hintText: 'PUN/0001',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        ManualLrStatusLine(entry: _entry),
      ],
    );
  }

  Widget _modeSwitch() {
    return _manual
        ? TextButton.icon(
            onPressed: () => _setManual(false),
            icon: const Icon(Icons.autorenew_rounded, size: 16),
            label: const Text('Use automatic'),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.number.isNotEmpty)
                const Text(
                  'confirmed on save',
                  style: TextStyle(color: AppColors.slate, fontSize: 10.5),
                ),
              TextButton.icon(
                onPressed: () => _setManual(true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Enter manually'),
              ),
            ],
          );
  }
}
