import '../../models/user.dart';

enum AuthStatus {
  initial,
  authenticating,
  authenticated,
  unauthenticated,
  failure,
}

class AuthState {
  final AuthStatus status;
  final bool initialised;
  final AppUser? currentUser;
  final List<AppUser> users;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.initialised = false,
    this.currentUser,
    this.users = const [],
    this.errorMessage,
  });

  bool get isLoggedIn => currentUser != null;
  List<AppUser> get staffUsers =>
      users.where((u) => u.role.isStaffSide).toList();

  AuthState copyWith({
    AuthStatus? status,
    bool? initialised,
    AppUser? currentUser,
    bool clearCurrentUser = false,
    List<AppUser>? users,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      initialised: initialised ?? this.initialised,
      currentUser: clearCurrentUser ? null : (currentUser ?? this.currentUser),
      users: users ?? this.users,
      errorMessage: errorMessage,
    );
  }
}
