import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);

/// Server-side aggregates for the dashboard headline tiles. Refetches when the
/// authenticated user changes (i.e. after login).
///
/// The result is kept alive for 30 s after the last watcher disposes: a quick
/// hop from Dashboard → any other page → back to Dashboard reuses the cached
/// figures instead of re-hitting /reports/dashboard, which was the biggest
/// nav-lag on the Dashboard tile. Same window as [LrNotifier]'s TTL so both
/// caches line up.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const DashboardSummary();
  final link = ref.keepAlive();
  Timer(const Duration(seconds: 30), link.close);
  return ref.watch(reportsRepositoryProvider).dashboard();
});
