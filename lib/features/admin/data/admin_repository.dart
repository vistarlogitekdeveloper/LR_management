import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/audit_entry.dart';
import '../../../shared/models/user.dart';

class RoleInfo {
  final String id;
  final String code;
  final String name;
  const RoleInfo({required this.id, required this.code, required this.name});

  factory RoleInfo.fromJson(Map<String, dynamic> json) => RoleInfo(
        id: json['id'] as String,
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
      );
}

class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<List<AppUser>> listUsers() async {
    final res = await _api.dio.get('/admin/users');
    final rows = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return rows.map(AppUser.fromJson).toList();
  }

  Future<AppUser> createUser({
    required String username,
    required String name,
    required String roleId,
    required String password,
    String? email,
    String? mobile,
    bool active = true,
  }) async {
    final res = await _api.dio.post('/admin/users', data: {
      'username': username,
      'name': name,
      'role_id': roleId,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
      if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
      'active': active,
    });
    return AppUser.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<AppUser> updateUser(
    String id,
    int version, {
    String? name,
    String? email,
    String? mobile,
    String? roleId,
    bool? active,
  }) async {
    final res = await _api.dio.patch(
      '/admin/users/$id',
      data: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (mobile != null) 'mobile': mobile,
        if (roleId != null) 'role_id': roleId,
        if (active != null) 'active': active,
      },
      options: Options(headers: {'If-Match': version.toString()}),
    );
    return AppUser.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> deleteUser(String id) async {
    await _api.dio.delete('/admin/users/$id');
  }

  Future<List<RoleInfo>> listRoles() async {
    final res = await _api.dio.get('/admin/roles');
    final rows = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return rows.map(RoleInfo.fromJson).toList();
  }

  Future<List<AuditEntry>> listAudit({String? entityType}) async {
    final rows = await fetchAllPages(
      _api,
      '/admin/audit',
      query: {if (entityType != null) 'entity_type': entityType},
      maxPages: 5,
    );
    return rows.map(AuditEntry.fromJson).toList();
  }
}
