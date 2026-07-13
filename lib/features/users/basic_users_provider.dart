import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_providers.dart';
import '../auth/providers/auth_provider.dart';

/// A minimal reference to an app user (id + display name) for pickers such as
/// the LR "Trip Lead By" field. Equality is by id so it works as a selectable
/// value in [SearchableField] / dropdowns.
class UserRef {
  final String id;
  final String name;
  const UserRef({required this.id, required this.name});

  factory UserRef.fromJson(Map<String, dynamic> json) => UserRef(
        id: (json['id'] as String?) ?? '',
        name:
            (json['name'] as String?) ?? (json['username'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) => other is UserRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Lightweight list of active app users (id + name), usable by ANY signed-in
/// user who can create/edit an LR — not just admins.
///
/// Backed by `GET /users/basic`, which the backend must expose to LR-creating
/// roles (operators, regional admins, …). It must NOT be the admin-only
/// `/admin/users` endpoint. Until that endpoint exists the call fails and this
/// degrades to an empty list, so the picker simply shows no options instead of
/// throwing.
final basicUsersProvider = FutureProvider<List<UserRef>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  try {
    final res = await ref.watch(apiClientProvider).dio.get('/users/basic');
    final raw = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    final list = (raw as List?) ?? const [];
    final users = list
        .whereType<Map>()
        .map((e) => UserRef.fromJson(e.cast<String, dynamic>()))
        .where((u) => u.id.isNotEmpty && u.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return users;
  } catch (_) {
    // Endpoint not deployed yet / not permitted for this role — degrade to an
    // empty picker rather than surfacing an error on the LR form.
    return const [];
  }
});
