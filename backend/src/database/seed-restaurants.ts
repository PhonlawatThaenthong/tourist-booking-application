import 'reflect-metadata';
import dataSourceInstance from '../config/data-source';
import { Restaurant } from '../modules/restaurants/restaurant.entity';
import { RESTAURANTS } from './restaurants.data';

/**
 * Populates `restaurants` with real places near the resort, replacing the
 * placeholder Pattaya list the app used to load from
 * `frontend/lib/data/mock_data.dart`.
 *
 * Photos are not part of this: they are files the backend stores, uploaded
 * through the API by `npm run upload:restaurant-photos` once they exist.
 *
 * Matched by `name` and safe to run more than once: a restaurant whose name
 * already exists is left untouched rather than duplicated.
 *
 * Usage: npm run seed:restaurants
 */
async function seed(): Promise<void> {
  const dataSource = await dataSourceInstance.initialize();
  const repo = dataSource.getRepository(Restaurant);

  let created = 0;
  let skipped = 0;

  for (const { photo: _photo, ...spec } of RESTAURANTS) {
    const exists = await repo.findOne({ where: { name: spec.name } });
    if (exists) {
      skipped += 1;
      continue;
    }
    await repo.save(repo.create(spec));
    created += 1;
  }

  console.log(`Seed complete: ${created} restaurant(s) created, ${skipped} already present.`);
  await dataSource.destroy();
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
