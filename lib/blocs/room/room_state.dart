import '../../models/room.dart';

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
  final List<Room> rooms;
  const RoomState({this.rooms = const []});

  RoomState copyWith({List<Room>? rooms}) {
    return RoomState(rooms: rooms ?? this.rooms);
  }
}
