import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Replaces the standard/deluxe/suite/family room taxonomy with what the rooms
 * actually are: single-bed or twin-bed. The old tiers never corresponded to a
 * real difference between rooms and were about to be indexed into the
 * chatbot's vector store as fact (see docs/chatbot-integration.md).
 *
 * Every room seeded so far satisfies standard/deluxe -> single,
 * suite/family -> twin, so existing rows are remapped rather than dropped.
 */
export class RoomTypeSingleTwin1757900000000 implements MigrationInterface {
  name = 'RoomTypeSingleTwin1757900000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "rooms" ALTER COLUMN "type" TYPE text USING "type"::text`);
    await q.query(`
      UPDATE "rooms" SET "type" = CASE
        WHEN "type" IN ('standard', 'deluxe') THEN 'single'
        ELSE 'twin'
      END
    `);
    await q.query(`DROP TYPE "rooms_type_enum"`);
    await q.query(`CREATE TYPE "rooms_type_enum" AS ENUM('single', 'twin')`);
    await q.query(`
      ALTER TABLE "rooms" ALTER COLUMN "type" TYPE "rooms_type_enum"
      USING "type"::"rooms_type_enum"
    `);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "rooms" ALTER COLUMN "type" TYPE text USING "type"::text`);
    await q.query(`
      UPDATE "rooms" SET "type" = CASE
        WHEN "type" = 'single' THEN 'standard'
        ELSE 'suite'
      END
    `);
    await q.query(`DROP TYPE "rooms_type_enum"`);
    await q.query(`CREATE TYPE "rooms_type_enum" AS ENUM('standard', 'deluxe', 'suite', 'family')`);
    await q.query(`
      ALTER TABLE "rooms" ALTER COLUMN "type" TYPE "rooms_type_enum"
      USING "type"::"rooms_type_enum"
    `);
  }
}
