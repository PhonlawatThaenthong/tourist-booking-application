import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { timingSafeEqual } from 'crypto';

export const INTERNAL_KEY_HEADER = 'x-internal-key';

/**
 * The global per-IP throttler, except that read-only calls carrying the
 * chatbot's shared secret are not counted.
 *
 * Every tool call the chatbot makes back into this API comes from the one IP
 * of its container, and a single question can fan out into several GETs, so
 * a handful of concurrent chat users would otherwise exhaust the 120/min
 * bucket for everyone. The secret is used instead of an IP allow-list because
 * Docker Desktop NATs traffic arriving on the published port to the docker
 * gateway (172.x) — exempting that range would exempt every client.
 *
 * The header only bypasses rate limiting. It grants no access: protected
 * routes still require the customer's own JWT. GET-only, so a leaked key
 * cannot be used to brute-force login or password reset.
 */
@Injectable()
export class InternalAwareThrottlerGuard extends ThrottlerGuard {
  protected async shouldSkip(context: ExecutionContext): Promise<boolean> {
    if (isInternalRead(context.switchToHttp().getRequest())) return true;
    return super.shouldSkip(context);
  }
}

function isInternalRead(req: { method?: string; headers?: Record<string, unknown> }): boolean {
  const secret = process.env.CHATBOT_INTERNAL_KEY;
  if (!secret) return false; // not configured → nobody is exempt
  if (req.method !== 'GET') return false;

  const provided = req.headers?.[INTERNAL_KEY_HEADER];
  if (typeof provided !== 'string') return false;

  const a = Buffer.from(provided);
  const b = Buffer.from(secret);
  // timingSafeEqual throws on length mismatch.
  return a.length === b.length && timingSafeEqual(a, b);
}
