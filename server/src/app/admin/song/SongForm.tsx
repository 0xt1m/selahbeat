'use client';

import { useActionState } from 'react';
import Link from 'next/link';
import { saveSong } from '../actions';

export type SongFormValues = {
  id?: string;
  title: string;
  artist: string;
  bpm: number;
  beats: number;
  noteValue: number;
  key: string;
  notes: string;
  verified: boolean;
};

const KEYS = ['', 'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
  'Am', 'Bm', 'C#m', 'Dm', 'Em', 'F#m', 'Gm'];

export function SongForm({ initial, isNew }: { initial: SongFormValues; isNew: boolean }) {
  const [state, action, pending] = useActionState(saveSong, null as { error?: string } | null);

  return (
    <form action={action} className="max-w-2xl space-y-5">
      {initial.id && <input type="hidden" name="id" value={initial.id} />}

      <Field label="Title">
        <input name="title" defaultValue={initial.title} required className={input} />
      </Field>

      <Field label="Artist">
        <input name="artist" defaultValue={initial.artist} className={input} />
      </Field>

      <div className="grid grid-cols-3 gap-4">
        <Field label="Tempo (BPM)">
          <input name="bpm" type="number" step="0.5" min={20} max={400} defaultValue={initial.bpm} required className={input} />
        </Field>
        <Field label="Beats per bar">
          <input name="beats" type="number" min={1} max={32} defaultValue={initial.beats} required className={input} />
        </Field>
        <Field label="Note value">
          <select name="noteValue" defaultValue={initial.noteValue} className={input}>
            {[2, 4, 8, 16].map((v) => (
              <option key={v} value={v}>{v}</option>
            ))}
          </select>
        </Field>
      </div>

      <Field label="Key">
        <select name="key" defaultValue={initial.key} className={input}>
          {KEYS.map((k) => (
            <option key={k} value={k}>{k || '—'}</option>
          ))}
        </select>
      </Field>

      <Field label="Notes">
        <textarea name="notes" defaultValue={initial.notes} rows={3} className={input} />
      </Field>

      <label className="flex items-center gap-2 text-sm text-neutral-300">
        <input type="checkbox" name="verified" defaultChecked={initial.verified} className="accent-amber-500" />
        Tempo verified against a recording
      </label>

      {state?.error && <p className="text-sm text-red-400">{state.error}</p>}

      {!isNew && (
        <p className="text-xs text-neutral-600">
          The id <code className="text-neutral-400">{initial.id}</code> is permanent. Apps that
          already imported this song key their copy on it.
        </p>
      )}

      <div className="flex items-center gap-3 pt-2">
        <button
          type="submit"
          disabled={pending}
          className="rounded-lg bg-accent px-5 py-2.5 font-semibold text-black hover:brightness-110 disabled:opacity-50"
        >
          {pending ? 'Saving…' : isNew ? 'Create song' : 'Save changes'}
        </button>
        <Link href="/admin" className="text-sm text-neutral-400 hover:text-neutral-200">
          Cancel
        </Link>
      </div>
    </form>
  );
}

const input =
  'w-full rounded-lg border border-neutral-800 bg-surface px-3 py-2 text-sm outline-none focus:border-accent';

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="mb-1.5 block text-sm text-neutral-400">{label}</label>
      {children}
    </div>
  );
}
