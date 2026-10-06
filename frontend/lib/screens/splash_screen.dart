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
      return const _BrandSplash();
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

/// Shown while the auth session is restored. Same logo, size and white ground
/// as the native launch screens (Android launch_background / values-v31,
/// iOS LaunchScreen.storyboard), so the hand-off to Flutter looks seamless.
/// The spinner sits apart from the logo so the logo never shifts position.
class _BrandSplash extends StatelessWidget {
  const _BrandSplash();

  /// Must match the 160dp/pt logo in the native launch screens.
  static const double logoSize = 160;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Center(
            child: Semantics(
              label: AppConfig.hotelName,
              image: true,
              child: Image.asset(
                'image/logo.png',
                width: logoSize,
                height: logoSize,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.6),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
