'use client';

import { useState, useTransition } from 'react';
import Link from 'next/link';
import { patchSong, deleteSong } from './actions';

export type AdminSong = {
  id: string;
  title: string;
  artist: string | null;
  bpm: number;
  beats: number;
  noteValue: number;
  key: string | null;
  verified: boolean;
};

const KEYS = ['', 'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
  'Am', 'Bm', 'C#m', 'Dm', 'Em', 'F#m', 'Gm'];

const METERS = ['4/4', '3/4', '2/4', '6/8', '12/8', '5/4', '7/8', '9/8', '1/4'];

/** Looks like text until you click it, so the table still reads as a table. */
const cellInput =
  'w-full rounded border border-transparent bg-transparent px-2 py-1 outline-none ' +
  'hover:border-neutral-800 focus:border-accent focus:bg-black/40';

export function SongTable({ songs }: { songs: AdminSong[] }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-neutral-900">
      <table className="w-full text-left text-sm">
        <thead className="bg-surface text-xs uppercase tracking-wider text-neutral-500">
          <tr>
            <th className="px-4 py-3">Title</th>
            <th className="px-4 py-3">Artist</th>
            <th className="px-4 py-3 text-right">BPM</th>
            <th className="px-4 py-3">Meter</th>
            <th className="px-4 py-3">Key</th>
            <th className="px-4 py-3">Tempo</th>
            <th className="px-4 py-3"></th>
          </tr>
        </thead>
        <tbody>
          {songs.map((song) => (
            <SongRow key={song.id} song={song} />
          ))}
          {songs.length === 0 && (
            <tr>
              <td colSpan={7} className="px-4 py-10 text-center text-neutral-600">
                No songs match.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

function SongRow({ song }: { song: AdminSong }) {
  // Held locally so a slow round trip never makes the cell you are typing in
  // snap back to the server's copy mid-keystroke.
  const [draft, setDraft] = useState(song);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [pending, startTransition] = useTransition();

  function save(patch: Partial<AdminSong>, revert: Partial<AdminSong>) {
    setError(null);
    startTransition(async () => {
      const result = await patchSong(song.id, patch);
      if (result?.error) {
        setError(result.error);
        setDraft((d) => ({ ...d, ...revert }));   // put back what the server still has
        return;
      }
      setSaved(true);
      setTimeout(() => setSaved(false), 1200);
    });
  }

  /** Only writes when the value actually changed, so tabbing through is free. */
  function commitText(field: 'title' | 'artist', value: string) {
    const trimmed = value.trim();
    const current = (song[field] ?? '') as string;
    if (trimmed === current) return;
    if (field === 'title' && !trimmed) {
      setDraft((d) => ({ ...d, title: song.title }));
      setError('Title cannot be empty');
      return;
    }
    save({ [field]: field === 'artist' && !trimmed ? null : trimmed }, { [field]: song[field] });
  }

  function commitBPM(value: string) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed === song.bpm) {
      setDraft((d) => ({ ...d, bpm: song.bpm }));
      return;
    }
    save({ bpm: parsed }, { bpm: song.bpm });
  }

  return (
    <tr className="border-t border-neutral-900 hover:bg-surface/60">
      <td className="px-2 py-1.5 font-medium">
        <input
          value={draft.title}
          onChange={(e) => setDraft({ ...draft, title: e.target.value })}
          onBlur={(e) => commitText('title', e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
          className={cellInput}
        />
        <div className="px-2 text-xs text-neutral-600">
          {song.id}
          {error && <span className="ml-2 text-red-400">{error}</span>}
          {saved && !error && <span className="ml-2 text-good">saved</span>}
          {pending && !saved && <span className="ml-2 text-neutral-500">saving…</span>}
        </div>
      </td>

      <td className="px-2 py-1.5 text-neutral-400">
        <input
          value={draft.artist ?? ''}
          placeholder="—"
          onChange={(e) => setDraft({ ...draft, artist: e.target.value })}
          onBlur={(e) => commitText('artist', e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
          className={cellInput}
        />
      </td>

      <td className="px-2 py-1.5">
        <input
          type="number"
          min={20}
          max={400}
          step={1}
          value={draft.bpm}
          onChange={(e) => setDraft({ ...draft, bpm: Number(e.target.value) })}
          onBlur={(e) => commitBPM(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && e.currentTarget.blur()}
          className={`${cellInput} text-right tabular-nums`}
        />
      </td>

      <td className="px-2 py-1.5 text-neutral-400">
        <select
          value={`${draft.beats}/${draft.noteValue}`}
          onChange={(e) => {
            const [beats, noteValue] = e.target.value.split('/').map(Number);
            setDraft({ ...draft, beats, noteValue });
            save({ beats, noteValue }, { beats: song.beats, noteValue: song.noteValue });
          }}
          className={cellInput}
        >
          {/* A meter already on a song that is not in the list still shows. */}
          {[...new Set([...METERS, `${draft.beats}/${draft.noteValue}`])].map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
        </select>
      </td>

      <td className="px-2 py-1.5 text-accent">
        <select
          value={draft.key ?? ''}
          onChange={(e) => {
            const key = e.target.value || null;
            setDraft({ ...draft, key });
            save({ key }, { key: song.key });
          }}
          className={cellInput}
        >
          {KEYS.map((k) => (
            <option key={k} value={k}>
              {k || '—'}
            </option>
          ))}
        </select>
      </td>

      <td className="px-2 py-1.5">
        <button
          onClick={() => {
            const verified = !draft.verified;
            setDraft({ ...draft, verified });
            save({ verified }, { verified: song.verified });
          }}
          className={
            draft.verified
              ? 'rounded border border-good/40 px-2 py-1 text-xs text-good hover:bg-good/10'
              : 'rounded border border-neutral-800 px-2 py-1 text-xs text-neutral-500 hover:border-neutral-600'
          }
          title="Click to change whether this tempo is trusted"
        >
          {draft.verified ? 'verified' : 'estimate'}
        </button>
      </td>

      <td className="px-4 py-1.5 text-right whitespace-nowrap">
        <Link
          href={`/admin/song/${song.id}`}
          className="text-xs text-neutral-600 hover:text-accent"
          title="Notes and everything else"
        >
          Open
        </Link>
        <form action={deleteSong} className="ml-3 inline">
          <input type="hidden" name="id" value={song.id} />
          <button className="text-xs text-neutral-600 hover:text-red-400">Delete</button>
        </form>
      </td>
    </tr>
  );
}
