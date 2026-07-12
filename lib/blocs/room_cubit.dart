import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../data/mock_data.dart';
import '../models/room.dart';

/// Filters that drive the real-time room search.
class RoomFilter {
  final DateTime? checkIn;
  final DateTime? checkOut;
  final Set<RoomType> types;
  final double minPrice;
  final double maxPrice;
  final int guests;
  final String query;

  const RoomFilter({
    this.checkIn,
    this.checkOut,
    this.types = const {},
    this.minPrice = 0,
    this.maxPrice = 10000,
    this.guests = 1,
    this.query = '',
  });

  RoomFilter copyWith({
    DateTime? checkIn,
    DateTime? checkOut,
    Set<RoomType>? types,
    double? minPrice,
    double? maxPrice,
    int? guests,
    String? query,
  }) {
    return RoomFilter(
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      types: types ?? this.types,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      guests: guests ?? this.guests,
      query: query ?? this.query,
    );
  }
}

class RoomState {
  RoomState();
}

class RoomCubit extends Cubit<RoomState> {
  RoomCubit() : super(RoomState());

  final List<Room> _rooms = MockData.rooms();

  List<Room> get allRooms => List.unmodifiable(_rooms);

  /// Lowest and highest nightly prices, used to seed the price slider.
  double get minRoomPrice => _rooms.isEmpty
      ? 0
      : _rooms.map((r) => r.pricePerNight).reduce((a, b) => a < b ? a : b);
  double get maxRoomPrice => _rooms.isEmpty
      ? 10000
      : _rooms.map((r) => r.pricePerNight).reduce((a, b) => a > b ? a : b);

  Room? byId(String id) {
    final match = _rooms.where((r) => r.id == id);
    return match.isEmpty ? null : match.first;
  }

  /// Real-time search. [isRoomBooked] lets the booking cubit exclude rooms
  /// that are already reserved for the requested dates.
  List<Room> search(
    RoomFilter filter, {
    bool Function(String roomId, DateTime checkIn, DateTime checkOut)?
        isRoomBooked,
  }) {
    return _rooms.where((room) {
      if (room.status != RoomStatus.available) return false;
      if (filter.types.isNotEmpty && !filter.types.contains(room.type)) {
        return false;
      }
      if (room.pricePerNight < filter.minPrice ||
          room.pricePerNight > filter.maxPrice) {
        return false;
      }
      if (room.capacity < filter.guests) return false;
      if (filter.query.isNotEmpty &&
          !room.name.toLowerCase().contains(filter.query.toLowerCase())) {
        return false;
      }
      if (filter.checkIn != null &&
          filter.checkOut != null &&
          isRoomBooked != null &&
          isRoomBooked(room.id, filter.checkIn!, filter.checkOut!)) {
        return false;
      }
      return true;
    }).toList();
  }

  // ---- Admin operations -------------------------------------------------

  void addRoom({
    required String name,
    required RoomType type,
    required double pricePerNight,
    required int capacity,
    required String description,
    required List<String> imageUrls,
    required List<String> amenities,
  }) {
    _rooms.add(Room(
      id: const Uuid().v4(),
      name: name,
      type: type,
      pricePerNight: pricePerNight,
      capacity: capacity,
      description: description,
      imageUrls: imageUrls.isEmpty
          ? const [
              'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800'
            ]
          : imageUrls,
      amenities: amenities,
    ));
    emit(RoomState());
  }

  void updateRoom(Room room) {
    final i = _rooms.indexWhere((r) => r.id == room.id);
    if (i != -1) {
      _rooms[i] = room;
      emit(RoomState());
    }
  }

  void updatePrice(String id, double price) {
    final room = byId(id);
    if (room != null) {
      room.pricePerNight = price;
      emit(RoomState());
    }
  }

  void setStatus(String id, RoomStatus status) {
    final room = byId(id);
    if (room != null) {
      room.status = status;
      emit(RoomState());
    }
  }

  void removeRoom(String id) {
    _rooms.removeWhere((r) => r.id == id);
    emit(RoomState());
  }
}
