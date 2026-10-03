import 'dart:typed_data';

import '../../models/room.dart';

/// A photo picked in the room form, not yet on the server. Held as bytes
/// rather than a device path: a path means nothing on any other device.
class PendingPhoto {
  final Uint8List bytes;
  final String filename;
  const PendingPhoto(this.bytes, this.filename);
}

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

  /// Uploaded once the room exists, and appended after [imageUrls].
  final List<PendingPhoto> newPhotos;

  const RoomAddRequested({
    required this.name,
    required this.type,
    required this.pricePerNight,
    required this.capacity,
    required this.description,
    required this.imageUrls,
    required this.amenities,
    this.newPhotos = const [],
  });
}

class RoomUpdateRequested extends RoomEvent {
  final Room room;

  /// Uploaded after the update, and appended to the room's photos.
  final List<PendingPhoto> newPhotos;

  const RoomUpdateRequested(this.room, {this.newPhotos = const []});
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
