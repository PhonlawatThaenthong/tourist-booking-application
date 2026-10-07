import { randomUUID } from 'crypto';
/**
 * bullmq wants host/port (or an ioredis instance), not a bare URL, so this
 * parses `REDIS_URL` once for BullModule.forRoot. docker-compose.yml sets
 * `REDIS_URL=redis://redis:6379` automatically when the API itself runs in
 * the compose network; the default here matches the `6379:6379` host mapping
 * for running the API on the host instead.
 */
export function getRedisConnection() {
  const url = new URL(process.env.REDIS_URL ?? 'redis://localhost:6379');
  return {
    host: url.hostname,
    port: Number(url.port || 6379),
    password: url.password || undefined,
  };
}

/**
 * Cap on how long a request waits for `queue.add`. bullmq's ioredis client
 * buffers commands while Redis is down and keeps retrying for minutes, so
 * without this an HTTP request that enqueues a job hangs instead of failing.
 * The buffered add may still land later if Redis comes back.
 */
/**
 * Room-search cache (RedisCacheModule). The design doc asks for a 30-60 s TTL:
 * long enough to absorb bursts of identical searches, short enough that a
 * missed invalidation heals itself quickly. `CACHE_ENABLED=false` turns the
 * cache off entirely (every read goes to Postgres, X-Cache: BYPASS).
 */
export function getCacheOptions() {
  const ttl = Number(process.env.CACHE_TTL_SECONDS ?? 60);
  const timeout = Number(process.env.CACHE_OP_TIMEOUT_MS ?? 250);
  return {
    enabled: (process.env.CACHE_ENABLED ?? 'true').toLowerCase() !== 'false',
    ttlSeconds: Number.isFinite(ttl) && ttl > 0 ? Math.floor(ttl) : 60,
    opTimeoutMs: Number.isFinite(timeout) && timeout > 0 ? timeout : 250,
  };
}

/**
 * Per-room booking lock (RedisLockService). The lock is held for one short
 * transaction, so a 5 s TTL is generous; it only matters if the holder dies.
 * `LOCK_WAIT_MS` is how long a second request for the same room waits before
 * a 503. `LOCK_ENABLED=false` skips the lock (Postgres still prevents overlaps).
 */
export function getLockOptions() {
  const num = (name: string, fallback: number) => {
    const v = Number(process.env[name] ?? fallback);
    return Number.isFinite(v) && v > 0 ? v : fallback;
  };
  return {
    enabled: (process.env.LOCK_ENABLED ?? 'true').toLowerCase() !== 'false',
    ttlMs: num('LOCK_TTL_MS', 5000),
    waitMs: num('LOCK_WAIT_MS', 2000),
    opTimeoutMs: num('CACHE_OP_TIMEOUT_MS', 250),
  };
}

export function withQueueTimeout<T>(pending: Promise<T>, ms = 2000): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`Redis did not respond within ${ms}ms`)), ms);
  });
  return Promise.race([pending, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Key prefix for throttler counters. In tests every app instance gets its
 * own prefix (same isolation the in-memory store gave), unless a test sets
 * THROTTLE_KEY_PREFIX to make two instances share one bucket on purpose.
 */
export function getThrottleKeyPrefix(): string {
  if (process.env.THROTTLE_KEY_PREFIX) return process.env.THROTTLE_KEY_PREFIX;
  return process.env.NODE_ENV === 'test'
    ? `poonsuk:throttle:test:${randomUUID()}:`
    : 'poonsuk:throttle:';
}