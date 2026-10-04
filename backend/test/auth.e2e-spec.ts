import { INestApplication, UnauthorizedException, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { MailService } from '../src/modules/mail/mail.service';
import { UsersService } from '../src/modules/users/users.service';

/**
 * Auth flows end to end: register, login, /me, refresh-token rotation,
 * logout, and the forgot/reset-password code.
 *
 * Rate limits matter here. The throttler is per IP and in memory per app, so
 * this file gets its own budget, but every HTTP call below counts:
 *   register 5/min · login 10/min · refresh 20/min
 *   forgot-password 3/15min · reset-password 5/15min
 * Extra setup users are therefore created through the services, and the
 * "5 wrong codes" case goes through AuthService directly. The tests run in
 * order and later ones rely on state from earlier ones.
 *
 * Requires Postgres + Redis (docker compose up). Run with `npm run test:e2e`.
 */
describe('Auth (e2e)', () => {
  let app: INestApplication;
  let ds: DataSource;
  let users: UsersService;
  let auth: AuthService;

  const stamp = Date.now();
  const main = {
    name: 'Auth Tester',
    email: `auth.${stamp}@example.com`,
    password: 'password123',
  };

  // Captures the 6-digit code the API would have emailed.
  const sentCodes = new Map<string, string>();

  let accessToken: string;
  let refreshToken: string;

  const http = () => request(app.getHttpServer());

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
    users = app.get(UsersService);
    auth = app.get(AuthService);

    jest
      .spyOn(app.get(MailService), 'sendPasswordResetCode')
      .mockImplementation(async (to: string, code: string) => {
        sentCodes.set(to, code);
      });
  });

  afterAll(async () => {
    await app?.close();
  });

  // ---------------------------------------------------------------- register

  it('register returns tokens and a customer profile, never the password hash', async () => {
    // Mixed-case on purpose: the account must be stored lower-cased.
    const res = await http()
      .post('/api/auth/register')
      .send({ ...main, email: main.email.toUpperCase(), phone: '081-234-5678' })
      .expect(201);

    expect(res.body.accessToken).toEqual(expect.any(String));
    expect(res.body.refreshToken).toEqual(expect.any(String));
    expect(res.body.user).toEqual({
      id: expect.any(String),
      name: main.name,
      email: main.email, // lower-cased
      phone: '081-234-5678',
      role: 'customer',
    });
    expect(JSON.stringify(res.body)).not.toMatch(/password/i);
  });

  it('register rejects an email that is already taken, regardless of case', async () => {
    await http()
      .post('/api/auth/register')
      .send({ ...main, email: main.email.replace('auth.', 'AUTH.') })
      .expect(409);
  });

  it('register rejects a password shorter than 8 characters', async () => {
    await http()
      .post('/api/auth/register')
      .send({ name: 'Short', email: `short.${stamp}@example.com`, password: '1234567' })
      .expect(400);
  });

  it('register rejects a malformed email', async () => {
    await http()
      .post('/api/auth/register')
      .send({ name: 'Bad', email: 'not-an-email', password: 'password123' })
      .expect(400);
  });

  it('register cannot be used to make yourself an admin', async () => {
    // `role` is not in RegisterDto, so forbidNonWhitelisted rejects the body.
    await http()
      .post('/api/auth/register')
      .send({
        name: 'Sneaky', email: `sneaky.${stamp}@example.com`,
        password: 'password123', role: 'admin',
      })
      .expect(400);
    expect(await users.findByEmail(`sneaky.${stamp}@example.com`)).toBeNull();
  });

  // ------------------------------------------------------------------- login

  it('login works with the email in any case', async () => {
    const res = await http()
      .post('/api/auth/login')
      .send({ email: main.email.toUpperCase(), password: main.password })
      .expect(200);
    accessToken = res.body.accessToken;
    refreshToken = res.body.refreshToken;
    expect(res.body.user.email).toBe(main.email);
  });

  it('wrong password and unknown email fail with the same message', async () => {
    const wrongPw = await http()
      .post('/api/auth/login')
      .send({ email: main.email, password: 'wrong-password' })
      .expect(401);
    const noUser = await http()
      .post('/api/auth/login')
      .send({ email: `nobody.${stamp}@example.com`, password: 'password123' })
      .expect(401);
    // No account enumeration: the two failures must be indistinguishable.
    expect(wrongPw.body.message).toBe(noUser.body.message);
  });

  // --------------------------------------------------------------------- /me

  it('/me returns the logged-in user', async () => {
    const res = await http()
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);
    expect(res.body.email).toBe(main.email);
    expect(res.body.role).toBe('customer');
  });

  it('/me rejects a missing or forged token', async () => {
    await http().get('/api/auth/me').expect(401);
    await http().get('/api/auth/me').set('Authorization', 'Bearer not.a.jwt').expect(401);
    // Correct shape, wrong signature.
    const [h, p] = accessToken.split('.');
    await http()
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${h}.${p}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`)
      .expect(401);
  });

  // ----------------------------------------------------------------- refresh

  it('refresh rotates the token: the new one works, the old one is dead', async () => {
    const first = await http()
      .post('/api/auth/refresh')
      .send({ refreshToken })
      .expect(200);
    expect(first.body.refreshToken).not.toBe(refreshToken);
    expect(first.body.accessToken).toEqual(expect.any(String));

    // Replaying the used token must fail (stolen-token protection).
    await http().post('/api/auth/refresh').send({ refreshToken }).expect(401);

    refreshToken = first.body.refreshToken;
    accessToken = first.body.accessToken;
    await http().get('/api/auth/me').set('Authorization', `Bearer ${accessToken}`).expect(200);
  });

  it('refresh rejects a token that was never issued', async () => {
    await http()
      .post('/api/auth/refresh')
      .send({ refreshToken: 'f'.repeat(96) })
      .expect(401);
  });

  it('refresh rejects an expired token', async () => {
    const session = await auth.login({ email: main.email, password: main.password });
    await ds.query(
      `UPDATE refresh_tokens SET expires_at = now() - interval '1 minute'
       WHERE token_hash = encode(sha256($1::bytea), 'hex')`,
      [session.refreshToken],
    );
    await http()
      .post('/api/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(401);
  });

  // ------------------------------------------------------------------ logout

  it('logout revokes the refresh token', async () => {
    const session = await auth.login({ email: main.email, password: main.password });
    await http()
      .post('/api/auth/logout')
      .send({ refreshToken: session.refreshToken })
      .expect(204);
    await http()
      .post('/api/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(401);
  });

  // ---------------------------------------------------------- password reset

  it('forgot-password answers identically for known and unknown emails', async () => {
    const known = await http()
      .post('/api/auth/forgot-password')
      .send({ email: main.email })
      .expect(200);
    const unknown = await http()
      .post('/api/auth/forgot-password')
      .send({ email: `ghost.${stamp}@example.com` })
      .expect(200);

    expect(known.body).toEqual(unknown.body);
    expect(sentCodes.get(main.email)).toMatch(/^\d{6}$/);
    expect(sentCodes.has(`ghost.${stamp}@example.com`)).toBe(false);
  });

  it('reset-password rejects a wrong code', async () => {
    const real = sentCodes.get(main.email)!;
    const wrong = real === '000000' ? '111111' : '000000';
    await http()
      .post('/api/auth/reset-password')
      .send({ email: main.email, code: wrong, newPassword: 'newpassword456' })
      .expect(401);
  });

  it('reset-password with the right code changes the password and ends every session', async () => {
    // A session opened before the reset...
    const before = await auth.login({ email: main.email, password: main.password });

    await http()
      .post('/api/auth/reset-password')
      .send({ email: main.email, code: sentCodes.get(main.email), newPassword: 'newpassword456' })
      .expect(200);

    // ...is revoked by it.
    await http()
      .post('/api/auth/refresh')
      .send({ refreshToken: before.refreshToken })
      .expect(401);

    await http()
      .post('/api/auth/login')
      .send({ email: main.email, password: main.password })
      .expect(401);
    await http()
      .post('/api/auth/login')
      .send({ email: main.email, password: 'newpassword456' })
      .expect(200);
  });

  it('a reset code cannot be used twice', async () => {
    await http()
      .post('/api/auth/reset-password')
      .send({ email: main.email, code: sentCodes.get(main.email), newPassword: 'another789xyz' })
      .expect(401);
  });

  it('a reset code is burned after 5 wrong guesses, even the right code then fails', async () => {
    // Through the service: five HTTP guesses would use the whole route budget.
    const email = `guess.${stamp}@example.com`;
    await users.create({ name: 'Guesser', email, password: 'password123' });
    await auth.forgotPassword(email);
    const code = sentCodes.get(email)!;
    const wrong = code === '000000' ? '111111' : '000000';

    for (let i = 0; i < 5; i++) {
      await expect(
        auth.resetPassword({ email, code: wrong, newPassword: 'newpassword456' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    }
    await expect(
      auth.resetPassword({ email, code, newPassword: 'newpassword456' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('an expired reset code is rejected', async () => {
    const email = `expired.${stamp}@example.com`;
    const user = await users.create({ name: 'Late', email, password: 'password123' });
    await auth.forgotPassword(email);
    await ds.query(
      `UPDATE password_reset_tokens SET expires_at = now() - interval '1 minute'
       WHERE user_id = $1`,
      [user.id],
    );
    await expect(
      auth.resetPassword({ email, code: sentCodes.get(email)!, newPassword: 'newpassword456' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('a new forgot-password request invalidates the previous code', async () => {
    const email = `twice.${stamp}@example.com`;
    await users.create({ name: 'Twice', email, password: 'password123' });
    await auth.forgotPassword(email);
    const firstCode = sentCodes.get(email)!;
    await auth.forgotPassword(email);
    const secondCode = sentCodes.get(email)!;
    if (firstCode === secondCode) return; // 1-in-a-million collision, nothing to assert

    await expect(
      auth.resetPassword({ email, code: firstCode, newPassword: 'newpassword456' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(
      auth.resetPassword({ email, code: secondCode, newPassword: 'newpassword456' }),
    ).resolves.toEqual({ message: expect.any(String) });
  });

  // Last on purpose: it uses up the forgot-password budget for this app.
  it('forgot-password is rate limited to 3 requests per 15 minutes', async () => {
    // Two calls already made above; one more is allowed, the next is not.
    await http().post('/api/auth/forgot-password').send({ email: main.email }).expect(200);
    await http().post('/api/auth/forgot-password').send({ email: main.email }).expect(429);
  });
});
