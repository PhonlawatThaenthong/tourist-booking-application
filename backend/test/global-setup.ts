import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from '../src/config/data-source';

/**
 * Runs pending migrations ONCE, before Jest starts its workers.
 *
 * Each suite also calls `ds.runMigrations()` in beforeAll, and Jest runs the
 * suites in parallel workers. With a pending migration, every worker saw it as
 * pending and ran it at the same time: one won, the others failed with
 * "column ... already exists". Doing it here first leaves nothing pending, so
 * the per-suite calls become no-ops. (CI is unaffected: it runs
 * `npm run migration:run` before the e2e step.)
 */
export default async function globalSetup(): Promise<void> {
  const ds = new DataSource(buildDataSourceOptions());
  await ds.initialize();
  try {
    await ds.runMigrations();
  } finally {
    await ds.destroy();
  }
}
