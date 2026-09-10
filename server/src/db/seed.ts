/**
 * Loads catalog/seed-songs.json into the database.
 *
 * Idempotent and non-destructive: a song already present keeps whatever the
 * admin has edited. Re-running only adds songs that are missing, so editing in
 * /admin is never undone by a redeploy.
 */
import fs from 'node:fs';
import path from 'node:path';
import { ensureMigrated } from './index';
import { getSong, upsertSong } from '../lib/catalog';

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

function main() {
  ensureMigrated();

  const seedPath = path.resolve(process.cwd(), 'catalog/seed-songs.json');
  if (!fs.existsSync(seedPath)) {
    console.error(`No seed file at ${seedPath}`);
    process.exit(1);
  }

  const raw = JSON.parse(fs.readFileSync(seedPath, 'utf8')) as { songs: SeedSong[] };
  let added = 0;
  let skipped = 0;

  for (const song of raw.songs) {
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

  console.log(`Seed complete: ${added} added, ${skipped} already present.`);
}

main();
