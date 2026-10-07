import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { SentryGlobalFilter, SentryModule } from '@sentry/nestjs/setup';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bullmq';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { HealthModule } from './modules/health/health.module';
import { RoomsModule } from './modules/rooms/rooms.module';
import { BookingsModule } from './modules/bookings/bookings.module';
import { RestaurantsModule } from './modules/restaurants/restaurants.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { RedisCacheModule } from './modules/cache/redis-cache.module';
import { ReportsModule } from './modules/reports/reports.module';
import { ChatbotModule } from './modules/chatbot/chatbot.module';
import { InternalAwareThrottlerGuard } from './common/guards/internal-aware-throttler.guard';
import { createRedisThrottlerStorage } from './common/throttler/resilient-throttler.storage';
import { buildDataSourceOptions } from './config/data-source';
import { getRedisConnection } from './config/redis.config';

@Module({
  imports: [
    // First in the list so it wraps every module below it.
    // A no-op unless src/instrument.ts found a DSN.
    SentryModule.forRoot(),
    ConfigModule.forRoot({ isGlobal: true }),
    // Per-IP counters in Redis, shared by every API replica (falls back to
    // in-memory if Redis is down). Sensitive routes (login, password reset,
    // QR, chatbot) tighten this with @Throttle.
    ThrottlerModule.forRootAsync({
      useFactory: () => ({
        throttlers: [{ name: 'default', ttl: 60_000, limit: 120 }],
        errorMessage: 'คำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
        storage: createRedisThrottlerStorage(),
      }),
    }),
    TypeOrmModule.forRoot(buildDataSourceOptions()),
    BullModule.forRoot({ connection: getRedisConnection() }),
    RedisCacheModule,
    AuthModule,
    UsersModule,
    HealthModule,
    RoomsModule,
    BookingsModule,
    RestaurantsModule,
    PaymentsModule,
    NotificationsModule,
    ReportsModule,
    ChatbotModule,
  ],
  providers: [
    // Reports unhandled exceptions, then rethrows so Nest's own error
    // handling is unchanged. Deliberate HttpExceptions (the 409 a losing
    // double-booking gets, a 401, a 400 from ValidationPipe) are not
    // reported — only 5xx and genuinely unhandled throws are.
    { provide: APP_FILTER, useClass: SentryGlobalFilter },
    // The chatbot's tool calls all arrive from its container's single IP, so
    // GETs carrying X-Internal-Key (= CHATBOT_INTERNAL_KEY) are not counted.
    // A shared secret, not an IP exemption: Docker Desktop NATs external
    // traffic on the published port to the same 172.x gateway, so exempting
    // that range would switch rate limiting off for everyone. The real limit
    // for chat traffic sits on POST /api/chatbot/query instead.
    { provide: APP_GUARD, useClass: InternalAwareThrottlerGuard },
  ],
})
export class AppModule {}
