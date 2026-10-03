import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { RoomType } from '../src/modules/rooms/room.entity';

/**
 * Revenue and occupancy reports (issues #40, #41).
 *
 * Fixtures live in 2041 so bookings left behind by other suites cannot land in
 * the ranges asserted here; they are deleted again in afterAll so re-runs do
 * not accumulate.
 */
describe('Staff reports (e2e)', () => {
  let app: INestApplication;
  let ds: DataSource;

  const stamp = Date.now();
  const cust = { name: 'Report Cust', email: `rcust.${stamp}@example.com`, password: 'password123' };
  const admin = { name: 'Report Admin', email: `radmin.${stamp}@example.com`, password: 'password123' };

  let custToken: string;
  let adminToken: string;
  let roomId: string;

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

    const reg = await request(app.getHttpServer()).post('/api/auth/register').send(cust).expect(201);
    custToken = reg.body.accessToken;
    const customerId = reg.body.user.id;

    await request(app.getHttpServer()).post('/api/auth/register').send(admin).expect(201);
    await ds.query(`UPDATE users SET role = 'admin' WHERE email = $1`, [admin.email]);
    const login = await request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: admin.email, password: admin.password })
      .expect(200);
    adminToken = login.body.accessToken;

    const [room] = await ds.query(
      `INSERT INTO rooms (name, type, price_per_night, capacity)
       VALUES ($1, $2, 1000, 2) RETURNING id`,
      [`Report Test Room ${stamp}`, RoomType.TWIN],
    );
    roomId = room.id;

    const insert = (checkIn: string, checkOut: string, total: number, status: string, paid: string) =>
      ds.query(
        `INSERT INTO bookings (room_id, customer_id, check_in, check_out, guests, total_price, status, payment_status)
         VALUES ($1, $2, $3, $4, 2, $5, $6, $7)`,
        [roomId, customerId, checkIn, checkOut, total, status, paid],
      );
    // Paid, 3 nights straddling March/April: 30 Mar, 31 Mar, 1 Apr.
    await insert('2041-03-30', '2041-04-02', 3000, 'approved', 'paid');
    // Unpaid hold: occupies a night but earns nothing.
    await insert('2041-04-05', '2041-04-06', 1000, 'pending', 'unpaid');
    // Cancelled + refunded: neither revenue nor occupancy.
    await insert('2041-04-10', '2041-04-12', 2000, 'cancelled', 'refunded');
  });

  afterAll(async () => {
    if (roomId) {
      await ds.query(`DELETE FROM bookings WHERE room_id = $1`, [roomId]);
      await ds.query(`DELETE FROM rooms WHERE id = $1`, [roomId]);
    }
    await app?.close();
  });

  const get = (path: string, token = adminToken) =>
    request(app.getHttpServer()).get(path).set('Authorization', `Bearer ${token}`);

  it('daily revenue counts only the nights inside the range', async () => {
    const res = await get('/api/staff/reports/revenue?from=2041-03-31&to=2041-04-01').expect(200);
    expect(res.body.series).toEqual([
      { period: '2041-03-31', revenue: 1000 },
      { period: '2041-04-01', revenue: 1000 },
    ]);
    expect(res.body.total).toBe(2000);
    expect(res.body.paidBookings).toBe(1);
  });

  it('monthly revenue splits a stay across months and zero-fills empty ones', async () => {
    const res = await get('/api/staff/reports/revenue?from=2041-03-01&to=2041-05-31&groupBy=month')
      .expect(200);
    expect(res.body.series).toEqual([
      { period: '2041-03', revenue: 2000 },
      { period: '2041-04', revenue: 1000 },
      { period: '2041-05', revenue: 0 },
    ]);
    expect(res.body.total).toBe(3000);
  });

  it('occupancy counts non-cancelled nights, broken down by room type', async () => {
    const res = await get('/api/staff/reports/occupancy?from=2041-04-01&to=2041-04-10').expect(200);
    expect(res.body.days).toBe(10);

    const twin = res.body.byType.find((t: any) => t.type === 'twin');
    // 1 Apr from the paid stay + 5 Apr from the unpaid hold; the cancelled one is ignored.
    expect(twin.bookedNights).toBe(2);
    expect(twin.availableNights).toBe(twin.rooms * 10);
    expect(twin.rate).toBe(Math.round((2 / (twin.rooms * 10)) * 1000) / 10);

    expect(res.body.byType.map((t: any) => t.type).sort()).toEqual(['single', 'twin']);
    expect(res.body.overall.rooms).toBe(
      res.body.byType.reduce((n: number, t: any) => n + t.rooms, 0),
    );
  });

  it('rejects a reversed or oversized range', async () => {
    await get('/api/staff/reports/occupancy?from=2041-04-10&to=2041-04-01').expect(400);
    await get('/api/staff/reports/revenue?from=2041-01-01&to=2042-06-01').expect(400);
    await get('/api/staff/reports/revenue?from=2041-04-01&to=2041-04-02&groupBy=week').expect(400);
  });

  it('is closed to customers', async () => {
    await get('/api/staff/reports/revenue?from=2041-04-01&to=2041-04-02', custToken).expect(403);
  });
});
