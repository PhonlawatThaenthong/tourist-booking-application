import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { JwtStrategy } from '../../modules/auth/strategies/jwt.strategy';
import { UserRole } from '../../modules/users/user.entity';
import { OptionalJwtAuthGuard } from './optional-jwt-auth.guard';

const SECRET = 'optional-jwt-guard-test-secret';

function contextFor(headers: Record<string, string>) {
  const req: Record<string, any> = { headers };
  const ctx = {
    getType: () => 'http',
    switchToHttp: () => ({ getRequest: () => req, getResponse: () => ({}) }),
  } as unknown as ExecutionContext;
  return { ctx, req };
}

describe('OptionalJwtAuthGuard', () => {
  const original = process.env.JWT_ACCESS_SECRET;
  const guard = new OptionalJwtAuthGuard();

  beforeAll(() => {
    process.env.JWT_ACCESS_SECRET = SECRET;
    new JwtStrategy(); // registers the 'jwt' passport strategy
  });

  afterAll(() => {
    if (original === undefined) delete process.env.JWT_ACCESS_SECRET;
    else process.env.JWT_ACCESS_SECRET = original;
  });

  it('lets an anonymous request through with no user', async () => {
    const { ctx, req } = contextFor({});
    await expect(Promise.resolve(guard.canActivate(ctx))).resolves.toBe(true);
    expect(req.user).toBeUndefined();
  });

  it('rejects a malformed token with 401 instead of treating it as anonymous', async () => {
    const { ctx } = contextFor({ authorization: 'Bearer not-a-jwt' });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an expired token with 401', async () => {
    const token = new JwtService({ secret: SECRET }).sign(
      { sub: 'u1', email: 'a@b.c', role: UserRole.CUSTOMER },
      { expiresIn: -10 },
    );
    const { ctx } = contextFor({ authorization: `Bearer ${token}` });
    await expect(guard.canActivate(ctx)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('attaches the payload for a valid token', async () => {
    const token = new JwtService({ secret: SECRET }).sign(
      { sub: 'u1', email: 'a@b.c', role: UserRole.CUSTOMER },
    );
    const { ctx, req } = contextFor({ authorization: `Bearer ${token}` });
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(req.user).toMatchObject({ sub: 'u1', email: 'a@b.c', role: UserRole.CUSTOMER });
  });
});
