import { Module } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
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
import { buildDataSourceOptions } from './config/data-source';
import { getRedisConnection } from './config/redis.config';

@Module({
  imports: [
    // First in the list so it wraps every module below it.
    // A no-op unless src/instrument.ts found a DSN.
    SentryModule.forRoot(),
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRoot(buildDataSourceOptions()),
    BullModule.forRoot({ connection: getRedisConnection() }),
    AuthModule,
    UsersModule,
    HealthModule,
    RoomsModule,
    BookingsModule,
    RestaurantsModule,
    PaymentsModule,
    NotificationsModule,
  ],
  providers: [
    // Reports unhandled exceptions, then rethrows so Nest's own error
    // handling is unchanged. Deliberate HttpExceptions (the 409 a losing
    // double-booking gets, a 401, a 400 from ValidationPipe) are not
    // reported — only 5xx and genuinely unhandled throws are.
    { provide: APP_FILTER, useClass: SentryGlobalFilter },
  ],
})
export class AppModule {}
