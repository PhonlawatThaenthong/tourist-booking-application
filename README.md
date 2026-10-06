# Mobile App Final Project

Monorepo. Two independent applications side by side:

```
mobile-app-final-project/
├── frontend/   Flutter app (flutter_bloc) — the mobile client
├── backend/    NestJS + PostgreSQL + TypeORM API
```

## frontend/

```bash
cd frontend
flutter clean          # required once after the move — clears stale absolute paths
flutter pub get
flutter run
```

Demo accounts (mock data): `admin@hotel.com / admin123`,
`staff@hotel.com / staff123`, `customer@hotel.com / customer123`

The data layer sits behind `lib/repositories/`. `lib/main.dart` is the single
place where implementations are chosen — swapping `MockAuthRepository` for an
HTTP one is the whole of Phase 2.

## backend/

```bash
cd backend
copy .env.example .env
npm install
docker compose up -d postgres redis
npm run migration:run
npm run start:dev      # http://localhost:3000
```

See `backend/README.md` for endpoints and conventions.

## Migration status

| Sprint | Scope | Status |
|---|---|---|
| 0 | Repository abstraction in the Flutter app | done |
| 1 | Backend auth vertical slice | done |
| 2 | Rooms + bookings, double-booking prevention | done |
| 3 | Flutter switches to the real API | done |
| 4 | Redis, BullMQ, payments, load balancing, observability | partial: Redis, BullMQ, payments, Nginx and Sentry done; single API instance, no load balancing yet |
