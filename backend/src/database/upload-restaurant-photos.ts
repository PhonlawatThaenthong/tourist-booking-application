import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import { extname, join } from 'path';
import { RESTAURANTS } from './restaurants.data';

/**
 * Uploads each restaurant's photo from `backend/seed-photos/restaurants/`
 * through the staff API, so the files land wherever the running backend keeps
 * its uploads — including inside the Docker volume, which a plain copy from
 * the host could not reach.
 *
 * Photos not in the folder yet are skipped and listed, so this can be run
 * again as more arrive. Re-running replaces photos already uploaded.
 *
 * Env: API_URL (default http://localhost:3000), and an admin or staff login in
 * SEED_ADMIN_EMAIL / SEED_ADMIN_PASSWORD (default: the demo admin account).
 *
 * Usage: npm run upload:restaurant-photos
 */
const API = (process.env.API_URL ?? 'http://localhost:3000').replace(/\/$/, '');
const PHOTO_DIR = join(__dirname, '..', '..', 'seed-photos', 'restaurants');
const MIME: Record<string, string> = {
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp',
};

async function api<T>(path: string, init: RequestInit): Promise<T> {
  const res = await fetch(`${API}${path}`, init);
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`${init.method ?? 'GET'} ${path} -> ${res.status} ${JSON.stringify(body)}`);
  }
  return body as T;
}

async function main(): Promise<void> {
  const { accessToken } = await api<{ accessToken: string }>('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: process.env.SEED_ADMIN_EMAIL ?? 'admin@hotel.com',
      password: process.env.SEED_ADMIN_PASSWORD ?? 'admin123',
    }),
  });

  const listed = await api<Array<{ id: string; name: string }>>('/api/restaurants', {});
  const idByName = new Map(listed.map((r) => [r.name, r.id]));

  const missingFile: string[] = [];
  const missingRow: string[] = [];
  let uploaded = 0;

  for (const spec of RESTAURANTS) {
    const id = idByName.get(spec.name);
    if (!id) {
      missingRow.push(spec.name);
      continue;
    }
    // The listed name, or the same name as any other supported image type
    // (a screenshot saved as .png should not need renaming).
    const base = spec.photo.slice(0, -extname(spec.photo).length);
    const file = [spec.photo, ...Object.keys(MIME).map((ext) => base + ext)]
      .map((name) => join(PHOTO_DIR, name))
      .find(existsSync);
    if (!file) {
      missingFile.push(spec.photo);
      continue;
    }

    const form = new FormData();
    const type = MIME[extname(file).toLowerCase()] ?? 'image/jpeg';
    form.append('image', new Blob([await readFile(file)], { type }), spec.photo);
    await api(`/api/staff/restaurants/${id}/image`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}` },
      body: form,
    });
    uploaded += 1;
    console.log(`uploaded  ${spec.photo}`);
  }

  console.log(`\n${uploaded} photo(s) uploaded.`);
  if (missingFile.length) {
    console.log(`Not in ${PHOTO_DIR} yet:\n  ${missingFile.join('\n  ')}`);
  }
  if (missingRow.length) {
    console.log(`No such restaurant in the API (run seed:restaurants first):\n  ${missingRow.join('\n  ')}`);
  }
}

main().catch((err) => {
  console.error('Upload failed:', err instanceof Error ? err.message : err);
  process.exit(1);
});
