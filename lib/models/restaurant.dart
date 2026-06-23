class Restaurant {
  final String id;
  final String name;
  final String cuisine;
  final double rating;
  final String priceRange; // e.g. "฿฿"
  final String description;
  final String imageUrl;
  final String address;
  final double latitude;
  final double longitude;
  final double distanceKm;

  const Restaurant({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.rating,
    required this.priceRange,
    required this.description,
    required this.imageUrl,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
  });
}
