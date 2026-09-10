import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { sql } from 'drizzle-orm';
import * as schema from './schema';
import path from 'node:path';
import fs from 'node:fs';

const DATABASE_PATH = process.env.DATABASE_PATH ?? './data/selahbeat.db';

function createConnection() {
  const dir = path.dirname(DATABASE_PATH);
  fs.mkdirSync(dir, { recursive: true });

  const sqlite = new Database(DATABASE_PATH);
  // WAL lets readers run while a write is in flight — the API stays responsive
  // while the admin saves a song.
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('foreign_keys = ON');
  sqlite.pragma('busy_timeout = 5000');
  return drizzle(sqlite, { schema });
}

// Next dev-mode hot reload would otherwise open a new handle on every edit.
const globalForDb = globalThis as unknown as { __selahbeatDb?: ReturnType<typeof createConnection> };
export const db = globalForDb.__selahbeatDb ?? createConnection();
if (process.env.NODE_ENV !== 'production') globalForDb.__selahbeatDb = db;

/**
 * Schema creation. Deliberately DDL-in-code rather than a migration tool: the
 * schema is small, and one fewer moving part matters more here than migration
 * ceremony. When it stops being true, switch to drizzle-kit.
 */
export function migrate() {
  db.run(sql`
    CREATE TABLE IF NOT EXISTS songs (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      artist TEXT,
      bpm REAL NOT NULL,
      beats INTEGER NOT NULL DEFAULT 4,
      note_value INTEGER NOT NULL DEFAULT 4,
      key TEXT,
      notes TEXT,
      verified INTEGER NOT NULL DEFAULT 0,
      revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
  `);
  // The one query that has to be fast: "everything above revision N".
  db.run(sql`CREATE INDEX IF NOT EXISTS idx_songs_revision ON songs (revision)`);
  db.run(sql`CREATE INDEX IF NOT EXISTS idx_songs_title ON songs (title)`);

  db.run(sql`
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  `);
  db.run(sql`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);
  db.run(sql`
    CREATE TABLE IF NOT EXISTS subscriptions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      status TEXT NOT NULL,
      tier TEXT NOT NULL DEFAULT 'free',
      current_period_end TEXT,
      updated_at TEXT NOT NULL
    )
  `);
}

let migrated = false;
export function ensureMigrated() {
  if (migrated) return;
  migrate();
  migrated = true;
}
