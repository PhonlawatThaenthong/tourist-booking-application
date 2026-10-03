import '../../models/user.dart';
import '../auth_repository.dart';
import '../repository_exception.dart';
import 'api_client.dart';

/// HTTP [AuthRepository] against `/api/auth` and `/api/staff/users`.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);

  final ApiClient _api;

  /// `GET /api/staff/users` is back-office only. Rather than let a customer's
  /// app fire a request that can only come back 403, it answers with an empty
  /// list — which is all the customer-facing screens ever needed from it.
  @override
  Future<List<AppUser>> listUsers() async {
    if (!_api.isStaffSide) return const [];
    final data = await _api.get('/api/staff/users') as List<dynamic>;
    return data
        .map((e) => userFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<AppUser> login({required String email, required String password}) async {
    final data = await _api.post(
      '/api/auth/login',
      body: {'email': email.trim(), 'password': password},
      auth: false,
    );
    return _api.saveSession(data as Map<String, dynamic>);
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
    };
    // The API rejects unknown *and* null-valued fields
    // (`forbidNonWhitelisted`), so an empty phone is omitted, not sent as ''.
    if (phone.trim().isNotEmpty) body['phone'] = phone.trim();

    final data = await _api.post('/api/auth/register', body: body, auth: false);
    return _api.saveSession(data as Map<String, dynamic>);
  }

  @override
  Future<AppUser> createStaff({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'role': role.name,
    };
    if (phone.trim().isNotEmpty) body['phone'] = phone.trim();

    final data = await _api.post('/api/staff/users', body: body);
    return userFromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteUser(String id) => _api.delete('/api/staff/users/$id');

  @override
  Future<AppUser?> restoreSession() async {
    final remembered = await _api.loadSession();
    if (remembered == null) return null;
    try {
      // Verifies the stored tokens are still good and picks up a role or name
      // changed on another device. A 401 here triggers one silent rotation
      // inside ApiClient before it gives up.
      final data = await _api.get('/api/auth/me') as Map<String, dynamic>;
      final user = userFromJson(data);
      _api.setCurrentUser(user);
      return user;
    } on AuthException {
      await _api.clearSession();
      return null;
    }
  }

  @override
  Future<void> persistSession(AppUser user) async {
    // Login, register and refresh already persist the tokens; the Bloc calling
    // this again must not overwrite them with a token-less snapshot.
    _api.setCurrentUser(user);
  }

  @override
  Future<void> clearSession() async {
    final token = _api.refreshToken;
    if (token != null) {
      try {
        await _api.post('/api/auth/logout', body: {'refreshToken': token});
      } on RepositoryException {
        // Server-side revocation is best-effort — the local session goes away
        // either way, otherwise a network blip would trap the user signed in.
      }
    }
    await _api.clearSession();
  }

  @override
  Future<void> forgotPassword({required String email}) async {
    await _api.post(
      '/api/auth/forgot-password',
      body: {'email': email.trim()},
      auth: false,
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.post(
      '/api/auth/reset-password',
      body: {'email': email.trim(), 'code': code.trim(), 'newPassword': newPassword},
      auth: false,
    );
  }
}
