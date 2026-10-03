import '../models/user.dart';

/// Data access for accounts and the signed-in session.
///
/// Method names mirror the REST contract in the backend design document
/// (section 9), so swapping [MockAuthRepository] for an HTTP implementation
/// does not change any Bloc.
abstract class AuthRepository {
  /// All accounts. Backend: `GET /api/staff/users`.
  Future<List<AppUser>> listUsers();

  /// Backend: `POST /api/auth/login`.
  /// Throws [AuthException] when the credentials do not match.
  Future<AppUser> login({required String email, required String password});

  /// Backend: `POST /api/auth/register`.
  /// Throws [RepositoryException] when the email is already taken.
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  });

  /// Backend: `POST /api/staff/users` (admin only).
  Future<AppUser> createStaff({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  });

  /// Backend: `DELETE /api/staff/users/:id` (admin only).
  Future<void> deleteUser(String id);

  // ---- Session persistence ---------------------------------------------
  // Mock: stores the user id. HTTP: stores the refresh token instead — the
  // Bloc only ever asks "who was signed in last time?".

  /// The account restored from local storage, or null if there is no session.
  Future<AppUser?> restoreSession();

  /// Remember [user] so the next app start restores the session.
  Future<void> persistSession(AppUser user);

  /// Backend: `POST /api/auth/logout`.
  Future<void> clearSession();

  /// Backend: `POST /api/auth/forgot-password`. Always succeeds — the server
  /// answers identically whether or not the email is registered, and emails
  /// a 6-digit code when it is.
  Future<void> forgotPassword({required String email});

  /// Backend: `POST /api/auth/reset-password`.
  /// Throws [RepositoryException] when the code is wrong, expired, or the
  /// email has none pending.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });
}
