import { Logger, OnApplicationShutdown } from '@nestjs/common';
import { ThrottlerStorage, ThrottlerStorageService } from '@nestjs/throttler';
import { ThrottlerStorageRedisService } from '@nest-lab/throttler-storage-redis';
import Redis from 'ioredis';
import { getRedisConnection, getThrottleKeyPrefix } from '../../config/redis.config';

/** Not exported from the @nestjs/throttler root, so derive it instead of importing from dist/. */
type ThrottlerStorageRecord = Awaited<ReturnType<ThrottlerStorage['increment']>>;

/**
 * Shared per-IP counters in Redis, so every API replica counts the same
 * bucket. If Redis is unreachable, falls back to this process's memory:
 * limits become per-replica for a while instead of every request failing.
 */
export class ResilientThrottlerStorage implements ThrottlerStorage, OnApplicationShutdown {
  private readonly logger = new Logger(ResilientThrottlerStorage.name);
  private lastWarn = 0;

  constructor(
    private readonly primary: ThrottlerStorage,
    private readonly fallback = new ThrottlerStorageService(),
    private readonly onShutdown: () => void = () => undefined,
    private readonly whenReady: () => Promise<void> = () => Promise.resolve(),
  ) {}

  /**
   * Resolves once the Redis connection is up. Requests before that use the
   * in-memory fallback, which is harmless in production but makes a test
   * that counts hits across two instances flaky, so tests await this.
   */
  ready(): Promise<void> {
    return this.whenReady();
  }

  async increment(
    key: string,
    ttl: number,
    limit: number,
    blockDuration: number,
    throttlerName: string,
  ): Promise<ThrottlerStorageRecord> {
    try {
      return await this.primary.increment(key, ttl, limit, blockDuration, throttlerName);
    } catch (err) {
      // At most one warning a minute, however many requests fall back.
      if (Date.now() - this.lastWarn > 60_000) {
        this.lastWarn = Date.now();
        this.logger.warn(`Redis throttler unavailable, using in-memory: ${(err as Error).message}`);
      }
      return this.fallback.increment(key, ttl, limit, blockDuration, throttlerName);
    }
  }

  /**
   * Nest calls this for the storage ThrottlerModule provides. Without it the
   * Redis socket and the in-memory sweep timer keep the process (and Jest) alive.
   */
  onApplicationShutdown(): void {
    this.fallback.onApplicationShutdown();
    this.onShutdown();
  }
}

/**
 * Fail-fast client like FAST_REDIS_CLIENT in RedisCacheModule: no offline
 * queue and no retries, so a Redis outage costs a request one failed call
 * (then the in-memory fallback) instead of a hang.
 */
export function createRedisThrottlerStorage(): ResilientThrottlerStorage {
  const client = new Redis({
    ...getRedisConnection(),
    enableOfflineQueue: false,
    maxRetriesPerRequest: 0,
    connectTimeout: 2000,
    keyPrefix: getThrottleKeyPrefix(),
  });
  // ioredis keeps reconnecting in the background; don't log every failure.
  client.on('error', () => undefined);
  return new ResilientThrottlerStorage(
    new ThrottlerStorageRedisService(client),
    undefined,
    () => client.disconnect(),
    () =>
      client.status === 'ready'
        ? Promise.resolve()
        : new Promise<void>((resolve) => client.once('ready', () => resolve())),
  );
}
