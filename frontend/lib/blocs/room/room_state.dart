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

  /// Anonymised booked date-ranges across all customers (for availability).
  final List<BookedRange> bookedRanges;

  /// Transient: set on the failing transition only, never carried forward.
  final String? errorMessage;

  const RoomState({
    this.rooms = const [],
    this.bookedRanges = const [],
    this.errorMessage,
  });

  RoomState copyWith({
    List<Room>? rooms,
    List<BookedRange>? bookedRanges,
    String? errorMessage,
  }) {
    return RoomState(
      rooms: rooms ?? this.rooms,
      bookedRanges: bookedRanges ?? this.bookedRanges,
      errorMessage: errorMessage,
    );
  }
}
