import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/mock_data.dart';
import '../../models/restaurant.dart';
import 'restaurant_event.dart';
import 'restaurant_state.dart';

class RestaurantBloc extends Bloc<RestaurantEvent, RestaurantState> {
  RestaurantBloc() : super(const RestaurantState()) {
    on<RestaurantStarted>(_onStarted);
  }

  /// Restaurants sorted nearest-first.
  List<Restaurant> get nearby {
    final sorted = [...state.restaurants];
    sorted.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return sorted;
  }

  void _onStarted(RestaurantStarted event, Emitter<RestaurantState> emit) {
    emit(state.copyWith(restaurants: MockData.restaurants()));
  }
}
