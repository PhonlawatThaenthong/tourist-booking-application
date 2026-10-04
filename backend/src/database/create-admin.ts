import 'reflect-metadata';
import * as bcrypt from 'bcrypt';
import dataSourceInstance from '../config/data-source';
import { User, UserRole } from '../modules/users/user.entity';

/**
 * Creates the first admin account. Replaces the old seed-users script, which
 * created three demo accounts with passwords committed to the repo
 * (admin123 etc.) — fine on a laptop, an open door on a public deployment.
 *
 * Credentials come only from the environment; there are no defaults:
 *
 *   SEED_ADMIN_EMAIL     required
 *   SEED_ADMIN_PASSWORD  required, at least 12 characters
 *   SEED_ADMIN_NAME      optional (default "System Admin")
 *
 * Safe to run more than once: an existing account with that email is left
 * untouched (its password is NOT reset).
 *
 * Usage (PowerShell):
 *   $env:SEED_ADMIN_EMAIL="you@example.com"; $env:SEED_ADMIN_PASSWORD="<strong password>"
 *   npm run seed:admin
 */
const BCRYPT_ROUNDS = 12;
const MIN_PASSWORD_LENGTH = 12;

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
}

async function main(): Promise<void> {
  const email = required('SEED_ADMIN_EMAIL').toLowerCase();
  const password = required('SEED_ADMIN_PASSWORD');
  const name = process.env.SEED_ADMIN_NAME?.trim() || 'System Admin';

  if (password.length < MIN_PASSWORD_LENGTH) {
    throw new Error(`SEED_ADMIN_PASSWORD must be at least ${MIN_PASSWORD_LENGTH} characters`);
  }

  const dataSource = await dataSourceInstance.initialize();
  try {
    const repo = dataSource.getRepository(User);
    // Same case-insensitive match as login (unique index is on LOWER(email))
    const exists = await repo
      .createQueryBuilder('u')
      .where('LOWER(u.email) = LOWER(:email)', { email })
      .getOne();
    if (exists) {
      console.log(`Admin not created: ${email} already exists (role: ${exists.role}).`);
      return;
    }
    await repo.save(repo.create({
      name,
      email,
      passwordHash: await bcrypt.hash(password, BCRYPT_ROUNDS),
      role: UserRole.ADMIN,
    }));
    console.log(`Admin created: ${email}`);
  } finally {
    await dataSource.destroy();
  }
}

main().catch((err) => {
  console.error('create-admin failed:', err instanceof Error ? err.message : err);
  process.exit(1);
});
