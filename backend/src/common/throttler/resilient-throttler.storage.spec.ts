import { Logger } from '@nestjs/common';
import { ThrottlerStorage, ThrottlerStorageService } from '@nestjs/throttler';
import { ResilientThrottlerStorage } from './resilient-throttler.storage';

type Increment = ThrottlerStorage['increment'];

/** Stands in for the Redis storage: counts hits, or throws while `down`. */
class FakePrimary implements ThrottlerStorage {
  down = false;
  calls = 0;

  increment: Increment = async () => {
    this.calls++;
    if (this.down) throw new Error('connection refused');
    return { totalHits: this.calls, timeToExpire: 60, isBlocked: false, timeToBlockExpire: 0 };
  };
}

const hit = (s: ThrottlerStorage, key = 'ip-1') => s.increment(key, 60_000, 10, 60_000, 'default');

describe('ResilientThrottlerStorage', () => {
  let primary: FakePrimary;
  let fallback: ThrottlerStorageService;
  let onShutdown: jest.Mock;
  let storage: ResilientThrottlerStorage;
  let warn: jest.SpyInstance;

  beforeEach(() => {
    primary = new FakePrimary();
    fallback = new ThrottlerStorageService();
    onShutdown = jest.fn();
    storage = new ResilientThrottlerStorage(primary, fallback, onShutdown);
    warn = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    storage.onApplicationShutdown(); // clears the in-memory sweep timer
    warn.mockRestore();
  });

  it('counts in the primary (Redis) store while it is up', async () => {
    await hit(storage);
    const second = await hit(storage);

    expect(second.totalHits).toBe(2);
    expect(primary.calls).toBe(2);
    expect(fallback.storage.size).toBe(0);
  });

  it('falls back to memory instead of throwing when the primary fails', async () => {
    primary.down = true;

    await expect(hit(storage)).resolves.toMatchObject({ totalHits: 1, isBlocked: false });
    const second = await hit(storage);

    expect(second.totalHits).toBe(2); // the fallback keeps its own count
    expect(fallback.storage.size).toBeGreaterThan(0);
  });

  it('still blocks over the limit while on the fallback', async () => {
    primary.down = true;
    let last = await hit(storage);
    for (let i = 0; i < 10; i++) last = await hit(storage);

    expect(last.isBlocked).toBe(true);
  });

  it('warns at most once a minute, however many requests fall back', async () => {
    primary.down = true;
    for (let i = 0; i < 5; i++) await hit(storage, `ip-${i}`);

    expect(warn).toHaveBeenCalledTimes(1);
  });

  it('goes back to the primary as soon as it recovers', async () => {
    primary.down = true;
    await hit(storage);
    primary.down = false;

    const back = await hit(storage);
    expect(back.totalHits).toBe(primary.calls);
  });

  it('ready() waits for the Redis connection', async () => {
    let connect!: () => void;
    const connected = new Promise<void>((r) => (connect = r));
    const s = new ResilientThrottlerStorage(primary, new ThrottlerStorageService(), undefined, () => connected);

    let done = false;
    const pending = s.ready().then(() => (done = true));
    await Promise.resolve();
    expect(done).toBe(false);

    connect();
    await pending;
    expect(done).toBe(true);
    s.onApplicationShutdown();
  });

  it('closes the Redis connection on shutdown', () => {
    storage.onApplicationShutdown();
    expect(onShutdown).toHaveBeenCalled();
  });
});
