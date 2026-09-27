import { Logger } from '@nestjs/common';

const DEV_FALLBACK_SECRET = 'change-me-access-secret';

/**
 * Single source for the access-token secret so the signer (AuthService) and
 * the verifier (JwtStrategy) can never disagree on it — they used to read
 * `process.env.JWT_ACCESS_SECRET` independently with different fallbacks,
 * which meant signing worked while every verification failed whenever the
 * env var was unset.
 *
 * A function, not a top-level constant: AuthModule is required before
 * `config/data-source.ts` in AppModule's import list (see app.module.ts), so
 * a value computed at module-load time would read `process.env` before
 * `dotenv.config()` (called from data-source.ts) has populated it from
 * `.env`. Reading it lazily, at actual call time, happens well after the
 * whole module graph — dotenv included — has finished loading.
 */
export function getJwtAccessSecret(): string {
  const fromEnv = process.env.JWT_ACCESS_SECRET;
  if (fromEnv) return fromEnv;
  // A publicly known signing key lets anyone mint an admin token.
  if (process.env.NODE_ENV === 'production') {
    throw new Error('JWT_ACCESS_SECRET must be set when NODE_ENV=production');
  }
  Logger.warn(
    'JWT_ACCESS_SECRET is not set — using an insecure default. Set it in .env before deploying.',
    'Config',
  );
  return DEV_FALLBACK_SECRET;
}
