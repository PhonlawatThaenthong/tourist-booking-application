import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Adds the front-desk states a stay moves through after payment:
 * approved -> checked_in -> checked_out.
 *
 * Both still count as live for EXC_bookings_no_overlap (its predicate is
 * `status <> 'cancelled'`), so a room stays held while the guest is in it and
 * for the rest of the booked range after they leave.
 */
export class BookingCheckInOut1758000000000 implements MigrationInterface {
  name = 'BookingCheckInOut1758000000000';

  public async up(q: QueryRunner): Promise<void> {
    // Allowed inside a transaction since PG 12, as long as the new values are
    // not used in the same one — they are not.
    await q.query(`ALTER TYPE "bookings_status_enum" ADD VALUE IF NOT EXISTS 'checked_in'`);
    await q.query(`ALTER TYPE "bookings_status_enum" ADD VALUE IF NOT EXISTS 'checked_out'`);
  }

  public async down(q: QueryRunner): Promise<void> {
    // Postgres cannot drop an enum value, so the type is rebuilt. Stays past
    // check-in fold back into 'approved', the state they were in before.
    // The exclusion constraint's predicate depends on the column's type, so it
    // has to come off while the column is retyped.
    await q.query(`ALTER TABLE "bookings" DROP CONSTRAINT "EXC_bookings_no_overlap"`);
    await q.query(`ALTER TABLE "bookings" ALTER COLUMN "status" DROP DEFAULT`);
    await q.query(`ALTER TABLE "bookings" ALTER COLUMN "status" TYPE text USING "status"::text`);
    await q.query(`
      UPDATE "bookings" SET "status" = 'approved'
       WHERE "status" IN ('checked_in', 'checked_out')
    `);
    await q.query(`DROP TYPE "bookings_status_enum"`);
    await q.query(`CREATE TYPE "bookings_status_enum" AS ENUM('pending', 'approved', 'cancelled')`);
    await q.query(`
      ALTER TABLE "bookings" ALTER COLUMN "status" TYPE "bookings_status_enum"
      USING "status"::"bookings_status_enum"
    `);
    await q.query(`ALTER TABLE "bookings" ALTER COLUMN "status" SET DEFAULT 'pending'`);
    await q.query(`
      ALTER TABLE "bookings"
      ADD CONSTRAINT "EXC_bookings_no_overlap"
      EXCLUDE USING gist (
        room_id WITH =,
        daterange(check_in, check_out, '[)') WITH &&
      ) WHERE (status <> 'cancelled')
    `);
  }
}
