import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../models/room.dart';
import '../repository_exception.dart';
import '../room_repository.dart';

/// Fallback image used when a newly created room has no photo yet.
const _placeholderImage =
    'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800';

class MockRoomRepository implements RoomRepository {
  MockRoomRepository() : _rooms = MockData.rooms();

  final List<Room> _rooms;

  @override
  Future<List<Room>> fetchRooms() async => List.unmodifiable(_rooms);

  @override
  Future<List<BookedRange>> fetchBookedRanges({DateTime? from, DateTime? to}) async =>
      const [];

  @override
  Future<Room> createRoom({
    required String name,
    required RoomType type,
    required double pricePerNight,
    required int capacity,
    required String description,
    required List<String> imageUrls,
    required List<String> amenities,
  }) async {
    final room = Room(
      id: const Uuid().v4(),
      name: name,
      type: type,
      pricePerNight: pricePerNight,
      capacity: capacity,
      description: description,
      imageUrls: imageUrls.isEmpty ? const [_placeholderImage] : imageUrls,
      amenities: amenities,
    );
    _rooms.add(room);
    return room;
  }

  @override
  Future<Room> updateRoom(Room room) async {
    final i = _indexOf(room.id);
    _rooms[i] = room;
    return room;
  }

  @override
  Future<Room> updatePrice(String id, double pricePerNight) async {
    final room = _rooms[_indexOf(id)];
    room.pricePerNight = pricePerNight;
    return room;
  }

  @override
  Future<Room> updateStatus(String id, RoomStatus status) async {
    final room = _rooms[_indexOf(id)];
    room.status = status;
    return room;
  }

  @override
  Future<void> deleteRoom(String id) async {
    _rooms.removeWhere((r) => r.id == id);
  }

  int _indexOf(String id) {
    final i = _rooms.indexWhere((r) => r.id == id);
    if (i == -1) throw const RepositoryException('Room not found.');
    return i;
  }
}
