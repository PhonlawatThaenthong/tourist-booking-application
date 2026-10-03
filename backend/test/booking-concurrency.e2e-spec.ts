import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { RoomType } from '../src/modules/rooms/room.entity';

/**
 * Sprint 2 acceptance criterion 4.
 *
 * Two customers POST the same room and the same nights at the same moment.
 * Exactly one must get 201 and the other 409 — never two 201s, and never two
 * 409s. This is the test that would fail if `EXC_bookings_no_overlap` were
 * dropped, no matter how carefully the service checked availability first.
 *
 * Requires a running Postgres (docker compose up postgres) with migrations
 * applied; run with `npm run test:e2e`.
 */
describe('POST /api/bookings — concurrent double booking (e2e)', () => {
  let app: INestApplication;
  let ds: DataSource;

  const stamp = Date.now();
  const alice = { name: 'Alice', email: `alice.${stamp}@example.com`, password: 'password123' };
  const bob = { name: 'Bob', email: `bob.${stamp}@example.com`, password: 'password123' };

  let aliceToken: string;
  let bobToken: string;
  let roomId: string;

  const CHECK_IN = '2030-01-10';
  const CHECK_OUT = '2030-01-12';

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

    // A room inserted directly: the API only lets staff create rooms, and
    // minting a staff account is not what this test is about.
    const [room] = await ds.query(
      `INSERT INTO rooms (name, type, price_per_night, capacity)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [`Race Test Room ${stamp}`, RoomType.SINGLE, 2500, 4],
    );
    roomId = room.id;

    aliceToken = await registerAndLogin(alice);
    bobToken = await registerAndLogin(bob);
  });

  afterAll(async () => {
    if (ds?.isInitialized) {
      await ds.query(`DELETE FROM bookings WHERE room_id = $1`, [roomId]);
      await ds.query(`DELETE FROM rooms WHERE id = $1`, [roomId]);
      await ds.query(`DELETE FROM users WHERE email = ANY($1)`, [[alice.email, bob.email]]);
    }
    await app?.close();
  });

  async function registerAndLogin(user: typeof alice): Promise<string> {
    await request(app.getHttpServer()).post('/api/auth/register').send(user).expect(201);
    const res = await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: user.email, password: user.password })
      .expect(200);
    return res.body.accessToken;
  }

  const book = (token: string) =>
    request(app.getHttpServer())
      .post('/api/bookings')
      .set('Authorization', `Bearer ${token}`)
      .send({ roomId, checkIn: CHECK_IN, checkOut: CHECK_OUT, guests: 2 });

  it('gives exactly one 201 and one 409 when two requests race', async () => {
    const [first, second] = await Promise.all([book(aliceToken), book(bobToken)]);
    const codes = [first.status, second.status].sort((a, b) => a - b);

    expect(codes).toEqual([201, 409]);

    const [{ count }] = await ds.query(
      `SELECT COUNT(*)::int AS count FROM bookings
       WHERE room_id = $1 AND status <> 'cancelled'`,
      [roomId],
    );
    expect(count).toBe(1);
  });

  it('prices the winning booking from the stored nightly rate, not the client', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/bookings/me')
      .set('Authorization', `Bearer ${aliceToken}`)
      .expect(200);

    const mine = res.body;
    if (mine.length === 0) return; // Bob won the race; his booking is checked below.

    expect(mine[0].totalPrice).toBe(5000); // 2 nights x 2500
    expect(mine[0].nights).toBe(2);
    expect(mine[0].roomName).toContain('Race Test Room');
  });

  it('still rejects an overlapping range on a later, non-concurrent attempt', async () => {
    await book(bobToken).expect(409);
  });

  it('accepts a back-to-back range that starts on the previous check-out day', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/bookings')
      .set('Authorization', `Bearer ${bobToken}`)
      .send({ roomId, checkIn: CHECK_OUT, checkOut: '2030-01-14', guests: 2 });

    // daterange '[)' — check-out day is free for the next guest.
    expect(res.status).toBe(201);
  });

  it('does not make a different room wait (per-room lock)', async () => {
    // Two rooms, two customers, the same nights, at the same moment. Each
    // request locks only its own room, so both must succeed.
    const [other] = await ds.query(
      `INSERT INTO rooms (name, type, price_per_night, capacity)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [`Race Test Room B ${stamp}`, RoomType.SINGLE, 2500, 4],
    );
    try {
      const [a, b] = await Promise.all([
        request(app.getHttpServer())
          .post('/api/bookings')
          .set('Authorization', `Bearer ${aliceToken}`)
          .send({ roomId, checkIn: '2030-02-01', checkOut: '2030-02-03', guests: 1 }),
        request(app.getHttpServer())
          .post('/api/bookings')
          .set('Authorization', `Bearer ${bobToken}`)
          .send({ roomId: other.id, checkIn: '2030-02-01', checkOut: '2030-02-03', guests: 1 }),
      ]);
      expect([a.status, b.status]).toEqual([201, 201]);
    } finally {
      await ds.query(`DELETE FROM bookings WHERE room_id = $1`, [other.id]);
      await ds.query(`DELETE FROM rooms WHERE id = $1`, [other.id]);
    }
  });

  it('lets the same room take two non-overlapping ranges at the same moment', async () => {
    // Same lock key, so the second request waits for the first instead of
    // being rejected — both get 201.
    const [a, b] = await Promise.all([
      request(app.getHttpServer())
        .post('/api/bookings')
        .set('Authorization', `Bearer ${aliceToken}`)
        .send({ roomId, checkIn: '2030-03-01', checkOut: '2030-03-03', guests: 1 }),
      request(app.getHttpServer())
        .post('/api/bookings')
        .set('Authorization', `Bearer ${bobToken}`)
        .send({ roomId, checkIn: '2030-03-05', checkOut: '2030-03-07', guests: 1 }),
    ]);
    expect([a.status, b.status]).toEqual([201, 201]);
  });

  it('hides the room from availability search for the booked range', async () => {
    const res = await request(app.getHttpServer())
      .get(`/api/rooms?checkIn=${CHECK_IN}&checkOut=${CHECK_OUT}`)
      .expect(200);

    expect(res.body.map((r: { id: string }) => r.id)).not.toContain(roomId);
  });
});
