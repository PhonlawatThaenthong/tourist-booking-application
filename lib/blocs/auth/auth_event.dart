import '../../models/user.dart';

abstract class AuthEvent {
  const AuthEvent();
}

/// Restore a previous session from local storage on app start.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  const AuthLoginRequested(this.email, this.password);
}

/// Registers a new customer account and logs them in.
class AuthRegisterRequested extends AuthEvent {
  final String name;
  final String email;
  final String phone;
  final String password;
  const AuthRegisterRequested({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
  });
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Admin-only: create a staff or admin account.
class AuthStaffCreateRequested extends AuthEvent {
  final String name;
  final String email;
  final String phone;
  final String password;
  final UserRole role;
  const AuthStaffCreateRequested({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
  });
}

/// Admin-only: remove a staff or admin account.
class AuthStaffDeleteRequested extends AuthEvent {
  final String id;
  const AuthStaffDeleteRequested(this.id);
}
