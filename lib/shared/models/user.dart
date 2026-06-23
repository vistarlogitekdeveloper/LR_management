enum UserRole { admin, operator, accounts }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.operator => 'Operator',
        UserRole.accounts => 'Accounts',
      };

  String get code => switch (this) {
        UserRole.admin => 'ADMIN',
        UserRole.operator => 'OPERATOR',
        UserRole.accounts => 'ACCOUNTS',
      };

  bool get canCreate => this != UserRole.accounts;
  bool get canEdit => this != UserRole.accounts;
  bool get canDelete => this == UserRole.admin;
  bool get canReports => true;
  bool get canMasters => this == UserRole.admin;
  bool get canAdmin => this == UserRole.admin;
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
    this.active = true,
    this.version = 0,
    this.permissions = const [],
  });

  bool can(String permission) =>
      permissions.isEmpty ? true : permissions.contains(permission);

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // Backend may return role as a flat string ("ADMIN") or an object
    // ({code: "ADMIN", name: "Admin"}). Accept both.
    final dynamic roleField = json['role'];
    String roleStr;
    String roleId = (json['role_id'] as String?) ?? '';
    if (roleField is String) {
      roleStr = roleField;
    } else if (roleField is Map) {
      roleStr =
          (roleField['code'] ?? roleField['name'] ?? 'operator').toString();
      roleId = (roleField['id'] as String?) ?? roleId;
    } else {
      roleStr = 'operator';
    }
    final roleNorm = roleStr.toLowerCase();
    final role = UserRole.values.firstWhere(
      (r) => r.name == roleNorm,
      orElse: () => UserRole.operator,
    );
    return AppUser(
      id: (json['id'] as String?) ?? '',
      username: json['username'] as String,
      password: '',
      role: role,
      name: (json['name'] as String?) ?? (json['username'] as String),
      email: (json['email'] as String?) ?? '',
      mobile: json['mobile'] as String?,
      roleId: roleId,
      active: (json['active'] as bool?) ?? true,
      version: (json['version'] as num?)?.toInt() ?? 0,
      permissions: ((json['permissions'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
