import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { getStorageToken } from '@nestjs/throttler';
import Redis from 'ioredis';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { ResilientThrottlerStorage } from '../src/common/throttler/resilient-throttler.storage';
import { getRedisConnection } from '../src/config/redis.config';

/**
 * Two API instances in one process stand in for two replicas behind Nginx.
 * They share one throttle bucket only if the counters live in Redis: with
 * the old in-memory store, instance B would start from zero and answer 401.
 *
 * THROTTLE_KEY_PREFIX makes both instances use the same keys on purpose
 * (other suites get a random prefix per app under NODE_ENV=test).
 *
 * Requires Postgres + Redis (docker compose up). Run with `npm run test:e2e`.
 */
describe('Throttler shared across replicas (e2e)', () => {
  const prefix = `poonsuk:throttle:shared-e2e:${Date.now()}:`;
  const savedPrefix = process.env.THROTTLE_KEY_PREFIX;
  let a: INestApplication;
  let b: INestApplication;

  const boot = async (): Promise<INestApplication> => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    const app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api', { exclude: ['health/live', 'health/ready'] });
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    // Otherwise the first hits could land in the in-memory fallback.
    await app.get<ResilientThrottlerStorage>(getStorageToken()).ready();
    return app;
  };

  // An address nobody registered: every attempt is a plain 401, no DB writes.
  const badLogin = (app: INestApplication) =>
    request(app.getHttpServer())
      .post('/api/auth/login')
      .send({ email: `nobody.${Date.now()}@example.com`, password: 'wrong-password' });

  beforeAll(async () => {
    process.env.THROTTLE_KEY_PREFIX = prefix;
    a = await boot();
    b = await boot();
  });

  afterAll(async () => {
    await a?.close();
    await b?.close();
    if (savedPrefix === undefined) delete process.env.THROTTLE_KEY_PREFIX;
    else process.env.THROTTLE_KEY_PREFIX = savedPrefix;

    const redis = new Redis(getRedisConnection());
    try {
      const keys = await redis.keys(`${prefix}*`);
      if (keys.length) await redis.del(...keys);
    } finally {
      redis.disconnect();
    }
  });

  it('login (10/min): 10 attempts on A use up the budget, so B answers 429', async () => {
    for (let i = 0; i < 10; i++) {
      await badLogin(a).expect(401);
    }
    await badLogin(b).expect(429);
  });

  it('A is blocked too: there is one bucket, not one per instance', async () => {
    await badLogin(a).expect(429);
  });
});
