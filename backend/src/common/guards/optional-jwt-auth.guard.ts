import { ExecutionContext, Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * Lets anonymous requests through with `request.user` undefined, but still
 * validates a token when one is sent.
 *
 * A present-but-invalid token is a 401, never a silent fallback to anonymous:
 * the app refreshes its access token on 401 and retries, so swallowing an
 * expired token would leave a logged-in customer quietly unable to ask about
 * their own bookings.
 */
@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
  canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest();
    if (!req.headers?.authorization) return true;
    return super.canActivate(context);
  }
}
