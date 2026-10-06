import { Inject, Injectable, Logger } from '@nestjs/common';
import { createHash } from 'crypto';
import { FAST_REDIS_CLIENT, withRedisTimeout } from './redis-client';

/** DI token for {@link CacheOptions}. */
export const CACHE_OPTIONS = Symbol('CACHE_OPTIONS');

export interface CacheOptions {
  enabled: boolean;
  /** Lifetime of one cached response. Also the worst-case staleness if an invalidation is lost. */
  ttlSeconds: number;
  /** A Redis call slower than this is treated as a failure and the request goes to Postgres. */
  opTimeoutMs: number;
}

/**
 * The three Redis commands the cache needs. ioredis satisfies it; the unit
 * test passes an in-memory fake.
 */
export interface CacheClient {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, mode: 'EX', seconds: number): Promise<unknown>;
  incr(key: string): Promise<number>;
}

/**
 * HIT    served from Redis
 * MISS   loaded from Postgres and stored for the next caller
 * BYPASS loaded from Postgres without touching Redis (caching off, or Redis unavailable)
 */
export type CacheStatus = 'HIT' | 'MISS' | 'BYPASS';

export interface Cached<T> {
  value: T;
  status: CacheStatus;
}

/**
 * Cache-aside over Redis with namespace versioning (design doc, section 5).
 *
 * Keys look like `cache:<namespace>:v<version>:<hash of params>`. Invalidating
 * a namespace is a single INCR of its version counter: every key written under
 * the old version becomes unreachable at once and expires on its own TTL. That
 * avoids SCAN/DEL over an unknown key set, and it removes the classic
 * cache-aside race — a slow reader that loaded data before a write and stores
 * it after the INCR writes under the old version, where nobody reads it.
 *
 * Fail-open by design. The cache only speeds up reads; Postgres stays the
 * source of truth (booking correctness rests on the exclusion constraint, not
 * on anything cached). So any Redis error or timeout degrades to a direct
 * database read, and `invalidate` never throws — it runs after a committed
 * write, and failing that request would report an error for a change that
 * already happened.
 *
 * Values go through JSON, so `Date` fields come back as ISO strings. That is
 * what the HTTP response would contain anyway, which is why this is meant for
 * data that goes straight to a response, not for objects code keeps using.
 */
@Injectable()
export class RedisCacheService {
  private readonly logger = new Logger(RedisCacheService.name);
  private healthy = true;

  constructor(
    @Inject(FAST_REDIS_CLIENT) private readonly client: CacheClient | null,
    @Inject(CACHE_OPTIONS) private readonly options: CacheOptions,
  ) {}

  get enabled(): boolean {
    return this.options.enabled && this.client !== null;
  }

  async getOrLoad<T>(
    namespace: string,
    params: Record<string, unknown>,
    loader: () => Promise<T>,
  ): Promise<Cached<T>> {
    if (!this.enabled) return { value: await loader(), status: 'BYPASS' };
    const client = this.client!;

    let key: string;
    try {
      const version = (await this.timed(client.get(versionKey(namespace)))) ?? '0';
      key = `cache:${namespace}:v${version}:${fingerprint(params)}`;
      const raw = await this.timed(client.get(key));
      this.markHealthy();
      if (raw !== null) return { value: JSON.parse(raw) as T, status: 'HIT' };
    } catch (err) {
      this.markUnhealthy(err);
      return { value: await loader(), status: 'BYPASS' };
    }

    // Loader errors (a bad query, Postgres down) propagate untouched.
    const value = await loader();
    try {
      await this.timed(client.set(key, JSON.stringify(value), 'EX', this.options.ttlSeconds));
    } catch (err) {
      this.markUnhealthy(err);
    }
    return { value, status: 'MISS' };
  }

  /** Drop every cached entry of a namespace. Call after the write has committed. */
  async invalidate(namespace: string): Promise<void> {
    if (!this.enabled) return;
    try {
      await this.timed(this.client!.incr(versionKey(namespace)));
      this.markHealthy();
    } catch (err) {
      // Entries under the old version live at most ttlSeconds more.
      this.markUnhealthy(err);
    }
  }

  private timed<T>(pending: Promise<T>): Promise<T> {
    return withRedisTimeout(pending, this.options.opTimeoutMs);
  }

  /** Log state changes only, so a Redis outage is one warning, not one per request. */
  private markUnhealthy(err: unknown): void {
    if (!this.healthy) return;
    this.healthy = false;
    this.logger.warn(`Redis cache unavailable, reading from Postgres directly: ${String(err)}`);
  }

  private markHealthy(): void {
    if (this.healthy) return;
    this.healthy = true;
    this.logger.log('Redis cache available again');
  }
}

function versionKey(namespace: string): string {
  return `cache:${namespace}:version`;
}

/**
 * Order-independent hash of the query parameters, ignoring undefined values,
 * so `?type=twin&guests=2` and `?guests=2&type=twin` share one entry.
 */
export function fingerprint(params: Record<string, unknown>): string {
  const canonical = Object.keys(params)
    .filter((k) => params[k] !== undefined && params[k] !== null && params[k] !== '')
    .sort()
    .map((k) => [k, params[k]]);
  return createHash('sha1').update(JSON.stringify(canonical)).digest('hex').slice(0, 20);
}
