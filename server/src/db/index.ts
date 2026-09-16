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

/**
 * Loads catalog/seed-songs.json.
 *
 * Runs in-process rather than as a separate `npm run seed` step, because the
 * production image is a Next.js standalone build: it has no tsx, no src/ and no
 * dev dependencies, so the TypeScript seed script cannot run there. Seeding on
 * first use means a fresh deployment comes up populated with no extra command.
 *
 * Only ever adds songs that are missing, so it can never overwrite edits made
 * in /admin, and re-running it is a no-op.
 */
/**
 * Adds catalogue songs the database does not have.
 *
 * Runs on every boot, not only the first, because the catalogue grows after
 * launch: a deploy that ships new songs should bring them with it rather than
 * needing a command run by hand on the server. Existing rows are left exactly
 * as they are - `ON CONFLICT DO NOTHING` - so edits made in /admin survive, and
 * a song deleted there stays deleted, since its row is still present.
 */
function seedMissingSongs() {
  const seedPath = path.resolve(process.cwd(), 'catalog/seed-songs.json');
  if (!fs.existsSync(seedPath)) {
    console.warn(`[selahbeat] no seed catalog at ${seedPath}`);
    return;
  }

  type SeedSong = {
    id: string; title: string; artist: string | null; bpm: number;
    beats: number; noteValue: number; key: string | null;
    notes: string | null; verified?: boolean;
  };

  try {
    const raw = JSON.parse(fs.readFileSync(seedPath, 'utf8')) as { songs: SeedSong[] };
    const now = new Date().toISOString();

    const known = new Set(
      db.all<{ id: string }>(sql`SELECT id FROM songs`).map((row) => row.id)
    );
    const missing = raw.songs.filter((song) => !known.has(song.id));
    if (missing.length === 0) return;

    const startRevision = Number(
      db.get<{ value: string }>(sql`SELECT value FROM meta WHERE key = 'catalog_revision'`)?.value ?? 0
    );
    let revision = startRevision;

    for (const song of missing) {
      revision += 1;
      db.run(sql`
        INSERT INTO songs (id, title, artist, bpm, beats, note_value, key, notes,
                           verified, revision, deleted, updated_at)
        VALUES (${song.id}, ${song.title}, ${song.artist ?? null}, ${song.bpm},
                ${song.beats}, ${song.noteValue}, ${song.key ?? null},
                ${song.notes ?? null}, ${song.verified ? 1 : 0}, ${revision}, 0, ${now})
        ON CONFLICT(id) DO NOTHING
      `);
    }

    // Each added song took a revision, so installed apps pull exactly the new
    // ones on their next sync instead of the whole catalogue again.
    db.run(sql`
      INSERT INTO meta (key, value) VALUES ('catalog_revision', ${String(revision)})
      ON CONFLICT(key) DO UPDATE SET value = ${String(revision)}
    `);

    console.log(`[selahbeat] added ${missing.length} songs from the catalog file`);
  } catch (error) {
    console.error('[selahbeat] seed failed:', error);
  }
}

let migrated = false;
export function ensureMigrated() {
  if (migrated) return;
  migrate();
  seedMissingSongs();
  migrated = true;
}
