import {
  Injectable, BadRequestException, ConflictException, NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { QueryFailedError, Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User, UserRole } from './user.entity';

const BCRYPT_ROUNDS = 12;

/** Postgres foreign_key_violation — the account still owns bookings. */
const PG_FOREIGN_KEY_VIOLATION = '23503';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User) private readonly repo: Repository<User>,
  ) {}

  /** `GET /api/staff/users` — ordered so the back-office list is stable. */
  list(): Promise<User[]> {
    return this.repo.find({ order: { role: 'ASC', name: 'ASC' } });
  }

  findById(id: string): Promise<User | null> {
    return this.repo.findOne({ where: { id } });
  }

  /** Includes passwordHash (which is `select: false` by default) for login. */
  findByEmailWithSecret(email: string): Promise<User | null> {
    return this.repo
      .createQueryBuilder('u')
      .addSelect('u.passwordHash')
      .where('LOWER(u.email) = LOWER(:email)', { email })
      .getOne();
  }

  findByEmail(email: string): Promise<User | null> {
    return this.repo
      .createQueryBuilder('u')
      .where('LOWER(u.email) = LOWER(:email)', { email })
      .getOne();
  }

  async create(input: {
    name: string; email: string; phone?: string; password: string; role?: UserRole;
  }): Promise<User> {
    const exists = await this.repo.findOne({ where: { email: input.email.toLowerCase() } });
    if (exists) throw new ConflictException('อีเมลนี้ถูกใช้งานแล้ว');

    const user = this.repo.create({
      name: input.name,
      email: input.email.toLowerCase(),
      phone: input.phone ?? null,
      passwordHash: await bcrypt.hash(input.password, BCRYPT_ROUNDS),
      role: input.role ?? UserRole.CUSTOMER,
    });
    return this.repo.save(user);
  }

  async getOrFail(id: string): Promise<User> {
    const user = await this.findById(id);
    if (!user) throw new NotFoundException('ไม่พบผู้ใช้');
    return user;
  }

  /**
   * `DELETE /api/staff/users/:id`. An admin deleting their own account would
   * lock the back-office out, and the booking FK is ON DELETE RESTRICT, so a
   * customer with history cannot be erased either.
   */
  async remove(id: string, actorId: string): Promise<void> {
    if (id === actorId) {
      throw new BadRequestException('ลบบัญชีของตัวเองไม่ได้');
    }
    const user = await this.getOrFail(id);
    try {
      await this.repo.remove(user);
    } catch (err) {
      if (err instanceof QueryFailedError
        && (err.driverError as { code?: string }).code === PG_FOREIGN_KEY_VIOLATION) {
        throw new ConflictException('ลบไม่ได้: บัญชีนี้มีประวัติการจองอยู่');
      }
      throw err;
    }
  }

  static verifyPassword(plain: string, hash: string): Promise<boolean> {
    return bcrypt.compare(plain, hash);
  }

  /** Used by `POST /api/auth/reset-password` once the reset code checks out. */
  async updatePassword(userId: string, newPassword: string): Promise<void> {
    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
    await this.repo.update({ id: userId }, { passwordHash });
  }
}
