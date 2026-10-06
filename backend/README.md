# Poonsuk Resort — Backend API

NestJS + PostgreSQL + TypeORM backend replacing `lib/data/mock_data.dart`
in the Flutter app. See `docs/Backend_Design_Poonsuk_Resort.docx` for the
full architecture design.

## Sprint status

| Sprint | Scope | Status |
|---|---|---|
| 1 | Auth vertical slice (users, refresh_tokens, JWT, guards, health, Docker) | done |
| 2 | Rooms + Bookings, exclusion constraint, concurrency test | done |
| 3 | Redis cache / lock, BullMQ notifications, payments | done |
| 4 | Nginx LB, read-replica, observability | partial: Nginx reverse proxy + Sentry done; single API instance, no read-replica |

## Run locally

```bash
cp .env.example .env          # then edit the JWT secrets
docker compose up -d postgres redis
npm install
npm run migration:run
npm run start:dev             # http://localhost:3000
```

Full container run (API in Docker too):

```bash
docker compose up --build
```

## Endpoints in Sprint 1

| Method | Path | Notes |
|---|---|---|
| POST | `/api/auth/register` | returns access + refresh token + user |
| POST | `/api/auth/login` | same shape |
| POST | `/api/auth/refresh` | rotates the refresh token |
| POST | `/api/auth/logout` | revokes the refresh token (204) |
| GET | `/api/auth/me` | requires `Authorization: Bearer <access>` |
| GET | `/health/live` | liveness, no dependency check |
| GET | `/health/ready` | readiness, pings the database |

## Redis cache (room search)

`GET /api/rooms` and `GET /api/rooms/availability` are cache-aside in Redis
(`src/modules/cache`). Every response carries `X-Cache: HIT | MISS | BYPASS`.

- Key: `poonsuk:cache:rooms:v<version>:<sha1 of query params>`, TTL `CACHE_TTL_SECONDS` (60).
- Invalidation: one `INCR poonsuk:cache:rooms:version` after any committed write that
  changes availability (room create/update/photo/delete, booking create/reschedule/
  status/cancel/expiry, sweeper). Old keys become unreachable and expire on their own.
  The list of write paths lives in `src/modules/rooms/rooms-cache.ts`.
- Fail-open: if Redis is down or slow (> `CACHE_OP_TIMEOUT_MS`), requests read Postgres
  (`BYPASS`). Booking correctness never depends on the cache — `POST /api/bookings`
  re-checks inside its transaction and the exclusion constraint has the last word.
- Seed scripts and manual SQL do not invalidate; their changes appear within the TTL.

```powershell
curl.exe -i "http://localhost:3000/api/rooms?checkIn=2026-12-01&checkOut=2026-12-03"   # MISS, then HIT
docker compose exec redis sh -c 'redis-cli --scan --pattern "poonsuk:cache:*"'
```

## Redis lock (booking, per room)

`POST /api/bookings` and `PATCH /api/staff/bookings/:id` run their transaction under
`poonsuk:lock:room:<roomId>` (`src/modules/cache/redis-lock.service.ts`).

- One key per room: bookings for different rooms never wait on each other.
- Acquire `SET key <uuid> NX PX LOCK_TTL_MS`; release with a Lua compare-and-delete, so
  a request whose lock expired can never delete the next holder's lock.
- Held for the transaction only (milliseconds), not for the unpaid-hold period — the hold
  is the `pending` row. A second request for the same room retries every 20–50 ms for up
  to `LOCK_WAIT_MS`, then gets 503.
- Fail-open: Redis down → the booking runs without the lock; the exclusion constraint
  still makes overlaps impossible. The lock only stops same-room requests from different
  API instances from colliding inside Postgres.

## Conventions

- `synchronize` is permanently `false`. Every schema change is a migration:
  `npm run migration:generate -- src/migrations/<Name>`
- Passwords are bcrypt hashes (cost 12); `password_hash` is `select: false`.
- Refresh tokens are stored as sha256 hashes and rotated on every use.
- `ValidationPipe` runs with `whitelist` + `forbidNonWhitelisted` globally.
- Role checks: `@UseGuards(JwtAuthGuard, RolesGuard) @Roles(UserRole.ADMIN)`.

## Next step (Sprint 2)

1. `rooms` and `bookings` migrations — add the exclusion constraint first:
   `EXCLUDE USING gist (room_id WITH =, daterange(check_in, check_out, '[)') WITH &&) WHERE (status <> 'cancelled')`
2. `GET /api/rooms` availability search (no cache yet).
3. `POST /api/bookings` inside a SERIALIZABLE transaction.
4. Integration test: two concurrent bookings for the same room/date →
   exactly one 201 and one 409.
