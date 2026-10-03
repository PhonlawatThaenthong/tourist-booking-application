import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Restaurant photos move from app-bundled assets to files the backend stores
 * (under UPLOAD_DIR, beside the payment slips), so they can be changed without
 * shipping a new app build.
 *
 * `image_path` is the file's path relative to UPLOAD_DIR, like
 * `payments.slip_path`. `image_url` stays as the fallback for a restaurant with
 * no uploaded photo (an external link, or empty), so it gets an empty default.
 */
export class RestaurantImagePath1758100000000 implements MigrationInterface {
  name = 'RestaurantImagePath1758100000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "restaurants" ADD "image_path" character varying(255)`);
    await q.query(`ALTER TABLE "restaurants" ALTER COLUMN "image_url" SET DEFAULT ''`);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "restaurants" ALTER COLUMN "image_url" DROP DEFAULT`);
    await q.query(`ALTER TABLE "restaurants" DROP COLUMN "image_path"`);
  }
}
