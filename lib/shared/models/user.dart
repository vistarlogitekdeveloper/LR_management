enum UserRole { superAdmin, admin, operator, accounts }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.superAdmin => 'Super Admin',
        UserRole.admin => 'Admin',
        UserRole.operator => 'Operator',
        UserRole.accounts => 'Accounts',
      };

  String get code => switch (this) {
        UserRole.superAdmin => 'SUPER_ADMIN',
        UserRole.admin => 'ADMIN',
        UserRole.operator => 'OPERATOR',
        UserRole.accounts => 'ACCOUNTS',
      };

  bool get isSuperAdmin => this == UserRole.superAdmin;

  // Coarse role gates used for navigation / routing. Fine-grained feature
  // access (which masters, LR create/edit/delete, ...) is permission-based —
  // see AppUser.can* getters, which honour per-user overrides.
  bool get canCreate => this != UserRole.accounts;
  bool get canEdit => this != UserRole.accounts;
  bool get canDelete => this == UserRole.admin || this == UserRole.superAdmin;
  bool get canReports => true;
  bool get canMasters => this != UserRole.accounts;
  bool get canAdmin => this == UserRole.admin || this == UserRole.superAdmin;
  bool get canManageRegions => this == UserRole.superAdmin;
}

class AppUser {
  final String id;
  final String username;
  final String password;
  final UserRole role;
  final String name;
  final String email;
  final String? mobile;
  final String roleId;
  final String? regionId;
  final String? regionName;
  final bool active;
  final int version;
  final List<String> permissions;

  const AppUser({
    this.id = '',
    required this.username,
    this.password = '',
    required this.role,
    required this.name,
    this.email = '',
    this.mobile,
    this.roleId = '',
    this.regionId,
    this.regionName,
    this.active = true,
    this.version = 0,
    this.permissions = const [],
  });

  bool get isSuperAdmin => role == UserRole.superAdmin;

  /// True if the user holds [permission] in their effective set (role defaults
  /// ± per-user overrides, as computed by the backend). Strict membership —
  /// an empty set grants nothing.
  bool can(String permission) => permissions.contains(permission);

  // ---- Fine-grained feature access (per-user, backend-enforced) ----
  bool get canCreateLr => can('LR_CREATE');
  bool get canEditLr => can('LR_EDIT');
  bool get canDeleteLr => can('LR_DELETE');
  bool get canViewReports => can('REPORTS_VIEW');

  // Master management: the granular per-master permission OR the coarse
  // MASTERS_MANAGE umbrella — so this works whether the backend is the new
  // per-master scheme or the older umbrella-only one (keeps admins working
  // even if the frontend is deployed ahead of the backend).
  bool _canMaster(String code) => can(code) || can('MASTERS_MANAGE');
  bool get canManageConsignors => _canMaster('MASTER_CONSIGNOR_MANAGE');
  bool get canManageConsignees => _canMaster('MASTER_CONSIGNEE_MANAGE');
  bool get canManageVehicles => _canMaster('MASTER_VEHICLE_MANAGE');
  bool get canManageDrivers => _canMaster('MASTER_DRIVER_MANAGE');
  bool get canManageTransporters => _canMaster('MASTER_TRANSPORTER_MANAGE');
  bool get canManageRoutes => _canMaster('MASTER_ROUTE_MANAGE');

  /// Can reach the admin surface (users, regions, system config).
  bool get canAdmin => role.canAdmin;

  /// Super-admin only: maintain the region list, manage all regions' users.
  bool get canManageRegions => role.canManageRegions;

  static UserRole roleFromCode(String raw) {
    switch (raw.toUpperCase()) {
      case 'SUPER_ADMIN':
      case 'SUPERADMIN':
        return UserRole.superAdmin;
      case 'ADMIN':
        return UserRole.admin;
      case 'ACCOUNTS':
        return UserRole.accounts;
      case 'OPERATOR':
      default:
        return UserRole.operator;
    }
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // Backend may return role as a flat string ("ADMIN") or an object
    // ({code: "ADMIN", name: "Admin"}). Accept both.
    final dynamic roleField = json['role'];
    String roleStr;
    String roleId = (json['role_id'] as String?) ?? '';
    if (roleField is String) {
      roleStr = roleField;
    } else if (roleField is Map) {
      roleStr = (roleField['code'] ?? roleField['name'] ?? 'operator').toString();
      roleId = (roleField['id'] as String?) ?? roleId;
    } else {
      roleStr = 'operator';
    }
    final role = roleFromCode(roleStr);

    // Region may arrive as a nested object and/or a flat region_id.
    String? regionId = json['region_id'] as String?;
    String? regionName;
    final dynamic regionField = json['region'];
    if (regionField is Map) {
      regionId = (regionField['id'] as String?) ?? regionId;
      regionName = regionField['name'] as String?;
    }

    return AppUser(
      id: (json['id'] as String?) ?? '',
      username: json['username'] as String,
      password: '',
      role: role,
      name: (json['name'] as String?) ?? (json['username'] as String),
      email: (json['email'] as String?) ?? '',
      mobile: json['mobile'] as String?,
      roleId: roleId,
      regionId: regionId,
      regionName: regionName,
      active: (json['active'] as bool?) ?? true,
      version: (json['version'] as num?)?.toInt() ?? 0,
      permissions: ((json['permissions'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
