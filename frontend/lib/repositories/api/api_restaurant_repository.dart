import 'dart:math' as math;

import '../../config.dart';
import '../../models/restaurant.dart';
import '../restaurant_repository.dart';
import 'api_client.dart';

/// HTTP [RestaurantRepository] against the public `/api/restaurants`.
class ApiRestaurantRepository implements RestaurantRepository {
  ApiRestaurantRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Restaurant>> fetchRestaurants() async {
    final data =
        await _api.get('/api/restaurants', auth: false) as List<dynamic>;
    return data
        .map(
          (e) => restaurantFromJson(
            e as Map<String, dynamic>,
            resolveMediaUrl: _api.resolveMediaUrl,
          ),
        )
        .toList(growable: false);
  }
}

/// The API stores only coordinates; the distance shown in the app is worked
/// out here, from the resort's own pin.
Restaurant restaurantFromJson(
  Map<String, dynamic> json, {
  required String Function(String url) resolveMediaUrl,
}) {
  final lat = (json['latitude'] as num).toDouble();
  final lng = (json['longitude'] as num).toDouble();
  return Restaurant(
    id: json['id'] as String,
    name: json['name'] as String,
    cuisine: json['cuisine'] as String,
    rating: (json['rating'] as num).toDouble(),
    priceRange: json['priceRange'] as String,
    description: json['description'] as String,
    imageUrl: resolveMediaUrl(json['imageUrl'] as String),
    address: json['address'] as String,
    latitude: lat,
    longitude: lng,
    distanceKm: _kmFromResort(lat, lng),
  );
}

/// Straight-line (haversine) distance. That is what "x away" means on a
/// listing; a road distance would need a routing API.
double _kmFromResort(double lat, double lng) {
  const earthRadiusKm = 6371.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat - AppConfig.hotelLat);
  final dLng = rad(lng - AppConfig.hotelLng);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(AppConfig.hotelLat)) *
          math.cos(rad(lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
