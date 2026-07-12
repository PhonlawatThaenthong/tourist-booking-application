import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/mock_data.dart';
import '../models/restaurant.dart';

class RestaurantState {
  RestaurantState();
}

class RestaurantCubit extends Cubit<RestaurantState> {
  RestaurantCubit() : super(RestaurantState());

  final List<Restaurant> _restaurants = MockData.restaurants();

  /// Restaurants sorted nearest-first.
  List<Restaurant> get nearby {
    final sorted = [..._restaurants];
    sorted.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return sorted;
  }
}
