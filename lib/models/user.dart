/// Roles supported by the application. Customers book rooms; staff and admins
/// access the back-office. Admins have every staff permission plus user/role
/// management and configuration.
enum UserRole { customer, staff, admin }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.customer:
        return 'Customer';
      case UserRole.staff:
        return 'Staff';
      case UserRole.admin:
        return 'Administrator';
    }
  }

  bool get isStaffSide => this == UserRole.staff || this == UserRole.admin;
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String password; // Plain text for demo only — never do this in production.
  final UserRole role;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
  });

  AppUser copyWith({
    String? name,
    String? email,
    String? phone,
    String? password,
    UserRole? role,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      password: password ?? this.password,
      role: role ?? this.role,
    );
  }
}
