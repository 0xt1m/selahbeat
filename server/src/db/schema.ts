import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';

/**
 * The shared song catalog.
 *
 * `id` is a stable slug and is the one hard contract with the app: it must
 * never be reused or renumbered, because clients key their imported copies on
 * it. Renaming a song is fine; changing its id orphans every install.
 *
 * `revision` is a global monotonic counter, not a per-row version. Every write
 * stamps the row with the next global value, which makes delta sync a single
 * indexed query: "give me everything above the revision I last saw".
 */
export const songs = sqliteTable('songs', {
  id: text('id').primaryKey(),
  title: text('title').notNull(),
  artist: text('artist'),
  bpm: real('bpm').notNull(),
  beats: integer('beats').notNull().default(4),
  noteValue: integer('note_value').notNull().default(4),
  key: text('key'),
  notes: text('notes'),
  /** False until a human has checked the tempo against a recording. */
  verified: integer('verified', { mode: 'boolean' }).notNull().default(false),
  revision: integer('revision').notNull().default(1),
  /** Soft delete, so clients learn about removals on their next delta. */
  deleted: integer('deleted', { mode: 'boolean' }).notNull().default(false),
  updatedAt: text('updated_at').notNull(),
});

export const meta = sqliteTable('meta', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
});

/**
 * Subscription seams. Unused in v1 — no login wall, the catalog is public —
 * but present so adding billing later is additive rather than a migration of
 * live data.
 */
export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  email: text('email').notNull(),
  createdAt: text('created_at').notNull(),
});

export const subscriptions = sqliteTable('subscriptions', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull(),
  status: text('status').notNull(),
  tier: text('tier').notNull().default('free'),
  currentPeriodEnd: text('current_period_end'),
  updatedAt: text('updated_at').notNull(),
});

export type SongRow = typeof songs.$inferSelect;
export type NewSongRow = typeof songs.$inferInsert;
