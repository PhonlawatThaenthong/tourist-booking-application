import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/room.dart';
import '../../repositories/repository_exception.dart';
import '../../repositories/room_repository.dart';
import 'room_event.dart';
import 'room_state.dart';

export 'room_state.dart' show RoomFilter;

class RoomBloc extends Bloc<RoomEvent, RoomState> {
  RoomBloc(this._repository) : super(const RoomState()) {
    on<RoomStarted>(_onStarted);
    on<RoomAddRequested>(_onAddRequested);
    on<RoomUpdateRequested>(_onUpdateRequested);
    on<RoomUpdatePriceRequested>(_onUpdatePriceRequested);
    on<RoomSetStatusRequested>(_onSetStatusRequested);
    on<RoomRemoveRequested>(_onRemoveRequested);
  }

  final RoomRepository _repository;

  List<Room> get allRooms => List.unmodifiable(state.rooms);

  /// Lowest and highest nightly prices, used to seed the price slider.
  double get minRoomPrice => state.rooms.isEmpty
      ? 0
      : state.rooms.map((r) => r.pricePerNight).reduce((a, b) => a < b ? a : b);
  double get maxRoomPrice => state.rooms.isEmpty
      ? 10000
      : state.rooms.map((r) => r.pricePerNight).reduce((a, b) => a > b ? a : b);

  Room? byId(String id) {
    final match = state.rooms.where((r) => r.id == id);
    return match.isEmpty ? null : match.first;
  }

  /// Availability across ALL customers, computed from the anonymised booked
  /// ranges — replaces the old client-side check that only saw own bookings.
  bool isRoomBooked(String roomId, DateTime checkIn, DateTime checkOut) {
    return state.bookedRanges.any(
      (r) => r.roomId == roomId && r.overlaps(checkIn, checkOut),
    );
  }

  /// Room ids that are booked on [day] (for the month calendar).
  Set<String> bookedRoomIdsOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return state.bookedRanges
        .where((r) => r.covers(d))
        .map((r) => r.roomId)
        .toSet();
  }

  /// Real-time search. [isRoomBooked] lets the booking bloc exclude rooms
  /// that are already reserved for the requested dates.
  ///
  /// Runs client-side against the loaded list. In Phase 3 this moves to the
  /// server (`GET /api/rooms?checkIn=&checkOut=&...`) and the same filter
  /// object becomes the query string.
  List<Room> search(
    RoomFilter filter, {
    bool Function(String roomId, DateTime checkIn, DateTime checkOut)?
        isRoomBooked,
  }) {
    return state.rooms.where((room) {
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

  Future<void> _onStarted(RoomStarted event, Emitter<RoomState> emit) async {
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
      final to = from.add(const Duration(days: 400));
      final rooms = await _repository.fetchRooms();
      final ranges = await _repository.fetchBookedRanges(from: from, to: to);
      emit(state.copyWith(rooms: rooms, bookedRanges: ranges));
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onAddRequested(
    RoomAddRequested event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final room = await _repository.createRoom(
        name: event.name,
        type: event.type,
        pricePerNight: event.pricePerNight,
        capacity: event.capacity,
        description: event.description,
        imageUrls: event.imageUrls,
        amenities: event.amenities,
      );
      emit(state.copyWith(rooms: [...state.rooms, room]));
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onUpdateRequested(
    RoomUpdateRequested event,
    Emitter<RoomState> emit,
  ) async {
    try {
      final updated = await _repository.updateRoom(event.room);
      _replace(updated, emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onUpdatePriceRequested(
    RoomUpdatePriceRequested event,
    Emitter<RoomState> emit,
  ) async {
    try {
      _replace(await _repository.updatePrice(event.id, event.price), emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onSetStatusRequested(
    RoomSetStatusRequested event,
    Emitter<RoomState> emit,
  ) async {
    try {
      _replace(await _repository.updateStatus(event.id, event.status), emit);
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  Future<void> _onRemoveRequested(
    RoomRemoveRequested event,
    Emitter<RoomState> emit,
  ) async {
    try {
      await _repository.deleteRoom(event.id);
      emit(state.copyWith(
        rooms: state.rooms.where((r) => r.id != event.id).toList(),
      ));
    } on RepositoryException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  void _replace(Room room, Emitter<RoomState> emit) {
    final i = state.rooms.indexWhere((r) => r.id == room.id);
    if (i == -1) return;
    final rooms = [...state.rooms];
    rooms[i] = room;
    emit(state.copyWith(rooms: rooms));
  }
}
