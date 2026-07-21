import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps a routed screen and fires [onEnter] once when the page mounts, i.e.
/// every time the user navigates to it. Used to pull fresh data from the API on
/// each page open so the app always shows live, up-to-date data.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    final flag = widget.loadingFlag;
    try {
      await widget.onEnter(ref);
    } catch (_) {
      // Entry refresh is best-effort — a transient failure keeps any prior data
      // on screen (and clears the loading flag below so it isn't stuck).
    } finally {
      // Guard against the user navigating away before the fetch resolves —
      // writing to `ref` after dispose would throw.
      if (mounted && flag != null) {
        ref.read(flag.notifier).state = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
