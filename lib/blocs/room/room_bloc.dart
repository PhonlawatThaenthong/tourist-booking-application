import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../models/room.dart';
import 'room_event.dart';
import 'room_state.dart';

export 'room_state.dart' show RoomFilter;

class RoomBloc extends Bloc<RoomEvent, RoomState> {
  RoomBloc() : super(const RoomState()) {
    on<RoomStarted>(_onStarted);
    on<RoomAddRequested>(_onAddRequested);
    on<RoomUpdateRequested>(_onUpdateRequested);
    on<RoomUpdatePriceRequested>(_onUpdatePriceRequested);
    on<RoomSetStatusRequested>(_onSetStatusRequested);
    on<RoomRemoveRequested>(_onRemoveRequested);
  }

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

  /// Real-time search. [isRoomBooked] lets the booking bloc exclude rooms
  /// that are already reserved for the requested dates.
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

  void _onStarted(RoomStarted event, Emitter<RoomState> emit) {
    emit(state.copyWith(rooms: MockData.rooms()));
  }

  void _onAddRequested(RoomAddRequested event, Emitter<RoomState> emit) {
    final room = Room(
      id: const Uuid().v4(),
      name: event.name,
      type: event.type,
      pricePerNight: event.pricePerNight,
      capacity: event.capacity,
      description: event.description,
      imageUrls: event.imageUrls.isEmpty
          ? const [
              'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800'
            ]
          : event.imageUrls,
      amenities: event.amenities,
    );
    emit(state.copyWith(rooms: [...state.rooms, room]));
  }

  void _onUpdateRequested(RoomUpdateRequested event, Emitter<RoomState> emit) {
    final i = state.rooms.indexWhere((r) => r.id == event.room.id);
    if (i == -1) return;
    final rooms = [...state.rooms];
    rooms[i] = event.room;
    emit(state.copyWith(rooms: rooms));
  }

  void _onUpdatePriceRequested(
    RoomUpdatePriceRequested event,
    Emitter<RoomState> emit,
  ) {
    final room = byId(event.id);
    if (room == null) return;
    room.pricePerNight = event.price;
    emit(state.copyWith(rooms: [...state.rooms]));
  }

  void _onSetStatusRequested(
    RoomSetStatusRequested event,
    Emitter<RoomState> emit,
  ) {
    final room = byId(event.id);
    if (room == null) return;
    room.status = event.status;
    emit(state.copyWith(rooms: [...state.rooms]));
  }

  void _onRemoveRequested(RoomRemoveRequested event, Emitter<RoomState> emit) {
    emit(state.copyWith(
      rooms: state.rooms.where((r) => r.id != event.id).toList(),
    ));
  }
}
