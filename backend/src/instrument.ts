/**
 * Sentry bootstrap.
 *
 * MUST be the very first import in main.ts. The SDK patches `http`, Express
 * and `pg` as it loads, and anything imported before it stays uninstrumented —
 * which is why this lives in its own file instead of at the top of main.ts.
 *
 * No `SENTRY_DSN` in the environment means Sentry never initialises at all.
 * That is the default for `npm run start:dev` and for CI, so noise from dev
 * machines and from the e2e suite never reaches the project and never eats
 * the free tier's monthly error budget.
 */
import * as Sentry from '@sentry/nestjs';
import { config as loadEnv } from 'dotenv';

// `nest start` does not read .env, and ConfigModule.forRoot() only runs once
// AppModule is constructed — which is long after this file. Without this the
// DSN below is always undefined under `npm run start:dev`, and Sentry silently
// never initialises. Same idiom as config/data-source.ts. In production the
// variables come from the real environment and this call is a no-op.
loadEnv();

const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment:
      process.env.SENTRY_ENVIRONMENT ?? process.env.NODE_ENV ?? 'development',
    // Set by the deploy pipeline (to the commit SHA) so a stack trace can be
    // tied back to the exact code that produced it.
    release: process.env.SENTRY_RELEASE,
    // Traces are sampled far below errors on purpose: performance events are
    // what actually burns through a free-tier quota, crashes are not.
    tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? 0.1),
    // Slip uploads carry payment images and auth headers — keep request
    // bodies, cookies and user identifiers out of the reports. (Replaces the
    // deprecated `sendDefaultPii: false`, which SDK 10.57+ supersedes with
    // this finer-grained object.)
    dataCollection: {
      userInfo: false,
      httpBodies: [],
      httpHeaders: { request: false, response: false },
      cookies: false,
    },
    // Structured logs, correlated with the errors and traces above.
    enableLogs: true,
  });
}
