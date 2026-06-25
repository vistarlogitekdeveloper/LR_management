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

class RegionInfo {
  final String id;
  final String code;
  final String name;
  final bool active;
  final int version;
  const RegionInfo({
    required this.id,
    required this.code,
    required this.name,
    this.active = true,
    this.version = 0,
  });

  factory RegionInfo.fromJson(Map<String, dynamic> json) => RegionInfo(
        id: json['id'] as String,
        code: (json['code'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        active: (json['active'] as bool?) ?? true,
        version: (json['version'] as num?)?.toInt() ?? 0,
      );
}

/// One per-user permission toggle row, as returned by the backend: whether the
/// role grants it by default, any per-user override, and the net effect.
class PermissionToggle {
  final String code;
  final String label;
  final bool roleDefault;
  final String? override; // 'ALLOW' | 'DENY' | null
  final bool effective;

  const PermissionToggle({
    required this.code,
    required this.label,
    required this.roleDefault,
    required this.override,
    required this.effective,
  });

  factory PermissionToggle.fromJson(Map<String, dynamic> json) => PermissionToggle(
        code: json['code'] as String,
        label: (json['label'] as String?) ?? json['code'] as String,
        roleDefault: (json['role_default'] as bool?) ?? false,
        override: json['override'] as String?,
        effective: (json['effective'] as bool?) ?? false,
      );
}

class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<List<AppUser>> listUsers({String? regionId}) async {
    final res = await _api.dio.get('/admin/users', queryParameters: {
      if (regionId != null && regionId.isNotEmpty) 'region_id': regionId,
    });
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
    String? regionId,
    bool active = true,
  }) async {
    final res = await _api.dio.post('/admin/users', data: {
      'username': username,
      'name': name,
      'role_id': roleId,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
      if (mobile != null && mobile.isNotEmpty) 'mobile': mobile,
      if (regionId != null && regionId.isNotEmpty) 'region_id': regionId,
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
    String? regionId,
    bool? active,
  }) async {
    final res = await _api.dio.patch(
      '/admin/users/$id',
      data: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (mobile != null) 'mobile': mobile,
        if (roleId != null) 'role_id': roleId,
        if (regionId != null) 'region_id': regionId,
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

  // ---- Regions ----

  Future<List<RegionInfo>> listRegions() async {
    final res = await _api.dio.get('/admin/regions');
    final rows = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return rows.map(RegionInfo.fromJson).toList();
  }

  Future<RegionInfo> createRegion({required String name, String? code}) async {
    final res = await _api.dio.post('/admin/regions', data: {
      'name': name,
      if (code != null && code.isNotEmpty) 'code': code,
    });
    return RegionInfo.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<RegionInfo> updateRegion(
    String id,
    int version, {
    String? name,
    String? code,
    bool? active,
  }) async {
    final res = await _api.dio.patch(
      '/admin/regions/$id',
      data: {
        if (name != null) 'name': name,
        if (code != null) 'code': code,
        if (active != null) 'active': active,
      },
      options: Options(headers: {'If-Match': version.toString()}),
    );
    return RegionInfo.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> deleteRegion(String id) async {
    await _api.dio.delete('/admin/regions/$id');
  }

  // ---- Per-user permission overrides ----

  Future<List<PermissionToggle>> getUserPermissions(String userId) async {
    final res = await _api.dio.get('/admin/users/$userId/permissions');
    final data = (res.data['data'] as Map).cast<String, dynamic>();
    final toggles = (data['toggles'] as List).cast<Map<String, dynamic>>();
    return toggles.map(PermissionToggle.fromJson).toList();
  }

  Future<List<PermissionToggle>> setUserPermissions(
    String userId,
    Map<String, bool> permissions,
  ) async {
    final res = await _api.dio.put(
      '/admin/users/$userId/permissions',
      data: {'permissions': permissions},
    );
    final data = (res.data['data'] as Map).cast<String, dynamic>();
    final toggles = (data['toggles'] as List).cast<Map<String, dynamic>>();
    return toggles.map(PermissionToggle.fromJson).toList();
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
