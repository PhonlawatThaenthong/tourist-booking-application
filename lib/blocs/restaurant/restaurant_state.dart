import '../../models/restaurant.dart';

class RestaurantState {
  final List<Restaurant> restaurants;
  const RestaurantState({this.restaurants = const []});

  RestaurantState copyWith({List<Restaurant>? restaurants}) {
    return RestaurantState(restaurants: restaurants ?? this.restaurants);
  }
}
