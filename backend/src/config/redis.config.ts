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
export function withQueueTimeout<T>(pending: Promise<T>, ms = 2000): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`Redis did not respond within ${ms}ms`)), ms);
  });
  return Promise.race([pending, timeout]).finally(() => clearTimeout(timer));
}
