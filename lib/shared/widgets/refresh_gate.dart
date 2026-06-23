import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps a routed screen and fires [onEnter] once when the page mounts, i.e.
/// every time the user navigates to it. Used to pull fresh data from the API on
/// each page open so the app always shows live, up-to-date data.
class RefreshGate extends ConsumerStatefulWidget {
  const RefreshGate({super.key, required this.onEnter, required this.child});

  final void Function(WidgetRef ref) onEnter;
  final Widget child;

  @override
  ConsumerState<RefreshGate> createState() => _RefreshGateState();
}

class _RefreshGateState extends ConsumerState<RefreshGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEnter(ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
