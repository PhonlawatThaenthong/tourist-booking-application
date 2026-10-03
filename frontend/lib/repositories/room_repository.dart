import 'dart:typed_data';

import '../models/room.dart';

/// Data access for rooms. Backend: `/api/rooms` and `/api/staff/rooms`.
abstract class RoomRepository {
  /// Backend: `GET /api/rooms`.
  Future<List<Room>> fetchRooms();

  /// Backend: `GET /api/rooms/availability?from=&to=`. Anonymised booked
  /// date-ranges across all customers, for client-side availability.
  Future<List<BookedRange>> fetchBookedRanges({DateTime? from, DateTime? to});

  /// Backend: `POST /api/staff/rooms`.
  Future<Room> createRoom({
    required String name,
    required RoomType type,
    required double pricePerNight,
    required int capacity,
    required String description,
    required List<String> imageUrls,
    required List<String> amenities,
  });

  /// Backend: `PATCH /api/staff/rooms/:id` — full replacement.
  Future<Room> updateRoom(Room room);

  /// Backend: `PATCH /api/staff/rooms/:id` — price only.
  Future<Room> updatePrice(String id, double pricePerNight);

  /// Backend: `PATCH /api/staff/rooms/:id` — availability/maintenance.
  Future<Room> updateStatus(String id, RoomStatus status);

  /// Backend: `POST /api/staff/rooms/:id/images`. Uploads one photo and
  /// returns the room with it appended to [Room.imageUrls].
  Future<Room> addRoomPhoto(
    String roomId, {
    required Uint8List bytes,
    required String filename,
  });

  /// Backend: `DELETE /api/staff/rooms/:id`.
  Future<void> deleteRoom(String id);
}
