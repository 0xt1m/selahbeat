import fs from 'node:fs';
import path from 'node:path';
import { getSong, upsertSong } from './catalog';

type SeedSong = {
  id: string;
  title: string;
  artist: string | null;
  bpm: number;
  beats: number;
  noteValue: number;
  key: string | null;
  notes: string | null;
  verified?: boolean;
};

function seedPath(): string {
  return path.resolve(process.cwd(), 'catalog/seed-songs.json');
}

function readSeed(): SeedSong[] {
  const file = seedPath();
  if (!fs.existsSync(file)) return [];
  const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as { songs?: SeedSong[] };
  return raw.songs ?? [];
}

/** How many songs in the shipped seed file are not in the database yet. */
export function pendingSeedCount(): number {
  return readSeed().filter((song) => !getSong(song.id)).length;
}

/**
 * Adds seed songs the database does not have.
 *
 * The same rule as first-boot seeding: a song already present is left exactly
 * as it is, so a tempo corrected in the admin table is never overwritten by a
 * later import. Only the missing ones are written, each taking one revision so
 * installed apps pick them up on their next sync.
 */
export function importMissingSeedSongs(): { added: number; skipped: number } {
  let added = 0;
  let skipped = 0;

  for (const song of readSeed()) {
    if (getSong(song.id)) {
      skipped += 1;
      continue;
    }
    upsertSong({
      id: song.id,
      title: song.title,
      artist: song.artist,
      bpm: song.bpm,
      beats: song.beats,
      noteValue: song.noteValue,
      key: song.key,
      notes: song.notes,
      verified: song.verified ?? false,
    });
    added += 1;
  }

  return { added, skipped };
}
