import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { RoomType } from '../src/modules/rooms/room.entity';
import { RedisCacheService } from '../src/modules/cache/redis-cache.service';
import { ROOMS_CACHE_NAMESPACE } from '../src/modules/rooms/rooms-cache';

/**
 * Redis cache-aside on GET /api/rooms (design doc section 5).
 *
 * What matters is not that the cache hits, but that it never serves a room
 * as free after a booking for it committed. That is the invalidation the
 * last test checks. Requires Postgres and Redis (docker compose up -d
 * postgres redis); run with `npm run test:e2e`.
 */
describe('GET /api/rooms — Redis cache (e2e)', () => {
  let app: INestApplication;
  let ds: DataSource;

  const stamp = Date.now();
  const carol = { name: 'Carol', email: `carol.${stamp}@example.com`, password: 'password123' };
  let token: string;
  let roomId: string;

  // A window no other suite uses, so its cached answer is this suite's alone.
  const CHECK_IN = '2031-03-10';
  const CHECK_OUT = '2031-03-12';
  const search = () =>
    request(app.getHttpServer())
      .get(`/api/rooms?checkIn=${CHECK_IN}&checkOut=${CHECK_OUT}&guests=1`)
      .expect(200);

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api', { exclude: ['health/live', 'health/ready'] });
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();

    ds = app.get(DataSource);
    await ds.runMigrations();

    const [room] = await ds.query(
      `INSERT INTO rooms (name, type, price_per_night, capacity)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [`Cache Test Room ${stamp}`, RoomType.SINGLE, 1800, 2],
    );
    roomId = room.id;
    // Raw SQL skips the service layer, so do what a staff room edit would:
    // drop cached answers that predate this room (e.g. from a previous run).
    await app.get(RedisCacheService).invalidate(ROOMS_CACHE_NAMESPACE);

    await request(app.getHttpServer()).post('/api/auth/register').send(carol).expect(201);
    const login = await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: carol.email, password: carol.password })
      .expect(200);
    token = login.body.accessToken;
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM bookings WHERE room_id = $1`, [roomId]);
      await ds.query(`DELETE FROM rooms WHERE id = $1`, [roomId]);
      await ds.query(`DELETE FROM users WHERE email = $1`, [carol.email]);
    }
    await app?.close();
  });

  it('answers the second identical search from Redis', async () => {
    // Other suites run in parallel and may invalidate between two calls, so
    // allow a few attempts before calling it a failure.
    let status = '';
    for (let i = 0; i < 5 && status !== 'HIT'; i++) {
      const res = await search();
      status = res.headers['x-cache'];
      expect(res.body.map((r: { id: string }) => r.id)).toContain(roomId);
    }
    expect(status).toBe('HIT');
  });

  it('hides the room right after it is booked, without waiting for the TTL', async () => {
    const before = await search();
    // HIT normally; MISS if a parallel suite just invalidated. Never BYPASS.
    expect(['HIT', 'MISS']).toContain(before.headers['x-cache']);
    expect(before.body.map((r: { id: string }) => r.id)).toContain(roomId);

    await request(app.getHttpServer())
      .post('/api/bookings')
      .set('Authorization', `Bearer ${token}`)
      .send({ roomId, checkIn: CHECK_IN, checkOut: CHECK_OUT, guests: 1 })
      .expect(201);

    const after = await search();
    expect(after.headers['x-cache']).toBe('MISS');
    expect(after.body.map((r: { id: string }) => r.id)).not.toContain(roomId);
  });

  it('rejects a bad range with 400 even when cached answers exist', async () => {
    await request(app.getHttpServer())
      .get(`/api/rooms?checkIn=${CHECK_OUT}&checkOut=${CHECK_IN}`)
      .expect(400);
  });
});
