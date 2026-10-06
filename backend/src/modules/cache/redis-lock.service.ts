import {
  Inject, Injectable, Logger, ServiceUnavailableException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { FAST_REDIS_CLIENT, withRedisTimeout } from './redis-client';

/** DI token for {@link LockOptions}. */
export const LOCK_OPTIONS = Symbol('LOCK_OPTIONS');

export interface LockOptions {
  enabled: boolean;
  /** Auto-expiry of a held lock (PX). Frees the room if the holder dies mid-request. */
  ttlMs: number;
  /** How long a request keeps retrying for a lock someone else holds before giving up with 503. */
  waitMs: number;
  /** A Redis call slower than this counts as "Redis unavailable". */
  opTimeoutMs: number;
}

/** The two Redis commands the lock needs. ioredis satisfies it; the unit test passes a fake. */
export interface LockClient {
  set(key: string, value: string, px: 'PX', ms: number, nx: 'NX'): Promise<'OK' | null>;
  eval(script: string, numKeys: number, ...args: string[]): Promise<unknown>;
}

/**
 * Delete the key only if it still holds our token. Without the check, a
 * request whose lock already expired would delete the NEXT holder's lock.
 */
const RELEASE_SCRIPT = `
if redis.call('get', KEYS[1]) == ARGV[1] then
  return redis.call('del', KEYS[1])
else
  return 0
end`;

/** Lock key for one room. Other rooms never share it, so they never wait on each other. */
export function roomLockKey(roomId: string): string {
  return `lock:room:${roomId}`;
}

/**
 * Single-instance Redis lock: `SET key token NX PX ttl` to acquire, a
 * compare-and-delete Lua script to release (design doc section 5).
 *
 * The lock is an ordering aid, not the guarantee. Double bookings are already
 * impossible because of the exclusion constraint; what the lock adds is that
 * requests for the SAME room from different API instances queue up in Redis
 * instead of colliding inside Postgres (serialization failures / deadlocks).
 * That is why it fails open: if Redis is down or slow, `withLock` runs the
 * work without a lock and the database still decides.
 *
 * Contention is handled by waiting, not rejecting: the holder only keeps the
 * lock for one short transaction, so a second request for the same room
 * (different dates, say) usually succeeds a few milliseconds later. Only if
 * the lock is still busy after `waitMs` does the caller get a 503.
 */
@Injectable()
export class RedisLockService {
  private readonly logger = new Logger(RedisLockService.name);
  private healthy = true;

  constructor(
    @Inject(FAST_REDIS_CLIENT) private readonly client: LockClient | null,
    @Inject(LOCK_OPTIONS) private readonly options: LockOptions,
  ) {}

  get enabled(): boolean {
    return this.options.enabled && this.client !== null;
  }

  async withLock<T>(key: string, work: () => Promise<T>): Promise<T> {
    if (!this.enabled) return work();

    const token = randomUUID();
    let acquired: boolean;
    try {
      acquired = await this.acquire(key, token);
    } catch (err) {
      this.markUnhealthy(err);
      return work();
    }
    if (!acquired) {
      throw new ServiceUnavailableException(
        'มีการจองห้องนี้กำลังดำเนินการอยู่ กรุณาลองใหม่อีกครั้ง',
      );
    }

    try {
      return await work();
    } finally {
      await this.release(key, token);
    }
  }

  /** true = acquired, false = still held by someone else after waitMs. Throws if Redis fails. */
  private async acquire(key: string, token: string): Promise<boolean> {
    const deadline = Date.now() + this.options.waitMs;
    for (;;) {
      const res = await withRedisTimeout(
        this.client!.set(key, token, 'PX', this.options.ttlMs, 'NX'),
        this.options.opTimeoutMs,
      );
      this.markHealthy();
      if (res === 'OK') return true;
      if (Date.now() >= deadline) return false;
      // Short, jittered pause so waiters don't retry in lockstep.
      await sleep(20 + Math.floor(Math.random() * 30));
    }
  }

  private async release(key: string, token: string): Promise<void> {
    try {
      const deleted = await withRedisTimeout(
        this.client!.eval(RELEASE_SCRIPT, 1, key, token),
        this.options.opTimeoutMs,
      );
      if (deleted !== 1) {
        // The work outlived ttlMs and someone else may have taken the lock.
        // Still safe (Postgres decides), but ttlMs is too short for this load.
        this.logger.warn(`lock ${key} expired before release; consider raising LOCK_TTL_MS`);
      }
    } catch (err) {
      // The key expires on its own after ttlMs.
      this.markUnhealthy(err);
    }
  }

  private markUnhealthy(err: unknown): void {
    if (!this.healthy) return;
    this.healthy = false;
    this.logger.warn(`Redis lock unavailable, continuing without it (Postgres still guards): ${String(err)}`);
  }

  private markHealthy(): void {
    if (this.healthy) return;
    this.healthy = true;
    this.logger.log('Redis lock available again');
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
