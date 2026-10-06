import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { UserRole } from '../../modules/users/user.entity';

export interface JwtPayload {
  sub: string;
  email: string;
  role: UserRole;
}

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): JwtPayload =>
    ctx.switchToHttp().getRequest<{ user: JwtPayload }>().user,
);
