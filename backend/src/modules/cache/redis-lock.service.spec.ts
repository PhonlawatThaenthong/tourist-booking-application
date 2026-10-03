import { ServiceUnavailableException } from '@nestjs/common';
import { LockClient, LockOptions, RedisLockService, roomLockKey } from './redis-lock.service';

/** In-memory SET NX PX + compare-and-delete, with real expiry. */
class FakeRedis implements LockClient {
  readonly keys = new Map<string, { value: string; expiresAt: number }>();
  down = false;

  async set(key: string, value: string, _px: 'PX', ms: number, _nx: 'NX') {
    if (this.down) throw new Error('connection refused');
    const cur = this.keys.get(key);
    if (cur && cur.expiresAt > Date.now()) return null;
    this.keys.set(key, { value, expiresAt: Date.now() + ms });
    return 'OK' as const;
  }

  async eval(_script: string, _n: number, key: string, token: string) {
    if (this.down) throw new Error('connection refused');
    const cur = this.keys.get(key);
    if (cur && cur.expiresAt > Date.now() && cur.value === token) {
      this.keys.delete(key);
      return 1;
    }
    return 0;
  }
}

const OPTIONS: LockOptions = { enabled: true, ttlMs: 5000, waitMs: 1000, opTimeoutMs: 50 };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe('RedisLockService', () => {
  let redis: FakeRedis;
  let locks: RedisLockService;

  beforeEach(() => {
    redis = new FakeRedis();
    locks = new RedisLockService(redis, OPTIONS);
  });

  /** Runs `ms` of work under the lock and records when it started and ended. */
  const timedWork = (key: string, ms: number, log: string[], name: string) =>
    locks.withLock(key, async () => {
      log.push(`${name}:start`);
      await sleep(ms);
      log.push(`${name}:end`);
      return name;
    });

  it('uses one key per room', () => {
    expect(roomLockKey('abc')).toBe('lock:room:abc');
  });

  it('runs requests for DIFFERENT rooms in parallel', async () => {
    const log: string[] = [];
    const t0 = Date.now();
    await Promise.all([
      timedWork(roomLockKey('room-A'), 150, log, 'A'),
      timedWork(roomLockKey('room-B'), 150, log, 'B'),
    ]);
    // Both started before either finished, and the pair took ~one work unit.
    expect(log.slice(0, 2).sort()).toEqual(['A:start', 'B:start']);
    expect(Date.now() - t0).toBeLessThan(280);
  });

  it('serialises requests for the SAME room and both succeed', async () => {
    const log: string[] = [];
    const results = await Promise.all([
      timedWork(roomLockKey('room-A'), 100, log, 'first'),
      timedWork(roomLockKey('room-A'), 100, log, 'second'),
    ]);
    expect(results.sort()).toEqual(['first', 'second']);
    // Never interleaved: each start is followed by its own end.
    expect(log[0].split(':')[0]).toBe(log[1].split(':')[0]);
    expect(log[2].split(':')[0]).toBe(log[3].split(':')[0]);
  });

  it('releases the lock after the work, also when the work throws', async () => {
    await locks.withLock('lock:room:x', async () => 1);
    await expect(
      locks.withLock('lock:room:x', async () => {
        throw new Error('db failed');
      }),
    ).rejects.toThrow('db failed');
    expect(redis.keys.has('lock:room:x')).toBe(false);
  });

  it('gives up with 503 when the room stays locked longer than waitMs', async () => {
    const short = new RedisLockService(redis, { ...OPTIONS, waitMs: 100 });
    await redis.set('lock:room:busy', 'someone-else', 'PX', 5000, 'NX');
    const t0 = Date.now();
    await expect(short.withLock('lock:room:busy', async () => 'never')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(Date.now() - t0).toBeGreaterThanOrEqual(100);
  });

  it('takes over a lock whose holder died, once its TTL runs out', async () => {
    const ttl = new RedisLockService(redis, { ...OPTIONS, ttlMs: 80 });
    await redis.set('lock:room:y', 'crashed-holder', 'PX', 80, 'NX');
    await expect(ttl.withLock('lock:room:y', async () => 'ok')).resolves.toBe('ok');
  });

  it("never deletes another request's lock after its own expired", async () => {
    const ttl = new RedisLockService(redis, { ...OPTIONS, ttlMs: 50 });
    await ttl.withLock('lock:room:z', async () => {
      await sleep(80); // our lock expires mid-work...
      await redis.set('lock:room:z', 'next-holder', 'PX', 5000, 'NX'); // ...and someone takes it
    });
    expect(redis.keys.get('lock:room:z')?.value).toBe('next-holder');
  });

  it('runs the work without a lock when Redis is down (Postgres still guards)', async () => {
    redis.down = true;
    await expect(locks.withLock('lock:room:a', async () => 'done')).resolves.toBe('done');
  });

  it('runs the work without a lock when disabled', async () => {
    const off = new RedisLockService(null, { ...OPTIONS, enabled: false });
    await expect(off.withLock('lock:room:a', async () => 'done')).resolves.toBe('done');
  });
});
