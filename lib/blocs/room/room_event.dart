import '../../models/room.dart';

abstract class RoomEvent {
  const RoomEvent();
}

class RoomStarted extends RoomEvent {
  const RoomStarted();
}

class RoomAddRequested extends RoomEvent {
  final String name;
  final RoomType type;
  final double pricePerNight;
  final int capacity;
  final String description;
  final List<String> imageUrls;
  final List<String> amenities;

  const RoomAddRequested({
    required this.name,
    required this.type,
    required this.pricePerNight,
    required this.capacity,
    required this.description,
    required this.imageUrls,
    required this.amenities,
  });
}

class RoomUpdateRequested extends RoomEvent {
  final Room room;
  const RoomUpdateRequested(this.room);
}

class RoomUpdatePriceRequested extends RoomEvent {
  final String id;
  final double price;
  const RoomUpdatePriceRequested(this.id, this.price);
}

class RoomSetStatusRequested extends RoomEvent {
  final String id;
  final RoomStatus status;
  const RoomSetStatusRequested(this.id, this.status);
}

class RoomRemoveRequested extends RoomEvent {
  final String id;
  const RoomRemoveRequested(this.id);
}
