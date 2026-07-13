import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../config.dart';
import '../models/user.dart';
import '../blocs/auth/auth_bloc.dart';
import '../theme.dart';
import 'admin/admin_home.dart';
import 'auth/login_screen.dart';
import 'customer/customer_home.dart';

/// Decides which experience to show once the auth session has been restored:
/// the customer app, the back-office, or the login screen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;

    if (!auth.initialised) {
      return const Scaffold(
        backgroundColor: AppTheme.primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.beach_access, color: Colors.white, size: 64),
              SizedBox(height: 16),
              Text(
                AppConfig.hotelName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    switch (auth.currentUser!.role) {
      case UserRole.customer:
        return const CustomerHome();
      case UserRole.staff:
      case UserRole.admin:
        return const AdminHome();
    }
  }
}
