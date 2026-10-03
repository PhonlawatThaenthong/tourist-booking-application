import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { RoomType } from '../src/modules/rooms/room.entity';

/**
 * Sprint 4 — manual QR-slip payment verification (e2e).
 *
 * Flow under test: customer uploads a transfer slip -> payment goes to
 * `awaiting_verification`, the booking stays unpaid; staff approves ->
 * payment `succeeded` and the booking becomes paid/approved. Also covers the
 * reject-then-re-upload path.
 *
 * Requires a running Postgres AND Redis (docker compose up), migrations
 * applied automatically in beforeAll. Run with `npm run test:e2e`.
 */
describe('Payment slip verification (e2e)', () => {
  let app: INestApplication;
  let ds: DataSource;

  const stamp = Date.now();
  const cust = { name: 'Somchai', email: `cust.${stamp}@example.com`, password: 'password123' };
  const admin = { name: 'Manager', email: `admin.${stamp}@example.com`, password: 'password123' };

  let custToken: string;
  let adminToken: string;
  let roomId: string;

  // A 1x1 transparent PNG — enough for multer to accept as an image.
  const PNG = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    'base64',
  );

  const attachSlip = (token: string, bookingId: string) =>
    request(app.getHttpServer())
      .post(`/api/bookings/${bookingId}/pay`)
      .set('Authorization', `Bearer ${token}`)
      .attach('slip', PNG, { filename: 'slip.png', contentType: 'image/png' });

  // Each booking gets its own non-overlapping range so the exclusion
  // constraint never rejects a setup booking.
  let dayCursor = 10;
  const newBooking = async (): Promise<string> => {
    const checkIn = futureDate(dayCursor);
    const checkOut = futureDate(dayCursor + 2);
    dayCursor += 5;
    const res = await request(app.getHttpServer())
      .post('/api/bookings')
      .set('Authorization', `Bearer ${custToken}`)
      .send({ roomId, checkIn, checkOut, guests: 2 })
      .expect(201);
    return res.body.id;
  };

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
      [`Slip Test Room ${stamp}`, RoomType.SINGLE, 1500, 4],
    );
    roomId = room.id;

    custToken = await registerAndLogin(cust);
    // Mint an admin by registering then promoting directly (register only
    // ever creates `customer`).
    await register(admin);
    await ds.query(`UPDATE users SET role = 'admin' WHERE email = $1`, [admin.email]);
    adminToken = await login(admin);
  });

  afterAll(async () => {
    await app?.close();
  });

  it('uploading a slip does NOT mark the booking paid — it awaits verification', async () => {
    const bookingId = await newBooking();

    const pay = await attachSlip(custToken, bookingId).expect(200);
    expect(pay.body.status).toBe('awaiting_verification');
    expect(pay.body.hasSlip).toBe(true);

    // Booking is still unpaid/pending until a human confirms.
    const me = await request(app.getHttpServer())
      .get('/api/bookings/me')
      .set('Authorization', `Bearer ${custToken}`)
      .expect(200);
    const b = me.body.find((x: any) => x.id === bookingId);
    expect(b.paymentStatus).toBe('unpaid');
    expect(b.status).toBe('pending');
  });

  it('staff sees the pending slip, views the image, and approves it', async () => {
    const bookingId = await newBooking();
    const pay = await attachSlip(custToken, bookingId).expect(200);
    const paymentId = pay.body.id;

    const list = await request(app.getHttpServer())
      .get('/api/staff/payments?status=awaiting_verification')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    expect(list.body.some((p: any) => p.id === paymentId)).toBe(true);

    await request(app.getHttpServer())
      .get(`/api/staff/payments/${paymentId}/slip`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200)
      .expect('Content-Type', /image/);

    const approve = await request(app.getHttpServer())
      .patch(`/api/staff/payments/${paymentId}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ action: 'approve' })
      .expect(200);
    expect(approve.body.status).toBe('succeeded');

    const view = await request(app.getHttpServer())
      .get(`/api/bookings/${bookingId}/payment`)
      .set('Authorization', `Bearer ${custToken}`)
      .expect(200);
    expect(view.body.status).toBe('succeeded');

    const me = await request(app.getHttpServer())
      .get('/api/bookings/me')
      .set('Authorization', `Bearer ${custToken}`)
      .expect(200);
    const b = me.body.find((x: any) => x.id === bookingId);
    expect(b.paymentStatus).toBe('paid');
    expect(b.status).toBe('approved');
  });

  it('a rejected slip leaves the booking unpaid and lets the customer re-upload', async () => {
    const bookingId = await newBooking();
    const pay = await attachSlip(custToken, bookingId).expect(200);
    const paymentId = pay.body.id;

    const reject = await request(app.getHttpServer())
      .patch(`/api/staff/payments/${paymentId}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ action: 'reject', reason: 'ยอดเงินไม่ตรง' })
      .expect(200);
    expect(reject.body.status).toBe('rejected');
    expect(reject.body.rejectReason).toBe('ยอดเงินไม่ตรง');

    // Re-upload after a rejection starts a fresh verification.
    const reupload = await attachSlip(custToken, bookingId).expect(200);
    expect(reupload.body.status).toBe('awaiting_verification');
    expect(reupload.body.rejectReason).toBeNull();
  });

  it('a customer cannot upload a slip to a booking that is not theirs', async () => {
    const bookingId = await newBooking();
    const otherToken = await registerAndLogin({
      name: 'Other', email: `other.${stamp}@example.com`, password: 'password123',
    });
    await attachSlip(otherToken, bookingId).expect(403);
  });

  // ---- helpers ----
  function futureDate(offsetDays: number): string {
    const d = new Date();
    d.setUTCFullYear(d.getUTCFullYear() + 2);
    d.setUTCDate(d.getUTCDate() + offsetDays);
    return d.toISOString().slice(0, 10);
  }

  function register(u: { name: string; email: string; password: string }) {
    return request(app.getHttpServer()).post('/api/auth/register').send(u).expect(201);
  }

  async function login(u: { email: string; password: string }): Promise<string> {
    const res = await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: u.email, password: u.password })
      .expect(200);
    return res.body.accessToken;
  }

  async function registerAndLogin(u: { name: string; email: string; password: string }): Promise<string> {
    await register(u);
    return login(u);
  }
});
