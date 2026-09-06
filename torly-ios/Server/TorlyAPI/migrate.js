import { readFile } from 'node:fs/promises';
import { createPool, transaction } from './db.js';

export async function migrate(pool) {
  await transaction(pool, async db => {
    await db.query('SELECT pg_advisory_xact_lock(390032)');
    await db.query('CREATE TABLE IF NOT EXISTS migrations (id text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
    for (const id of ['001_initial']) {
      if ((await db.query('SELECT id FROM migrations WHERE id=$1', [id])).rowCount) continue;
      await db.query(await readFile(new URL(`./schema/${id}.sql`, import.meta.url), 'utf8'));
      await db.query('INSERT INTO migrations(id) VALUES($1)', [id]);
    }
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const pool = createPool();
  try { await migrate(pool); console.log('Migrations complete'); }
  finally { await pool.end(); }
}
