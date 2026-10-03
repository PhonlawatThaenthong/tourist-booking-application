import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../models/user.dart';
import '../auth_repository.dart';
import '../repository_exception.dart';

/// In-memory [AuthRepository] backed by [MockData].
///
/// This is the only place left in the app that touches mock data. Replacing it
/// with an HTTP implementation in Phase 2 requires no change to AuthBloc.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository() : _users = MockData.users();

  static const _prefsKey = 'logged_in_user_id';

  /// Simulated network latency, previously hard-coded inside AuthBloc.
  static const _latency = Duration(milliseconds: 400);

  final List<AppUser> _users;

  @override
  Future<List<AppUser>> listUsers() async => List.unmodifiable(_users);

  @override
  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(_latency);
    final normalised = email.trim().toLowerCase();
    final match = _users.where(
      (u) => u.email.toLowerCase() == normalised && u.password == password,
    );
    if (match.isEmpty) {
      throw const AuthException('Invalid email or password.');
    }
    final user = match.first;
    await persistSession(user);
    return user;
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await Future<void>.delayed(_latency);
    final user = _add(
      name: name,
      email: email,
      phone: phone,
      password: password,
      role: UserRole.customer,
    );
    await persistSession(user);
    return user;
  }

  @override
  Future<AppUser> createStaff({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    return _add(
      name: name,
      email: email,
      phone: phone,
      password: password,
      role: role,
    );
  }

  @override
  Future<void> deleteUser(String id) async {
    _users.removeWhere((u) => u.id == id);
  }

  @override
  Future<AppUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    if (id == null) return null;
    final match = _users.where((u) => u.id == id);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<void> persistSession(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, user.id);
  }

  @override
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Mirrors the API's no-enumeration behaviour: succeeds either way.
  @override
  Future<void> forgotPassword({required String email}) async {
    await Future<void>.delayed(_latency);
  }

  /// No email is actually sent in the mock, so any 6-digit code is accepted.
  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await Future<void>.delayed(_latency);
    final normalised = email.trim().toLowerCase();
    final index = _users.indexWhere((u) => u.email.toLowerCase() == normalised);
    if (index == -1) {
      throw const RepositoryException('รหัสยืนยันไม่ถูกต้องหรือหมดอายุ');
    }
    _users[index] = _users[index].copyWith(password: newPassword);
  }

  AppUser _add({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  }) {
    final normalised = email.trim().toLowerCase();
    if (_users.any((u) => u.email.toLowerCase() == normalised)) {
      throw const RepositoryException(
        'An account with this email already exists.',
      );
    }
    final user = AppUser(
      id: const Uuid().v4(),
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      password: password,
      role: role,
    );
    _users.add(user);
    return user;
  }
}
