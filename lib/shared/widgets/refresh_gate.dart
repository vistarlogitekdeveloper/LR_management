import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/in_flight_provider.dart';
import '../../core/utils/perf_log.dart';

/// Wraps a routed screen and fires [onEnter] once when the page mounts, i.e.
/// every time the user navigates to it. Notifiers are expected to enforce their
/// own staleness policy (TTL / in-flight dedupe) so a re-nav to a page whose
/// data is already fresh is a no-op — this widget just kicks the trigger.
///
/// The fetch is scheduled in a microtask (not a post-frame callback) so the
/// request goes out in the same event-loop turn as the tap, instead of waiting
/// for the new page's first frame to render. On heavy pages (LR list with
/// hundreds of rows) that saves 200–500 ms of perceived latency.
///
/// While the fetch is running, [activeRefreshCountProvider] is incremented so
/// a global "working" indicator (top progress bar) can light up — meaningful
/// even when the screen renders from cache and shows no other change.
///
/// When [loadingFlag] is supplied, it is flipped to `false` once [onEnter]
/// settles (success or error). The flag starts `true` (the provider default),
/// so a screen shows a shimmer while the first fetch is in flight and stops as
/// soon as it returns. The flip is guarded by [State.mounted], so navigating
/// away mid-fetch never writes to a disposed ref.
class RefreshGate extends ConsumerStatefulWidget {
  const RefreshGate({
    super.key,
    required this.onEnter,
    required this.child,
    this.loadingFlag,
  });

  /// Runs on entry. May be sync or async; when async and [loadingFlag] is set,
  /// the flag clears only after the returned future completes.
  final FutureOr<void> Function(WidgetRef ref) onEnter;
  final Widget child;

  /// Optional first-load flag, cleared once [onEnter] settles.
  final StateProvider<bool>? loadingFlag;

  @override
  ConsumerState<RefreshGate> createState() => _RefreshGateState();
}

class _RefreshGateState extends ConsumerState<RefreshGate> {
  @override
  void initState() {
    super.initState();
    if (kAccPerfLog) accLog('[REFRESH-GATE] INIT');
    // Microtask, not addPostFrameCallback: kick the fetch immediately in this
    // event-loop turn so the network hit doesn't queue behind first-frame
    // rebuild work (which on the LR list can be hundreds of ms).
    scheduleMicrotask(() {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    final flag = widget.loadingFlag;
    // Hold notifier references before await — they survive widget disposal, so
    // the counter still decrements even if the user navigates away mid-fetch.
    final counter = ref.read(activeRefreshCountProvider.notifier);
    counter.update((s) => s + 1);
    try {
      await widget.onEnter(ref);
    } catch (_) {
      // Entry refresh is best-effort — a transient failure keeps any prior data
      // on screen (and clears the loading flag below so it isn't stuck).
    } finally {
      counter.update((s) => s - 1);
      // Guard against the user navigating away before the fetch resolves —
      // writing to `ref` after dispose would throw.
      if (mounted && flag != null) {
        ref.read(flag.notifier).state = false;
      }
    }
  }

  @override
  void dispose() {
    if (kAccPerfLog) accLog('[REFRESH-GATE] DISPOSE');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
