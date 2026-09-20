import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { randomBytes, randomInt, createHash } from 'crypto';
import { UsersService } from '../users/users.service';
import { User } from '../users/user.entity';
import { RefreshToken } from './refresh-token.entity';
import { PasswordResetToken } from './password-reset-token.entity';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { getJwtAccessSecret } from '../../config/jwt.config';
import { MailService } from '../mail/mail.service';

const RESET_CODE_TTL_MINUTES = Number(process.env.RESET_TOKEN_TTL_MINUTES ?? 15);
const MAX_RESET_ATTEMPTS = 5;
// Identical for "no such account", "wrong code" and "expired code" — no
// account enumeration, same principle as login's shared error message.
const GENERIC_RESET_ERROR = 'รหัสยืนยันไม่ถูกต้องหรือหมดอายุ';

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  user: { id: string; name: string; email: string; phone: string | null; role: string };
}

const sha256 = (v: string) => createHash('sha256').update(v).digest('hex');

@Injectable()
export class AuthService {
  constructor(
    private readonly users: UsersService,
    private readonly jwt: JwtService,
    @InjectRepository(RefreshToken)
    private readonly refreshRepo: Repository<RefreshToken>,
    @InjectRepository(PasswordResetToken)
    private readonly resetRepo: Repository<PasswordResetToken>,
    private readonly mail: MailService,
  ) {}

  async register(dto: RegisterDto): Promise<AuthTokens> {
    const user = await this.users.create(dto);
    return this.issueTokens(user);
  }

  async login(dto: LoginDto): Promise<AuthTokens> {
    const user = await this.users.findByEmailWithSecret(dto.email);
    // Same message for unknown email and wrong password (no account enumeration).
    if (!user || !(await UsersService.verifyPassword(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    }
    return this.issueTokens(user);
  }

  async refresh(rawToken: string): Promise<AuthTokens> {
    const record = await this.refreshRepo.findOne({
      where: { tokenHash: sha256(rawToken) },
      relations: { user: true },
    });
    if (!record || record.revokedAt || record.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException('Refresh token ไม่ถูกต้องหรือหมดอายุ');
    }
    // Rotation: the used token is revoked and a fresh pair is issued.
    record.revokedAt = new Date();
    await this.refreshRepo.save(record);
    return this.issueTokens(record.user);
  }

  async logout(rawToken: string): Promise<void> {
    await this.refreshRepo.update(
      { tokenHash: sha256(rawToken), revokedAt: undefined },
      { revokedAt: new Date() },
    );
  }

  /**
   * Always answers the same way regardless of whether `email` has an
   * account, so the response cannot be used to enumerate registered emails.
   */
  async forgotPassword(email: string): Promise<{ message: string }> {
    const user = await this.users.findByEmail(email);
    if (user) {
      // A fresh request supersedes any earlier unused code for this user.
      await this.resetRepo.update({ userId: user.id }, { usedAt: new Date() });

      const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
      await this.resetRepo.save(this.resetRepo.create({
        userId: user.id,
        codeHash: sha256(code),
        expiresAt: new Date(Date.now() + RESET_CODE_TTL_MINUTES * 60 * 1000),
      }));

      try {
        await this.mail.sendPasswordResetCode(user.email, code);
      } catch {
        // Swallowed on purpose: surfacing a send failure only for accounts
        // that exist would itself leak which emails are registered.
      }
    }
    return { message: 'ถ้าอีเมลนี้มีอยู่ในระบบ เราได้ส่งรหัสยืนยันไปให้แล้ว' };
  }

  async resetPassword(dto: ResetPasswordDto): Promise<{ message: string }> {
    const user = await this.users.findByEmail(dto.email);
    const token = user
      ? await this.resetRepo.findOne({
        where: { userId: user.id },
        order: { createdAt: 'DESC' },
      })
      : null;

    if (!user || !token || token.usedAt
      || token.expiresAt.getTime() < Date.now()
      || token.attempts >= MAX_RESET_ATTEMPTS) {
      throw new UnauthorizedException(GENERIC_RESET_ERROR);
    }

    if (token.codeHash !== sha256(dto.code)) {
      token.attempts += 1;
      // Burn it once exhausted so a later request cannot keep guessing.
      if (token.attempts >= MAX_RESET_ATTEMPTS) token.usedAt = new Date();
      await this.resetRepo.save(token);
      throw new UnauthorizedException(GENERIC_RESET_ERROR);
    }

    token.usedAt = new Date();
    await this.resetRepo.save(token);
    await this.users.updatePassword(user.id, dto.newPassword);
    // A password reset ends every session, not just the one making this request.
    await this.refreshRepo.update({ userId: user.id }, { revokedAt: new Date() });

    return { message: 'รีเซ็ตรหัสผ่านสำเร็จ กรุณาเข้าสู่ระบบอีกครั้ง' };
  }

  private async issueTokens(user: User): Promise<AuthTokens> {
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, role: user.role },
      {
        secret: getJwtAccessSecret(),
        expiresIn: process.env.JWT_ACCESS_TTL ?? '15m',
      },
    );

    const refreshToken = randomBytes(48).toString('hex');
    const days = Number(process.env.JWT_REFRESH_TTL_DAYS ?? 30);
    await this.refreshRepo.save(
      this.refreshRepo.create({
        userId: user.id,
        tokenHash: sha256(refreshToken),
        expiresAt: new Date(Date.now() + days * 24 * 60 * 60 * 1000),
      }),
    );

    return {
      accessToken,
      refreshToken,
      user: {
        id: user.id, name: user.name, email: user.email,
        phone: user.phone, role: user.role,
      },
    };
  }
}
