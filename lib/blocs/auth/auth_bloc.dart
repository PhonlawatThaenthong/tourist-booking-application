import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../models/user.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// Handles registration, login, logout and session restoration. Acts as the
/// in-memory user store (seeded from [MockData]).
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthStaffCreateRequested>(_onStaffCreateRequested);
    on<AuthStaffDeleteRequested>(_onStaffDeleteRequested);
  }

  static const _prefsKey = 'logged_in_user_id';

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    final users = MockData.users();
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsKey);
    AppUser? user;
    if (id != null) {
      try {
        user = users.firstWhere((u) => u.id == id);
      } catch (_) {
        user = null;
      }
    }
    emit(state.copyWith(
      initialised: true,
      users: users,
      currentUser: user,
      clearCurrentUser: user == null,
      status:
          user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    ));
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.authenticating));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final match = state.users.where(
      (u) =>
          u.email.toLowerCase() == event.email.trim().toLowerCase() &&
          u.password == event.password,
    );
    if (match.isEmpty) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: 'Invalid email or password.',
      ));
      return;
    }
    final user = match.first;
    await _persist(user.id);
    emit(state.copyWith(status: AuthStatus.authenticated, currentUser: user));
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.authenticating));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final exists = state.users.any(
      (u) => u.email.toLowerCase() == event.email.trim().toLowerCase(),
    );
    if (exists) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: 'An account with this email already exists.',
      ));
      return;
    }
    final user = AppUser(
      id: const Uuid().v4(),
      name: event.name.trim(),
      email: event.email.trim(),
      phone: event.phone.trim(),
      password: event.password,
      role: UserRole.customer,
    );
    await _persist(user.id);
    emit(state.copyWith(
      status: AuthStatus.authenticated,
      currentUser: user,
      users: [...state.users, user],
    ));
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      clearCurrentUser: true,
    ));
  }

  void _onStaffCreateRequested(
    AuthStaffCreateRequested event,
    Emitter<AuthState> emit,
  ) {
    if (state.users.any(
      (u) => u.email.toLowerCase() == event.email.trim().toLowerCase(),
    )) {
      emit(state.copyWith(
        errorMessage: 'An account with this email already exists.',
      ));
      return;
    }
    final staff = AppUser(
      id: const Uuid().v4(),
      name: event.name.trim(),
      email: event.email.trim(),
      phone: event.phone.trim(),
      password: event.password,
      role: event.role,
    );
    emit(state.copyWith(users: [...state.users, staff]));
  }

  void _onStaffDeleteRequested(
    AuthStaffDeleteRequested event,
    Emitter<AuthState> emit,
  ) {
    if (state.currentUser?.id == event.id) {
      emit(state.copyWith(
        errorMessage: 'You cannot delete your own account.',
      ));
      return;
    }
    emit(state.copyWith(
      users: state.users.where((u) => u.id != event.id).toList(),
    ));
  }

  Future<void> _persist(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
  }
}
