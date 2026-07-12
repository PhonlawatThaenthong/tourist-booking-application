import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'blocs/auth_cubit.dart';
import 'blocs/booking_cubit.dart';
import 'blocs/restaurant_cubit.dart';
import 'blocs/room_cubit.dart';
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
        BlocProvider(create: (_) => AuthCubit()..init()),
        BlocProvider(create: (_) => RoomCubit()),
        BlocProvider(create: (_) => BookingCubit()),
        BlocProvider(create: (_) => RestaurantCubit()),
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
