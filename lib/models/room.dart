enum RoomType { standard, deluxe, suite, family }

extension RoomTypeX on RoomType {
  String get label {
    switch (this) {
      case RoomType.standard:
        return 'Standard';
      case RoomType.deluxe:
        return 'Deluxe';
      case RoomType.suite:
        return 'Suite';
      case RoomType.family:
        return 'Family';
    }
  }
}

/// Operational status of a room set by staff. Only [available] rooms can be
/// booked by customers; [maintenance] rooms are hidden from search.
enum RoomStatus { available, maintenance }

extension RoomStatusX on RoomStatus {
  String get label =>
      this == RoomStatus.available ? 'Available' : 'Under maintenance';
}

class Room {
  final String id;
  String name;
  RoomType type;
  double pricePerNight;
  int capacity;
  String description;
  List<String> imageUrls;
  List<String> amenities;
  RoomStatus status;

  Room({
    required this.id,
    required this.name,
    required this.type,
    required this.pricePerNight,
    required this.capacity,
    required this.description,
    required this.imageUrls,
    required this.amenities,
    this.status = RoomStatus.available,
  });

  String get primaryImage =>
      imageUrls.isNotEmpty ? imageUrls.first : '';
}
