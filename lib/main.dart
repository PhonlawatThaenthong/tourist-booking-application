import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/auth/auth_event.dart';
import 'blocs/booking/booking_bloc.dart';
import 'blocs/booking/booking_event.dart';
import 'blocs/restaurant/restaurant_bloc.dart';
import 'blocs/restaurant/restaurant_event.dart';
import 'blocs/room/room_bloc.dart';
import 'blocs/room/room_event.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HotelBookingApp());
}

class HotelBookingApp extends StatelessWidget {
  const HotelBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AuthBloc()..add(const AuthStarted())),
        BlocProvider(create: (_) => RoomBloc()..add(const RoomStarted())),
        BlocProvider(create: (_) => BookingBloc()..add(const BookingStarted())),
        BlocProvider(
          create: (_) => RestaurantBloc()..add(const RestaurantStarted()),
        ),
      ],
      child: MaterialApp(
        title: 'Azure Bay Hotel',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
  }
}
