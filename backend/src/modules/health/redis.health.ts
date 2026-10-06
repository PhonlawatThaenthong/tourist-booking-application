import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { HealthCheckError, HealthIndicator, HealthIndicatorResult } from '@nestjs/terminus';
import Redis from 'ioredis';
import { getRedisConnection } from '../../config/redis.config';

/**
 * PINGs the Redis that backs the BullMQ queues. Uses its own client with the
 * offline queue disabled so a dead Redis fails the check immediately instead
 * of buffering the PING until the timeout.
 */
@Injectable()
export class RedisHealthIndicator extends HealthIndicator implements OnModuleDestroy {
  private readonly client = new Redis({
    ...getRedisConnection(),
    lazyConnect: true,
    enableOfflineQueue: false,
    maxRetriesPerRequest: 0,
  });

  constructor() {
    super();
    // Without a listener ioredis logs every reconnect failure as unhandled.
    this.client.on('error', () => undefined);
  }

  async pingCheck(key: string, timeoutMs: number): Promise<HealthIndicatorResult> {
    try {
      if (this.client.status === 'wait') await this.client.connect();
      await Promise.race([
        this.client.ping(),
        new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), timeoutMs)),
      ]);
      return this.getStatus(key, true);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      throw new HealthCheckError('Redis ping failed', this.getStatus(key, false, { message }));
    }
  }

  onModuleDestroy(): void {
    this.client.disconnect();
  }
}
