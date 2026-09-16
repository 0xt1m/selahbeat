'use client';

import { useState, useTransition } from 'react';
import { importSeedSongs } from './actions';

/** Offers the songs that shipped with this build but are not in the database. */
export function ImportSeedButton({ count }: { count: number }) {
  const [pending, startTransition] = useTransition();
  const [added, setAdded] = useState<number | null>(null);

  if (added !== null) {
    return (
      <p className="mb-6 rounded-lg border border-emerald-900/60 bg-emerald-950/30 px-4 py-3 text-sm text-emerald-200">
        Added {added} song{added === 1 ? '' : 's'} to the catalog.
      </p>
    );
  }

  return (
    <div className="mb-6 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-sky-900/60 bg-sky-950/30 px-4 py-3 text-sm text-sky-200">
      <span>
        {count} song{count === 1 ? '' : 's'} in this build&rsquo;s catalog file are not in the
        database yet. Songs already here keep their edits.
      </span>
      <button
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            const result = await importSeedSongs();
            setAdded(result.added);
          })
        }
        className="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-black hover:brightness-110 disabled:opacity-50"
      >
        {pending ? 'Importing…' : `Import ${count}`}
      </button>
    </div>
  );
}
