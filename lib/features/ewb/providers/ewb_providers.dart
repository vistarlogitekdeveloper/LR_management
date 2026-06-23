import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/ewb_repository.dart';

final ewbRepositoryProvider = Provider<EwbRepository>(
    (ref) => EwbRepository(ref.watch(apiClientProvider)));

final ewbListProvider = FutureProvider.autoDispose<List<EwbRecord>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(ewbRepositoryProvider).list();
});
