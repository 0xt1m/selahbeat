import { db, ensureMigrated } from '@/db';
import { songs, meta, type SongRow } from '@/db/schema';
import { eq, gt, and, sql, like, or, desc } from 'drizzle-orm';

const REVISION_KEY = 'catalog_revision';

export type CatalogSong = {
  id: string;
  title: string;
  artist: string | null;
  bpm: number;
  beats: number;
  noteValue: number;
  key: string | null;
  notes: string | null;
  revision: number;
};

/** Shape the app expects. Internal columns like `verified` stay server-side. */
export function toWire(row: SongRow): CatalogSong {
  return {
    id: row.id,
    title: row.title,
    artist: row.artist,
    bpm: row.bpm,
    beats: row.beats,
    noteValue: row.noteValue,
    key: row.key,
    notes: row.notes,
    revision: row.revision,
  };
}

export function currentRevision(): number {
  ensureMigrated();
  const row = db.select().from(meta).where(eq(meta.key, REVISION_KEY)).get();
  return row ? Number(row.value) : 0;
}

/**
 * Allocates the next global revision. Every write takes one, which is what
 * makes "everything since N" a single indexed range scan.
 */
export function nextRevision(): number {
  ensureMigrated();
  const next = currentRevision() + 1;
  db.insert(meta)
    .values({ key: REVISION_KEY, value: String(next) })
    .onConflictDoUpdate({ target: meta.key, set: { value: String(next) } })
    .run();
  return next;
}

export function getDelta(since: number) {
  ensureMigrated();
  const rev = currentRevision();

  // since <= 0 means a fresh client: send everything live, no tombstones.
  if (since <= 0) {
    const all = db.select().from(songs).where(eq(songs.deleted, false)).all();
    return { revision: rev, full: true, upserts: all.map(toWire), deletes: [] as string[] };
  }

  const changed = db.select().from(songs).where(gt(songs.revision, since)).all();
  return {
    revision: rev,
    full: false,
    upserts: changed.filter((r) => !r.deleted).map(toWire),
    deletes: changed.filter((r) => r.deleted).map((r) => r.id),
  };
}

export function searchSongs(query: string, limit = 25): CatalogSong[] {
  ensureMigrated();
  const q = `%${query.trim().toLowerCase()}%`;
  if (!query.trim()) return [];
  const rows = db
    .select()
    .from(songs)
    .where(
      and(
        eq(songs.deleted, false),
        or(like(sql`lower(${songs.title})`, q), like(sql`lower(${songs.artist})`, q))
      )
    )
    .limit(limit)
    .all();
  return rows.map(toWire);
}

export function listAllSongs(): SongRow[] {
  ensureMigrated();
  return db.select().from(songs).where(eq(songs.deleted, false)).orderBy(songs.title).all();
}

export function getSong(id: string): SongRow | undefined {
  ensureMigrated();
  return db.select().from(songs).where(eq(songs.id, id)).get();
}

export type SongInput = {
  id: string;
  title: string;
  artist?: string | null;
  bpm: number;
  beats: number;
  noteValue: number;
  key?: string | null;
  notes?: string | null;
  verified?: boolean;
};

export function upsertSong(input: SongInput) {
  ensureMigrated();
  const revision = nextRevision();
  const now = new Date().toISOString();

  db.insert(songs)
    .values({
      id: input.id,
      title: input.title,
      artist: input.artist ?? null,
      bpm: input.bpm,
      beats: input.beats,
      noteValue: input.noteValue,
      key: input.key ?? null,
      notes: input.notes ?? null,
      verified: input.verified ?? false,
      revision,
      deleted: false,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: songs.id,
      set: {
        title: input.title,
        artist: input.artist ?? null,
        bpm: input.bpm,
        beats: input.beats,
        noteValue: input.noteValue,
        key: input.key ?? null,
        notes: input.notes ?? null,
        verified: input.verified ?? false,
        revision,
        deleted: false,
        updatedAt: now,
      },
    })
    .run();
}

/**
 * Soft delete. A hard delete would be invisible to clients — they would keep a
 * stale copy forever, because a row that no longer exists can't carry a
 * revision above the one they last saw.
 */
export function softDeleteSong(id: string) {
  ensureMigrated();
  db.update(songs)
    .set({ deleted: true, revision: nextRevision(), updatedAt: new Date().toISOString() })
    .where(eq(songs.id, id))
    .run();
}

export function stats() {
  ensureMigrated();
  const all = db.select().from(songs).where(eq(songs.deleted, false)).all();
  return {
    total: all.length,
    verified: all.filter((s) => s.verified).length,
    unverified: all.filter((s) => !s.verified).length,
    revision: currentRevision(),
  };
}

/** Turns a title into a stable slug. Only ever used when creating a new song. */
export function slugify(title: string): string {
  return title
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}
