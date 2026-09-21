import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/auth/auth_event.dart';
import 'blocs/auth/auth_state.dart';
import 'blocs/booking/booking_bloc.dart';
import 'blocs/booking/booking_event.dart';
import 'blocs/restaurant/restaurant_bloc.dart';
import 'blocs/restaurant/restaurant_event.dart';
import 'blocs/room/room_bloc.dart';
import 'blocs/room/room_event.dart';
import 'config.dart';
import 'repositories/repositories.dart';
import 'repositories/api/api_repositories.dart';
import 'repositories/mock/mock_repositories.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One client for the whole app: it holds the access/refresh token pair and
  // de-duplicates token rotation across repositories.
  final app = HotelBookingApp(apiClient: ApiClient());

  // No DSN compiled in means no Sentry at all. That is the default for
  // `flutter run` and for CI, so a crash while developing never reaches the
  // project and never spends the free tier's monthly budget.
  if (AppConfig.sentryDsn.isEmpty) {
    runApp(app);
    return;
  }

  // `appRunner` is what makes this worth doing: Sentry installs its own error
  // zone around runApp, so it catches what a plain try/catch here could not —
  // uncaught async errors and Flutter framework exceptions alike.
  await SentryFlutter.init(
    (options) {
      options.dsn = AppConfig.sentryDsn;
      options.environment = AppConfig.sentryEnvironment;
      // Errors are always sent in full; only performance traces are sampled
      // down, because transactions are what exhaust a free-tier quota.
      options.tracesSampleRate = 0.1;
      // The app carries bearer tokens and payment slip images — keep request
      // bodies, headers and device identifiers out of the reports.
      options.sendDefaultPii = false;
      // Structured logs, correlated with the errors and traces above.
      options.enableLogs = true;
      // Stitches a tap in the app to the NestJS request it caused, so one
      // trace spans both — without this the mobile and backend projects
      // record the same failure as two unrelated events.
      //
      // The list is `final` and defaults to ['.*'] — every host, including
      // Google Maps. Replacing its contents keeps the sentry-trace/baggage
      // headers on our own API only. Entries are matched as regexes.
      options.tracePropagationTargets
        ..clear()
        ..addAll([
          r'^https?://localhost(:\d+)?/',
          r'^https?://10\.0\.2\.2(:\d+)?/',
          r'^https?://([^/]+\.)?poonsuk\.example/',
        ]);
    },
    // `SentryWidget` is not optional dressing: user-interaction tracing and
    // on-error screenshots both need the root widget wrapped.
    appRunner: () => runApp(SentryWidget(child: app)),
  );
}

class HotelBookingApp extends StatelessWidget {
  const HotelBookingApp({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    // Single wiring point for the data layer. Auth, rooms and bookings now talk
    // to the NestJS API; restaurants stay on mock data until `/api/restaurants`
    // exists.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>(
          create: (_) => ApiAuthRepository(apiClient),
        ),
        RepositoryProvider<RoomRepository>(
          create: (_) => ApiRoomRepository(apiClient),
        ),
        RepositoryProvider<BookingRepository>(
          create: (_) => ApiBookingRepository(apiClient),
        ),
        RepositoryProvider<PaymentRepository>(
          create: (_) => ApiPaymentRepository(apiClient),
        ),
        RepositoryProvider<RestaurantRepository>(
          create: (_) => MockRestaurantRepository(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) =>
                AuthBloc(ctx.read<AuthRepository>())..add(const AuthStarted()),
          ),
          BlocProvider(
            create: (ctx) =>
                RoomBloc(ctx.read<RoomRepository>())..add(const RoomStarted()),
          ),
          BlocProvider(
            create: (ctx) => BookingBloc(ctx.read<BookingRepository>())
              ..add(const BookingStarted()),
          ),
          BlocProvider(
            create: (ctx) => RestaurantBloc(ctx.read<RestaurantRepository>())
              ..add(const RestaurantStarted()),
          ),
        ],
        // Rooms and bookings are fetched once at startup, before anyone has
        // signed in — so the customer sees the public catalogue and no
        // bookings. The moment authentication settles (restored session, login
        // or logout) both are re-fetched, because who is asking decides which
        // endpoint answers: /api/rooms vs /api/staff/rooms, /api/bookings/me
        // vs /api/staff/bookings.
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (ctx, state) {
            if (state.status == AuthStatus.authenticated ||
                state.status == AuthStatus.unauthenticated) {
              ctx.read<RoomBloc>().add(const RoomStarted());
              ctx.read<BookingBloc>().add(const BookingStarted());
            }
          },
          child: MaterialApp(
            title: AppConfig.hotelName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            // Turns each pushed route into a navigation transaction and a
            // breadcrumb, so a crash report shows which screens the customer
            // passed through on the way to it. A no-op when Sentry is off.
            navigatorObservers: [SentryNavigatorObserver()],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', 'GB')],
            locale: const Locale('en', 'GB'),
            home: const SplashScreen(),
          ),
        ),
      ),
    );
  }
}
