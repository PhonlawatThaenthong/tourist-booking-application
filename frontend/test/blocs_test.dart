import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hotel_booking/blocs/auth/auth_bloc.dart';
import 'package:hotel_booking/blocs/auth/auth_event.dart';
import 'package:hotel_booking/blocs/auth/auth_state.dart';
import 'package:hotel_booking/blocs/room/room_bloc.dart';
import 'package:hotel_booking/blocs/room/room_event.dart';
import 'package:hotel_booking/models/room.dart';
import 'package:hotel_booking/models/user.dart';
import 'package:hotel_booking/repositories/mock/mock_auth_repository.dart';
import 'package:hotel_booking/repositories/mock/mock_room_repository.dart';
import 'package:hotel_booking/repositories/repository_exception.dart';

/// Room search uses its own fixed data (not lib/data/mock_data.dart) so that
/// editing the demo seed never breaks these tests.
class _FixedRooms extends MockRoomRepository {
  _FixedRooms(this.rooms, this.ranges);
  final List<Room> rooms;
  final List<BookedRange> ranges;

  @override
  Future<List<Room>> fetchRooms() async => rooms;

  @override
  Future<List<BookedRange>> fetchBookedRanges({DateTime? from, DateTime? to}) async => ranges;
}

class _FailingRooms extends MockRoomRepository {
  @override
  Future<List<Room>> fetchRooms() async =>
      throw const RepositoryException('ติดต่อเซิร์ฟเวอร์ไม่ได้');
}

/// Auth without the mock's simulated 400 ms latency, with one known user.
class _FastAuth extends MockAuthRepository {
  static const alice = AppUser(
    id: 'u-alice',
    name: 'Alice',
    email: 'alice@example.com',
    phone: '',
    password: 'password123',
    role: UserRole.customer,
  );

  @override
  Future<AppUser> login({required String email, required String password}) async {
    if (email.trim().toLowerCase() == alice.email && password == alice.password) {
      await persistSession(alice);
      return alice;
    }
    throw const AuthException('Invalid email or password.');
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    if (email.toLowerCase() == alice.email) {
      throw const RepositoryException('อีเมลนี้ถูกใช้งานแล้ว', statusCode: 409);
    }
    return AppUser(
      id: 'u-new', name: name, email: email, phone: phone,
      password: '', role: UserRole.customer,
    );
  }

  @override
  Future<AppUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('logged_in_user_id') == alice.id ? alice : null;
  }

  @override
  Future<List<AppUser>> listUsers() async => const [alice];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ------------------------------------------------------------------ rooms

  group('RoomBloc search', () {
    Room room(String id, String name, RoomType type,
            {RoomStatus status = RoomStatus.available}) =>
        Room(
          id: id, name: name, type: type, pricePerNight: 1000, capacity: 2,
          description: '', imageUrls: const [], amenities: const [], status: status,
        );

    final rooms = [
      room('s1', 'Sea Single', RoomType.single),
      room('s2', 'Garden Single', RoomType.single),
      room('t1', 'Sea Twin', RoomType.twin),
      room('m1', 'Broken Twin', RoomType.twin, status: RoomStatus.maintenance),
    ];
    // s1 is taken 10–13 May.
    final ranges = [
      BookedRange(roomId: 's1', checkIn: DateTime(2026, 5, 10), checkOut: DateTime(2026, 5, 13)),
    ];

    Future<RoomBloc> loaded() async {
      final bloc = RoomBloc(_FixedRooms(rooms, ranges))..add(const RoomStarted());
      await bloc.stream.firstWhere((s) => s.rooms.isNotEmpty);
      return bloc;
    }

    List<String> ids(List<Room> r) => r.map((e) => e.id).toList();

    test('rooms under maintenance never appear', () async {
      final bloc = await loaded();
      expect(ids(bloc.search(const RoomFilter())), ['s1', 's2', 't1']);
      await bloc.close();
    });

    test('filters by room type', () async {
      final bloc = await loaded();
      expect(ids(bloc.search(const RoomFilter(types: {RoomType.twin}))), ['t1']);
      expect(
        ids(bloc.search(const RoomFilter(types: {RoomType.single, RoomType.twin}))),
        ['s1', 's2', 't1'],
      );
      await bloc.close();
    });

    test('text search is case-insensitive on the room name', () async {
      final bloc = await loaded();
      expect(ids(bloc.search(const RoomFilter(query: 'sea'))), ['s1', 't1']);
      expect(ids(bloc.search(const RoomFilter(query: 'GARDEN'))), ['s2']);
      expect(bloc.search(const RoomFilter(query: 'nothing')), isEmpty);
      await bloc.close();
    });

    test('rooms booked by anyone for the chosen dates are hidden', () async {
      final bloc = await loaded();
      final filter = RoomFilter(checkIn: DateTime(2026, 5, 11), checkOut: DateTime(2026, 5, 12));
      expect(ids(bloc.search(filter, isRoomBooked: bloc.isRoomBooked)), ['s2', 't1']);
      await bloc.close();
    });

    test('arriving on the day a guest leaves is allowed', () async {
      final bloc = await loaded();
      expect(bloc.isRoomBooked('s1', DateTime(2026, 5, 13), DateTime(2026, 5, 15)), isFalse);
      expect(bloc.isRoomBooked('s1', DateTime(2026, 5, 12), DateTime(2026, 5, 15)), isTrue);
      expect(bloc.isRoomBooked('s2', DateTime(2026, 5, 10), DateTime(2026, 5, 13)), isFalse);
      await bloc.close();
    });

    test('calendar shows a room as booked on its nights, not its check-out day', () async {
      final bloc = await loaded();
      expect(bloc.bookedRoomIdsOn(DateTime(2026, 5, 10, 18)), {'s1'}); // time ignored
      expect(bloc.bookedRoomIdsOn(DateTime(2026, 5, 12)), {'s1'});
      expect(bloc.bookedRoomIdsOn(DateTime(2026, 5, 13)), isEmpty);
      await bloc.close();
    });

    test('byId finds a room or returns null', () async {
      final bloc = await loaded();
      expect(bloc.byId('t1')?.name, 'Sea Twin');
      expect(bloc.byId('nope'), isNull);
      await bloc.close();
    });

    test('a load failure is reported, not thrown', () async {
      final bloc = RoomBloc(_FailingRooms())..add(const RoomStarted());
      final state = await bloc.stream.first;
      expect(state.errorMessage, 'ติดต่อเซิร์ฟเวอร์ไม่ได้');
      expect(state.rooms, isEmpty);
      await bloc.close();
    });
  });

  // ------------------------------------------------------------------- auth

  group('AuthBloc', () {
    test('a fresh install starts signed out', () async {
      final bloc = AuthBloc(_FastAuth())..add(const AuthStarted());
      final s = await bloc.stream.first;
      expect(s.initialised, isTrue);
      expect(s.status, AuthStatus.unauthenticated);
      expect(s.currentUser, isNull);
      await bloc.close();
    });

    test('a remembered session is restored on start', () async {
      SharedPreferences.setMockInitialValues({'logged_in_user_id': 'u-alice'});
      final bloc = AuthBloc(_FastAuth())..add(const AuthStarted());
      final s = await bloc.stream.first;
      expect(s.status, AuthStatus.authenticated);
      expect(s.currentUser?.id, 'u-alice');
      await bloc.close();
    });

    test('login goes authenticating → authenticated', () async {
      final bloc = AuthBloc(_FastAuth());
      final states = bloc.stream.take(2).toList();
      bloc.add(const AuthLoginRequested('ALICE@example.com', 'password123'));
      final s = await states;
      expect(s[0].status, AuthStatus.authenticating);
      expect(s[1].status, AuthStatus.authenticated);
      expect(s[1].currentUser?.email, 'alice@example.com');
      await bloc.close();
    });

    test('wrong password ends in failure with a message and no user', () async {
      final bloc = AuthBloc(_FastAuth());
      final states = bloc.stream.take(2).toList();
      bloc.add(const AuthLoginRequested('alice@example.com', 'nope'));
      final s = (await states).last;
      expect(s.status, AuthStatus.failure);
      expect(s.errorMessage, 'Invalid email or password.');
      expect(s.currentUser, isNull);
      await bloc.close();
    });

    test('registering a taken email fails with the server message', () async {
      final bloc = AuthBloc(_FastAuth());
      final states = bloc.stream.take(2).toList();
      bloc.add(const AuthRegisterRequested(
        name: 'Dup', email: 'alice@example.com', phone: '', password: 'password123',
      ));
      final s = (await states).last;
      expect(s.status, AuthStatus.failure);
      expect(s.errorMessage, 'อีเมลนี้ถูกใช้งานแล้ว');
      await bloc.close();
    });

    test('a successful registration signs the new user in', () async {
      final bloc = AuthBloc(_FastAuth());
      final states = bloc.stream.take(2).toList();
      bloc.add(const AuthRegisterRequested(
        name: 'Bob', email: 'bob@example.com', phone: '0812345678', password: 'password123',
      ));
      final s = (await states).last;
      expect(s.status, AuthStatus.authenticated);
      expect(s.currentUser?.email, 'bob@example.com');
      expect(s.currentUser?.role, UserRole.customer);
      await bloc.close();
    });

    test('logout clears the user and the remembered session', () async {
      final bloc = AuthBloc(_FastAuth());
      bloc.add(const AuthLoginRequested('alice@example.com', 'password123'));
      await bloc.stream.firstWhere((s) => s.status == AuthStatus.authenticated);

      bloc.add(const AuthLogoutRequested());
      final s = await bloc.stream.first;
      expect(s.status, AuthStatus.unauthenticated);
      expect(s.currentUser, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('logged_in_user_id'), isNull);
      await bloc.close();
    });

    test('an admin cannot delete their own account', () async {
      final bloc = AuthBloc(_FastAuth());
      bloc.add(const AuthLoginRequested('alice@example.com', 'password123'));
      await bloc.stream.firstWhere((s) => s.status == AuthStatus.authenticated);

      bloc.add(const AuthStaffDeleteRequested('u-alice'));
      final s = await bloc.stream.first;
      expect(s.errorMessage, 'You cannot delete your own account.');
      expect(s.users.any((u) => u.id == 'u-alice'), isTrue);
      await bloc.close();
    });
  });
}
