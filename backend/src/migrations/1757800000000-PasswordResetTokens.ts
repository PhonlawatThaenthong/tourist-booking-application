import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Forgot/reset password: a one-time 6-digit code, stored only as a sha256
 * hash and scoped to one user, burned after use or too many failed attempts
 * — mirrors the refresh_tokens hash-and-expire pattern from InitAuth.
 */
export class PasswordResetTokens1757800000000 implements MigrationInterface {
  name = 'PasswordResetTokens1757800000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "password_reset_tokens" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "user_id" uuid NOT NULL,
        "code_hash" character varying(64) NOT NULL,
        "expires_at" TIMESTAMP WITH TIME ZONE NOT NULL,
        "used_at" TIMESTAMP WITH TIME ZONE,
        "attempts" smallint NOT NULL DEFAULT 0,
        "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_password_reset_tokens_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_password_reset_tokens_user" FOREIGN KEY ("user_id")
          REFERENCES "users"("id") ON DELETE CASCADE
      )
    `);
    await q.query(`CREATE INDEX "IDX_password_reset_tokens_user" ON "password_reset_tokens" ("user_id")`);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "password_reset_tokens"`);
  }
}
