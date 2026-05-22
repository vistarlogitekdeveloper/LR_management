enum UserRole { admin, operator, accounts }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.operator => 'Operator',
        UserRole.accounts => 'Accounts',
      };

  bool get canCreate => this != UserRole.accounts;
  bool get canEdit => this != UserRole.accounts;
  bool get canDelete => this == UserRole.admin;
  bool get canReports => true;
  bool get canMasters => this == UserRole.admin;
  bool get canAdmin => this == UserRole.admin;
}

class AppUser {
  final String username;
  final String password;
  final UserRole role;
  final String name;

  const AppUser({
    required this.username,
    required this.password,
    required this.role,
    required this.name,
  });
}
