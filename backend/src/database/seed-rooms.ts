import 'reflect-metadata';
import dataSourceInstance from '../config/data-source';
import { Room, RoomStatus, RoomType } from '../modules/rooms/room.entity';

/**
 * Populates `rooms` from the same catalogue the Flutter app used to load out
 * of `frontend/lib/data/mock_data.dart` before it switched to the API — see
 * Sprint 2 step 5 in docs/database-schema.md. Image paths are kept exactly as
 * they were (`image/P2.jpg`, ...): those are Flutter assets bundled in the
 * app (see `frontend/lib/widgets/app_image.dart`), not URLs the backend
 * serves, so the seed must not rewrite them.
 *
 * Matched by `name` and safe to run more than once: a room whose name already
 * exists is left untouched rather than duplicated.
 *
 * Usage: npm run seed:rooms
 */
const ROOMS: Array<{
  name: string;
  type: RoomType;
  pricePerNight: number;
  capacity: number;
  description: string;
  imageUrls: string[];
  amenities: string[];
  status?: RoomStatus;
}> = [
  {
    name: 'P1',
    type: RoomType.SINGLE,
    pricePerNight: 650,
    capacity: 2,
    description: 'Single bedroom with a king-size bed.',
    imageUrls: ['image/P2.jpg', 'image/single_bed.jpg'],
    amenities: ['Wi-Fi', 'Air conditioning', 'TV', 'Mini fridge', 'Coffee'],
  },
  {
    name: 'P2',
    type: RoomType.SINGLE,
    pricePerNight: 650,
    capacity: 2,
    description: 'Single bedroom with a king-size bed.',
    imageUrls: ['image/single_bed.jpg', 'image/P2.jpg'],
    amenities: ['Wi-Fi', 'Air conditioning', 'TV', 'Coffee'],
  },
  {
    name: 'P3',
    type: RoomType.TWIN,
    pricePerNight: 650,
    capacity: 2,
    description: 'Twin bedroom with twin beds.',
    imageUrls: ['image/twin_bed.jpg', 'image/P3.jpg'],
    amenities: ['Wi-Fi', 'Air conditioning', 'TV', 'Two beds', 'Coffee'],
  },
  {
    name: 'P4',
    type: RoomType.TWIN,
    pricePerNight: 650,
    capacity: 2,
    description: 'Twin bedroom with twin beds.',
    imageUrls: ['image/twin_bed2.jpg', 'image/P4.jpg'],
    amenities: ['Wi-Fi', 'Air conditioning', 'TV', 'Two beds', 'Coffee'],
  },
  {
    name: 'F1',
    type: RoomType.SINGLE,
    pricePerNight: 650,
    capacity: 2,
    description: 'Single bedroom with a king-size bed.',
    imageUrls: ['image/A_set1.jpg', 'image/F1.jpg'],
    amenities: ['Wi-Fi', 'Air conditioning', 'TV', 'Coffee'],
    status: RoomStatus.AVAILABLE,
  },
  {
    name: 'F2',
    type: RoomType.SINGLE,
    pricePerNight: 650,
    capacity: 2,
    description: 'Single bedroom with a king-size bed.',
    imageUrls: ['image/A_set1.jpg', 'image/F2.jpg'],
    amenities: ['Wi-Fi', 'Air conditioning', 'TV', 'Coffee'],
    status: RoomStatus.MAINTENANCE,
  },
];

async function seed(): Promise<void> {
  const dataSource = await dataSourceInstance.initialize();
  const repo = dataSource.getRepository(Room);

  let created = 0;
  let skipped = 0;

  for (const spec of ROOMS) {
    const exists = await repo.findOne({ where: { name: spec.name } });
    if (exists) {
      skipped += 1;
      continue;
    }
    await repo.save(repo.create(spec));
    created += 1;
  }

  console.log(`Seed complete: ${created} room(s) created, ${skipped} already present.`);
  await dataSource.destroy();
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
