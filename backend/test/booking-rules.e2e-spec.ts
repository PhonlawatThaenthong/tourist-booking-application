import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { UsersService } from '../src/modules/users/users.service';
import { UserRole } from '../src/modules/users/user.entity';
import { BookingsService } from '../src/modules/bookings/bookings.service';
import { RoomType } from '../src/modules/rooms/room.entity';

/**
 * The business rules of a booking, end to end: who may book, what the
 * server prices it at, which dates/guest counts are refused, overlaps,
 * cancellation rights, the staff-only routes, check-in/out, and the
 * unpaid-hold expiry.
 *
 * Users and tokens come from the services, not /auth/register, so this file
 * never touches the auth rate limits (see auth.e2e-spec.ts).
 *
 * Requires Postgres + Redis (docker compose up). Run with `npm run test:e2e`.
 */
describe('Booking rules (e2e)', () => {
  let app: INestApplication;
  let ds: DataSource;
  let bookings: BookingsService;

  const stamp = Date.now();
  const PRICE = 1250.5;
  const CAPACITY = 2;

  let roomId: string; // main room: 1250.50/night, 2 guests
  let maintenanceRoomId: string;
  let todayRoomId: string; // only used by the "stay starts today" tests

  let alice: string; // customer
  let aliceId: string;
  let bob: string; // another customer
  let staff: string;

  const http = () => request(app.getHttpServer());

  // Each call hands out a fresh, non-overlapping range two years ahead.
  let dayCursor = 0;
  const nextRange = (nights = 2) => {
    const checkIn = futureDate(dayCursor);
    const checkOut = futureDate(dayCursor + nights);
    dayCursor += nights + 3;
    return { checkIn, checkOut };
  };

  const book = (token: string, body: Record<string, unknown>) =>
    http().post('/api/bookings').set('Authorization', `Bearer ${token}`).send(body);

  const cancel = (token: string, id: string) =>
    http().post(`/api/bookings/${id}/cancel`).set('Authorization', `Bearer ${token}`);

  const staffPatch = (id: string, body: Record<string, unknown>) =>
    http().patch(`/api/staff/bookings/${id}`).set('Authorization', `Bearer ${staff}`).send(body);

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
    bookings = app.get(BookingsService);

    const insertRoom = async (name: string, status = 'available') => {
      const [row] = await ds.query(
        `INSERT INTO rooms (name, type, price_per_night, capacity, status)
         VALUES ($1, $2, $3, $4, $5) RETURNING id`,
        [`${name} ${stamp}`, RoomType.SINGLE, PRICE, CAPACITY, status],
      );
      return row.id as string;
    };
    roomId = await insertRoom('Rules Room');
    maintenanceRoomId = await insertRoom('Rules Maintenance', 'maintenance');
    todayRoomId = await insertRoom('Rules Today Room');

    const auth = app.get(AuthService);
    const users = app.get(UsersService);
    const pw = 'password123';

    const a = await auth.register({ name: 'Alice', email: `alice.${stamp}@example.com`, password: pw });
    alice = a.accessToken;
    aliceId = a.user.id;
    bob = (await auth.register({ name: 'Bob', email: `bob.${stamp}@example.com`, password: pw }))
      .accessToken;
    await users.create({
      name: 'Front Desk', email: `staff.${stamp}@example.com`, password: pw, role: UserRole.STAFF,
    });
    staff = (await auth.login({ email: `staff.${stamp}@example.com`, password: pw })).accessToken;
  });

  afterAll(async () => {
    await app?.close();
  });

  // ------------------------------------------------------------ creating

  it('requires a logged-in user', async () => {
    await http().post('/api/bookings').send({ roomId, ...nextRange(), guests: 1 }).expect(401);
  });

  it('prices the booking on the server: nights × nightly rate', async () => {
    const res = await book(alice, { roomId, ...nextRange(3), guests: 2 }).expect(201);
    expect(res.body.nights).toBe(3);
    // A JSON number, not the string Postgres returns for numeric: the Flutter
    // app parses it with `as num` and would crash on a string.
    expect(typeof res.body.totalPrice).toBe('number');
    expect(res.body.totalPrice).toBeCloseTo(PRICE * 3, 2);
    expect(res.body.status).toBe('pending');
    expect(res.body.paymentStatus).toBe('unpaid');
    expect(res.body.customerId).toBe(aliceId);
  });

  it('refuses a client-supplied price or customer', async () => {
    await book(alice, { roomId, ...nextRange(), guests: 1, totalPrice: 1 }).expect(400);
    await book(alice, { roomId, ...nextRange(), guests: 1, customerId: aliceId }).expect(400);
  });

  it('refuses check-out on or before check-in', async () => {
    const { checkIn } = nextRange();
    await book(alice, { roomId, checkIn, checkOut: checkIn, guests: 1 }).expect(400);
    await book(alice, { roomId, checkIn, checkOut: futureDate(dayCursor - 10), guests: 1 })
      .expect(400);
  });

  it('refuses dates that are not YYYY-MM-DD', async () => {
    await book(alice, { roomId, checkIn: '01/02/2030', checkOut: '03/02/2030', guests: 1 })
      .expect(400);
    await book(alice, { roomId, checkIn: 'tomorrow', checkOut: 'next week', guests: 1 })
      .expect(400);
  });

  it('refuses more guests than the room holds', async () => {
    await book(alice, { roomId, ...nextRange(), guests: CAPACITY + 1 }).expect(400);
  });

  it('refuses a guest count outside 1–20', async () => {
    await book(alice, { roomId, ...nextRange(), guests: 0 }).expect(400);
    await book(alice, { roomId, ...nextRange(), guests: 21 }).expect(400);
    await book(alice, { roomId, ...nextRange(), guests: 1.5 }).expect(400);
  });

  it('404s an unknown room and 400s a malformed room id', async () => {
    await book(alice, {
      roomId: '00000000-0000-4000-8000-000000000000', ...nextRange(), guests: 1,
    }).expect(404);
    await book(alice, { roomId: 'room-1', ...nextRange(), guests: 1 }).expect(400);
  });

  it('refuses a room under maintenance', async () => {
    await book(alice, { roomId: maintenanceRoomId, ...nextRange(), guests: 1 }).expect(409);
  });

  // ------------------------------------------------------------ overlaps

  it('refuses an overlapping range on the same room, from any customer', async () => {
    const range = nextRange(4);
    await book(alice, { roomId, ...range, guests: 1 }).expect(201);
    // Same dates.
    await book(bob, { roomId, ...range, guests: 1 }).expect(409);
    // Partial overlap: starts inside the existing stay.
    await book(bob, {
      roomId, checkIn: futureDate(dayCursor - 6), checkOut: futureDate(dayCursor + 1), guests: 1,
    }).expect(409);
  });

  it('allows back-to-back stays: check-out day can be the next check-in day', async () => {
    const first = nextRange(2);
    await book(alice, { roomId, ...first, guests: 1 }).expect(201);
    await book(bob, {
      roomId, checkIn: first.checkOut, checkOut: futureDate(dayCursor + 1), guests: 1,
    }).expect(201);
    dayCursor += 5;
  });

  it('a cancelled booking frees its dates', async () => {
    const range = nextRange();
    const res = await book(alice, { roomId, ...range, guests: 1 }).expect(201);
    await cancel(staff, res.body.id).expect(200);
    await book(bob, { roomId, ...range, guests: 1 }).expect(201);
  });

  // ------------------------------------------------------------ listing

  it('/bookings/me lists only the caller\'s own bookings', async () => {
    const res = await http()
      .get('/api/bookings/me')
      .set('Authorization', `Bearer ${alice}`)
      .expect(200);
    expect(res.body.length).toBeGreaterThan(0);
    expect(res.body.every((b: { customerId: string }) => b.customerId === aliceId)).toBe(true);
  });

  // ------------------------------------------------------------ cancelling

  // Guests contact the front desk; only staff/admin cancel (and refund).

  it('a customer cannot cancel, not even their own booking', async () => {
    const res = await book(alice, { roomId, ...nextRange(), guests: 1 }).expect(201);
    await cancel(alice, res.body.id).expect(403);
    await cancel(bob, res.body.id).expect(403);
    // Refused before the lookup, so an unknown id gives nothing away either.
    await cancel(alice, '00000000-0000-4000-8000-000000000000').expect(403);
    // Still standing; staff tidy it up so the range is free again.
    await cancel(staff, res.body.id).expect(200);
  });

  it('cancelling twice is refused', async () => {
    const res = await book(alice, { roomId, ...nextRange(), guests: 1 }).expect(201);
    const first = await cancel(staff, res.body.id).expect(200);
    expect(first.body.status).toBe('cancelled');
    await cancel(staff, res.body.id).expect(409);
  });

  it('cancelling an unknown booking 404s, a malformed id 400s', async () => {
    await cancel(staff, '00000000-0000-4000-8000-000000000000').expect(404);
    await cancel(staff, 'abc').expect(400);
  });

  it('staff can cancel a stay that has already started (no-shows, disputes)', async () => {
    const res = await book(alice, {
      roomId: todayRoomId, checkIn: todayAtResort(0), checkOut: todayAtResort(1), guests: 1,
    }).expect(201);
    await cancel(alice, res.body.id).expect(403);
    await cancel(staff, res.body.id).expect(200);
  });

  // ------------------------------------------------------------ staff routes

  it('staff routes are closed to customers and anonymous callers', async () => {
    await http().get('/api/staff/bookings').expect(401);
    await http().get('/api/staff/bookings').set('Authorization', `Bearer ${alice}`).expect(403);
    await http().get('/api/staff/bookings').set('Authorization', `Bearer ${staff}`).expect(200);
  });

  it('staff PATCH validates its input', async () => {
    const res = await book(alice, { roomId, ...nextRange(), guests: 1 }).expect(201);
    const id = res.body.id;
    await staffPatch(id, {}).expect(400);
    await staffPatch(id, { checkIn: futureDate(dayCursor) }).expect(400); // checkOut missing
    await staffPatch(id, { status: 'checked_in' }).expect(400); // must use the check-in route
    await staffPatch(id, { status: 'teleported' }).expect(400);
  });

  it('staff reschedule re-prices the booking from the nightly rate', async () => {
    const res = await book(alice, { roomId, ...nextRange(2), guests: 1 }).expect(201);
    const moved = nextRange(5);
    const patched = await staffPatch(res.body.id, moved).expect(200);
    expect(patched.body.checkIn).toBe(moved.checkIn);
    expect(patched.body.nights).toBe(5);
    expect(Number(patched.body.totalPrice)).toBeCloseTo(PRICE * 5, 2);
  });

  it('staff reschedule cannot move a booking onto taken dates', async () => {
    const taken = nextRange(3);
    await book(bob, { roomId, ...taken, guests: 1 }).expect(201);
    const res = await book(alice, { roomId, ...nextRange(2), guests: 1 }).expect(201);
    await staffPatch(res.body.id, taken).expect(409);
  });

  // ------------------------------------------------------------ check-in / out

  it('check-in needs an approved booking and the right day', async () => {
    // Pending → refused.
    const future = await book(alice, { roomId, ...nextRange(), guests: 1 }).expect(201);
    await http()
      .post(`/api/staff/bookings/${future.body.id}/check-in`)
      .set('Authorization', `Bearer ${staff}`)
      .expect(409);

    // Approved but the stay is years away → refused.
    await staffPatch(future.body.id, { status: 'approved' }).expect(200);
    await http()
      .post(`/api/staff/bookings/${future.body.id}/check-in`)
      .set('Authorization', `Bearer ${staff}`)
      .expect(400);
  });

  it('a stay starting today goes approved → checked in → checked out, then is frozen', async () => {
    const res = await book(alice, {
      roomId: todayRoomId, checkIn: todayAtResort(0), checkOut: todayAtResort(2), guests: 1,
    }).expect(201);
    const id = res.body.id;
    const post = (path: string) =>
      http().post(`/api/staff/bookings/${id}/${path}`).set('Authorization', `Bearer ${staff}`);

    // Can't check out before checking in.
    await post('check-out').expect(409);

    await staffPatch(id, { status: 'approved' }).expect(200);
    expect((await post('check-in').expect(200)).body.status).toBe('checked_in');
    expect((await post('check-out').expect(200)).body.status).toBe('checked_out');

    // A closed stay can't be edited or cancelled.
    await staffPatch(id, { status: 'approved' }).expect(409);
    await cancel(staff, id).expect(409);
  });

  // ------------------------------------------------------------ unpaid hold expiry

  it('an abandoned unpaid booking is auto-cancelled and frees the room', async () => {
    const range = nextRange();
    const res = await book(alice, { roomId, ...range, guests: 1 }).expect(201);

    await bookings.expireIfUnpaid(res.body.id);

    const after = await bookings.getOrFail(res.body.id);
    expect(after.status).toBe('cancelled');
    await book(bob, { roomId, ...range, guests: 1 }).expect(201);
  });

  it('expiry leaves an approved booking alone', async () => {
    const res = await book(alice, { roomId, ...nextRange(), guests: 1 }).expect(201);
    await staffPatch(res.body.id, { status: 'approved' }).expect(200);

    await bookings.expireIfUnpaid(res.body.id);

    expect((await bookings.getOrFail(res.body.id)).status).toBe('approved');
  });

  it('expiry of an unknown booking is a harmless no-op', async () => {
    await expect(
      bookings.expireIfUnpaid('00000000-0000-4000-8000-000000000000'),
    ).resolves.toBeUndefined();
  });

  // ---- helpers ----
  function futureDate(offsetDays: number): string {
    const d = new Date();
    d.setUTCFullYear(d.getUTCFullYear() + 2);
    d.setUTCDate(d.getUTCDate() + offsetDays);
    return d.toISOString().slice(0, 10);
  }

  /** Today (+offset days) in Bangkok, the same clock the service uses. */
  function todayAtResort(offsetDays: number): string {
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Bangkok' }).format(new Date());
    const d = new Date(`${today}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + offsetDays);
    return d.toISOString().slice(0, 10);
  }
});
