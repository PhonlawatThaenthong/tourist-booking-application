import { CacheClient, CacheOptions, RedisCacheService, fingerprint } from './redis-cache.service';

/** In-memory stand-in for the three Redis commands the cache uses. */
class FakeRedis implements CacheClient {
  readonly store = new Map<string, string>();
  readonly ttls = new Map<string, number>();
  down = false;

  async get(key: string) {
    this.check();
    return this.store.get(key) ?? null;
  }
  async set(key: string, value: string, _mode: 'EX', seconds: number) {
    this.check();
    this.store.set(key, value);
    this.ttls.set(key, seconds);
    return 'OK';
  }
  async incr(key: string) {
    this.check();
    const next = Number(this.store.get(key) ?? 0) + 1;
    this.store.set(key, String(next));
    return next;
  }
  private check() {
    if (this.down) throw new Error('connection refused');
  }
}

const OPTIONS: CacheOptions = { enabled: true, ttlSeconds: 60, opTimeoutMs: 50 };

describe('RedisCacheService', () => {
  let redis: FakeRedis;
  let cache: RedisCacheService;
  let dbReads: number;
  const loader = async () => {
    dbReads += 1;
    return [{ id: 'room-1', createdAt: new Date('2026-10-01T00:00:00Z') }];
  };

  beforeEach(() => {
    redis = new FakeRedis();
    cache = new RedisCacheService(redis, OPTIONS);
    dbReads = 0;
  });

  it('misses, then serves the same params from Redis without touching the loader', async () => {
    const first = await cache.getOrLoad('rooms', { type: 'twin' }, loader);
    const second = await cache.getOrLoad('rooms', { type: 'twin' }, loader);

    expect(first.status).toBe('MISS');
    expect(second.status).toBe('HIT');
    expect(dbReads).toBe(1);
    // JSON round trip: identical to what the HTTP response would serialise.
    expect(second.value).toEqual(JSON.parse(JSON.stringify(first.value)));
  });

  it('stores entries with the configured TTL', async () => {
    await cache.getOrLoad('rooms', { a: 1 }, loader);
    const dataKey = [...redis.ttls.keys()].find((k) => k.startsWith('cache:rooms:v0:'));
    expect(dataKey).toBeDefined();
    expect(redis.ttls.get(dataKey!)).toBe(60);
  });

  it('keeps different params apart', async () => {
    await cache.getOrLoad('rooms', { type: 'twin' }, loader);
    const other = await cache.getOrLoad('rooms', { type: 'single' }, loader);
    expect(other.status).toBe('MISS');
    expect(dbReads).toBe(2);
  });

  it('invalidate makes every entry of the namespace a miss, and only that namespace', async () => {
    await cache.getOrLoad('rooms', { type: 'twin' }, loader);
    await cache.getOrLoad('other', { x: 1 }, loader);

    await cache.invalidate('rooms');

    expect((await cache.getOrLoad('rooms', { type: 'twin' }, loader)).status).toBe('MISS');
    expect((await cache.getOrLoad('other', { x: 1 }, loader)).status).toBe('HIT');
  });

  it('a slow reader that stores after an invalidation cannot resurrect stale data', async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    // Reader reads the version, then stalls in the database...
    const slow = cache.getOrLoad('rooms', { q: 1 }, async () => {
      await gate;
      return ['stale'];
    });
    await new Promise((r) => setImmediate(r));
    // ...a booking commits and invalidates meanwhile...
    await cache.invalidate('rooms');
    release();
    await slow;
    // ...so the next reader must not get what the slow one stored.
    const next = await cache.getOrLoad('rooms', { q: 1 }, async () => ['fresh']);
    expect(next).toEqual({ value: ['fresh'], status: 'MISS' });
  });

  it('falls back to the loader when Redis is down, and invalidate does not throw', async () => {
    redis.down = true;

    const res = await cache.getOrLoad('rooms', { type: 'twin' }, loader);
    expect(res.status).toBe('BYPASS');
    expect(res.value).toHaveLength(1);
    await expect(cache.invalidate('rooms')).resolves.toBeUndefined();
  });

  it('treats a Redis call slower than opTimeoutMs as a failure', async () => {
    redis.get = () => new Promise(() => undefined); // never answers
    const res = await cache.getOrLoad('rooms', {}, loader);
    expect(res.status).toBe('BYPASS');
    expect(dbReads).toBe(1);
  });

  it('propagates loader errors instead of hiding them', async () => {
    await expect(
      cache.getOrLoad('rooms', {}, async () => {
        throw new Error('postgres down');
      }),
    ).rejects.toThrow('postgres down');
  });

  it('bypasses Redis completely when disabled', async () => {
    const off = new RedisCacheService(null, { ...OPTIONS, enabled: false });
    const res = await off.getOrLoad('rooms', {}, loader);
    expect(res.status).toBe('BYPASS');
    await off.invalidate('rooms');
    expect(redis.store.size).toBe(0);
  });
});

describe('fingerprint', () => {
  it('ignores key order and empty values', () => {
    expect(fingerprint({ a: 1, b: 'x', c: undefined })).toBe(fingerprint({ b: 'x', a: 1, d: '' }));
  });

  it('distinguishes different values', () => {
    expect(fingerprint({ guests: 2 })).not.toBe(fingerprint({ guests: 3 }));
  });
});
