/**
 * DI token for the "fail-fast" Redis connection shared by RedisCacheService
 * and RedisLockService. Null when both the cache and the lock are disabled.
 *
 * It is a separate connection from BullMQ's on purpose: BullMQ needs an
 * offline queue and endless retries, while a cache or a lock needs the
 * opposite — with the offline queue disabled a dead Redis fails a command at
 * once and the request carries on without Redis instead of waiting.
 */
export const FAST_REDIS_CLIENT = Symbol('FAST_REDIS_CLIENT');

/** Rejects if `pending` has not settled within `ms`. */
export function withRedisTimeout<T>(pending: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`Redis did not respond within ${ms}ms`)), ms);
  });
  return Promise.race([pending, timeout]).finally(() => clearTimeout(timer));
}
