import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/mock_data.dart';
import '../models/user.dart';

class AuthState {
  AuthState();
}

/// Handles registration, login, logout and session restoration. Acts as the
/// in-memory user store (seeded from [MockData]).
class AuthCubit extends Cubit<AuthState> {
  AuthCubit() : super(AuthState());

  final List<AppUser> _users = MockData.users();
  AppUser? _currentUser;
  bool _initialised = false;

  static const _prefsKey = 'logged_in_user_id';

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialised => _initialised;
  List<AppUser> get staffUsers =>
      _users.where((u) => u.role.isStaffSide).toList();

  /// Restore a previous session from local storage on app start.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    if (id != null) {
      try {
        _currentUser = _users.firstWhere((u) => u.id == id);
      } catch (_) {
        _currentUser = null;
      }
    }
    _initialised = true;
    emit(AuthState());
  }

  /// Returns null on success, or an error message on failure.
  Future<String?> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final match = _users.where(
      (u) =>
          u.email.toLowerCase() == email.trim().toLowerCase() &&
          u.password == password,
    );
    if (match.isEmpty) {
      return 'Invalid email or password.';
    }
    _currentUser = match.first;
    await _persist(_currentUser!.id);
    emit(AuthState());
    return null;
  }

  /// Registers a new customer account and logs them in. Returns an error
  /// message on failure (e.g. duplicate email).
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final exists = _users.any(
      (u) => u.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (exists) {
      return 'An account with this email already exists.';
    }
    final user = AppUser(
      id: const Uuid().v4(),
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      password: password,
      role: UserRole.customer,
    );
    _users.add(user);
    _currentUser = user;
    await _persist(user.id);
    emit(AuthState());
    return null;
  }

  /// Admin-only: create a staff or admin account.
  String? createStaff({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  }) {
    if (_users.any((u) => u.email.toLowerCase() == email.trim().toLowerCase())) {
      return 'An account with this email already exists.';
    }
    _users.add(AppUser(
      id: const Uuid().v4(),
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      password: password,
      role: role,
    ));
    emit(AuthState());
    return null;
  }

  /// Admin-only: remove a staff or admin account. Returns null on success,
  /// or an error message on failure.
  String? deleteStaff(String id) {
    if (_currentUser?.id == id) {
      return 'You cannot delete your own account.';
    }
    _users.removeWhere((u) => u.id == id);
    emit(AuthState());
    return null;
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    emit(AuthState());
  }

  Future<void> _persist(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }
}
