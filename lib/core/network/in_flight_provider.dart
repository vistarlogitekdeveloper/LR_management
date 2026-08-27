import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global count of background refreshes currently in flight. Any widget can
/// watch this to render a subtle "working" indicator so a click that produces
/// no visible change (cached render) still reads as responsive.
///
/// Refresh sites (RefreshGate, notifiers) bump this on start and drop it in
/// their finally block — the notifier reference is stable across widget
/// disposal, so the count stays accurate even if the user navigates away
/// mid-fetch.
final activeRefreshCountProvider = StateProvider<int>((ref) => 0);
