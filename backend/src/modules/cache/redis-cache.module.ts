import { Global, Inject, Module, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import {
  getCacheOptions, getLockOptions, getRedisConnection,
} from '../../config/redis.config';
import { CACHE_OPTIONS, CacheOptions, RedisCacheService } from './redis-cache.service';
import { LOCK_OPTIONS, LockOptions, RedisLockService } from './redis-lock.service';
import { FAST_REDIS_CLIENT } from './redis-client';

/**
 * Redis cache (room search) and Redis lock (booking per room), sharing one
 * fail-fast connection. Global so any module can inject either service —
 * invalidation and locking happen wherever rooms or bookings are written.
 */
@Global()
@Module({
  providers: [
    { provide: CACHE_OPTIONS, useFactory: getCacheOptions },
    { provide: LOCK_OPTIONS, useFactory: getLockOptions },
    {
      provide: FAST_REDIS_CLIENT,
      inject: [CACHE_OPTIONS, LOCK_OPTIONS],
      useFactory: (cache: CacheOptions, lock: LockOptions): Redis | null => {
        if (!cache.enabled && !lock.enabled) return null;
        const client = new Redis({
          ...getRedisConnection(),
          enableOfflineQueue: false,
          maxRetriesPerRequest: 0,
          connectTimeout: 2000,
          // Applies to plain keys and to the KEYS of EVAL alike.
          keyPrefix: 'poonsuk:',
        });
        // Without a listener ioredis logs every reconnect failure as unhandled.
        // It keeps reconnecting in the background, so both features recover by themselves.
        client.on('error', () => undefined);
        return client;
      },
    },
    RedisCacheService,
    RedisLockService,
  ],
  exports: [RedisCacheService, RedisLockService],
})
export class RedisCacheModule implements OnModuleDestroy {
  constructor(@Inject(FAST_REDIS_CLIENT) private readonly client: Redis | null) {}

  onModuleDestroy(): void {
    this.client?.disconnect();
  }
}
