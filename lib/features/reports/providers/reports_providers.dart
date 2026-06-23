import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
    (ref) => ReportsRepository(ref.watch(apiClientProvider)));

/// Server-side aggregates for the dashboard headline tiles. Refetches when the
/// authenticated user changes (i.e. after login).
final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const DashboardSummary();
  return ref.watch(reportsRepositoryProvider).dashboard();
});
