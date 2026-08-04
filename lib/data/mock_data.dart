import '../models/booking.dart';
import '../models/restaurant.dart';
import '../models/room.dart';
import '../models/user.dart';

/// Seed data that stands in for a backend. Providers load from here on startup
/// and then mutate their in-memory copies. Swap these out for API calls to go
/// live without touching the UI layer.
class MockData {
  MockData._();

  static List<AppUser> users() => [
    const AppUser(
      id: 'u-admin',
      name: 'System Admin',
      email: 'admin@hotel.com',
      phone: '+66800000001',
      password: 'admin123',
      role: UserRole.admin,
    ),
    const AppUser(
      id: 'u-staff',
      name: 'Front Desk Staff',
      email: 'staff@hotel.com',
      phone: '+66800000002',
      password: 'staff123',
      role: UserRole.staff,
    ),
    const AppUser(
      id: 'u-cust',
      name: 'Jane Customer',
      email: 'customer@hotel.com',
      phone: '+66800000003',
      password: 'customer123',
      role: UserRole.customer,
    ),
  ];

  static List<Room> rooms() => [
    Room(
      id: 'r-101',
      name: 'P1',
      type: RoomType.standard,
      pricePerNight: 650,
      capacity: 2,
      description:
          'Spacious deluxe room with a private balcony overlooking the bay '
          'and a king-size bed.',
      imageUrls: const ['image/P2.jpg', 'image/single_bed.jpg'],
      amenities: const ['Wi-Fi', 'Air conditioning', 'TV', 'Mini fridge', 'Coffee'],
    ),
    Room(
      id: 'r-205',
      name: 'P2',
      type: RoomType.deluxe,
      pricePerNight: 650,
      capacity: 2,
      description:
          'Spacious deluxe room with a private balcony overlooking the bay '
          'and a king-size bed.',
      imageUrls: const ['image/single_bed.jpg', 'image/P2.jpg'],
      amenities: const [
        'Wi-Fi',
        'Air conditioning',
        'TV',
        'Coffee',
      ],
    ),
    Room(
      id: 'r-310',
      name: 'P3',
      type: RoomType.suite,
      pricePerNight: 650,
      capacity: 2,
      description:
          'Luxurious suite with a separate living area, premium amenities '
          'and panoramic sea views.',
      imageUrls: const ['image/twin_bed.jpg', 'image/P3.jpg'],
      amenities: const [
        'Wi-Fi',
        'Air conditioning',
        'TV',
        'Two beds',
        'Coffee',
      ],
    ),
    Room(
      id: 'r-402',
      name: 'P4',
      type: RoomType.family,
      pricePerNight: 650,
      capacity: 2,
      description:
          'Perfect for families: two queen beds, extra space, and '
          'kid-friendly amenities.',
      imageUrls: const ['image/twin_bed2.jpg', 'image/P4.jpg'],
      amenities: const [
        'Wi-Fi',
        'Air conditioning',
        'TV',
        'Two beds',
        'Coffee',
      ],
    ),
    Room(
      id: 'r-f1',
      name: 'F1',
      type: RoomType.standard,
      pricePerNight: 650,
      capacity: 2,
      description:
          'Comfortable twin room ideal for friends or colleagues '
          'travelling together.',
      imageUrls: const ['image/A_set1.jpg', 'image/F1.jpg'],
      amenities: const ['Wi-Fi', 'Air conditioning', 'TV', 'Coffee'],
      status: RoomStatus.available,
    ),
    Room(
      id: 'r-f2',
      name: 'F2',
      type: RoomType.standard,
      pricePerNight: 650,
      capacity: 2,
      description:
          'Comfortable twin room ideal for friends or colleagues '
          'travelling together.',
      imageUrls: const ['image/A_set1.jpg', 'image/F2.jpg'],
      amenities: const ['Wi-Fi', 'Air conditioning', 'TV', 'Coffee'],
      status: RoomStatus.maintenance,
    )
  ];

  static List<Restaurant> restaurants() => const [
    Restaurant(
      id: 'res-1',
      name: 'The Salt Pier',
      cuisine: 'Seafood',
      rating: 4.7,
      priceRange: '฿฿฿',
      description: 'Fresh-off-the-boat seafood served right on the waterfront.',
      imageUrl:
          'https://images.unsplash.com/photo-1559339352-11d035aa65de?w=800',
      address: '12 Beach Road, Pattaya',
      latitude: 12.9301,
      longitude: 100.8801,
      distanceKm: 0.4,
    ),
    Restaurant(
      id: 'res-2',
      name: 'Baan Thai Kitchen',
      cuisine: 'Thai',
      rating: 4.5,
      priceRange: '฿฿',
      description: 'Authentic home-style Thai dishes and famous green curry.',
      imageUrl:
          'https://images.unsplash.com/photo-1455619452474-d2be8b1e70cd?w=800',
      address: '88 Soi 7, Pattaya',
      latitude: 12.9250,
      longitude: 100.8745,
      distanceKm: 0.8,
    ),
    Restaurant(
      id: 'res-3',
      name: 'Bella Napoli',
      cuisine: 'Italian',
      rating: 4.6,
      priceRange: '฿฿฿',
      description: 'Wood-fired pizza and handmade pasta by an Italian chef.',
      imageUrl:
          'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
      address: '45 Second Road, Pattaya',
      latitude: 12.9320,
      longitude: 100.8830,
      distanceKm: 1.1,
    ),
    Restaurant(
      id: 'res-4',
      name: 'Sakura Sushi Bar',
      cuisine: 'Japanese',
      rating: 4.4,
      priceRange: '฿฿',
      description: 'Fresh sushi, ramen and a cozy izakaya atmosphere.',
      imageUrl:
          'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=800',
      address: '210 Beach Road, Pattaya',
      latitude: 12.9189,
      longitude: 100.8760,
      distanceKm: 1.5,
    ),
  ];

  static List<Booking> bookings() {
    final now = DateTime.now();
    return [
      Booking(
        id: 'b-1001',
        roomId: 'r-205',
        roomName: 'Deluxe Sea View 205',
        customerId: 'u-cust',
        customerName: 'Jane Customer',
        checkIn: DateTime(now.year, now.month, now.day + 3),
        checkOut: DateTime(now.year, now.month, now.day + 6),
        guests: 2,
        totalPrice: 1950,
        status: BookingStatus.approved,
        paymentStatus: PaymentStatus.paid,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      Booking(
        id: 'b-1002',
        roomId: 'r-310',
        roomName: 'Executive Suite 310',
        customerId: 'u-cust',
        customerName: 'Jane Customer',
        checkIn: DateTime(now.year, now.month, now.day + 10),
        checkOut: DateTime(now.year, now.month, now.day + 12),
        guests: 2,
        totalPrice: 2600,
        status: BookingStatus.pending,
        paymentStatus: PaymentStatus.paid,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
    ];
  }
}
