import Link from 'next/link';
import { redirect } from 'next/navigation';
import { isAuthenticated } from '@/lib/auth';
import { listAllSongs, stats } from '@/lib/catalog';
import { deleteSong, logout } from './actions';

export const dynamic = 'force-dynamic';

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; filter?: string }>;
}) {
  if (!(await isAuthenticated())) redirect('/admin/login');

  const { q = '', filter = '' } = await searchParams;
  const summary = stats();
  let songs = listAllSongs();

  if (q) {
    const needle = q.toLowerCase();
    songs = songs.filter(
      (s) => s.title.toLowerCase().includes(needle) || (s.artist ?? '').toLowerCase().includes(needle)
    );
  }
  if (filter === 'unverified') songs = songs.filter((s) => !s.verified);

  return (
    <main className="mx-auto max-w-6xl px-6 py-10">
      <div className="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Song catalog</h1>
          <p className="mt-1 text-sm text-neutral-500">
            {summary.total} songs · {summary.unverified} unverified · revision {summary.revision}
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Link
            href="/admin/song/new"
            className="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-black hover:brightness-110"
          >
            New song
          </Link>
          <form action={logout}>
            <button className="rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-300 hover:border-neutral-500">
              Sign out
            </button>
          </form>
        </div>
      </div>

      <form className="mb-6 flex flex-wrap items-center gap-3" action="/admin">
        <input
          name="q"
          defaultValue={q}
          placeholder="Search title or artist"
          className="flex-1 min-w-[220px] rounded-lg border border-neutral-800 bg-surface px-3 py-2 text-sm outline-none focus:border-accent"
        />
        <select
          name="filter"
          defaultValue={filter}
          className="rounded-lg border border-neutral-800 bg-surface px-3 py-2 text-sm"
        >
          <option value="">All songs</option>
          <option value="unverified">Needs tempo check</option>
        </select>
        <button className="rounded-lg border border-neutral-700 px-4 py-2 text-sm hover:border-neutral-500">
          Filter
        </button>
      </form>

      {summary.unverified > 0 && (
        <p className="mb-6 rounded-lg border border-amber-900/60 bg-amber-950/30 px-4 py-3 text-sm text-amber-200">
          {summary.unverified} songs still have an unverified tempo. These came from the starter
          seed and are estimates — check one against a recording, then tick &ldquo;tempo
          verified&rdquo; so you know it&apos;s trustworthy.
        </p>
      )}

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
              <tr key={song.id} className="border-t border-neutral-900 hover:bg-surface/60">
                <td className="px-4 py-2.5 font-medium">
                  <Link href={`/admin/song/${song.id}`} className="hover:text-accent">
                    {song.title}
                  </Link>
                  <div className="text-xs text-neutral-600">{song.id}</div>
                </td>
                <td className="px-4 py-2.5 text-neutral-400">{song.artist ?? '—'}</td>
                <td className="px-4 py-2.5 text-right tabular-nums">{Math.round(song.bpm)}</td>
                <td className="px-4 py-2.5 text-neutral-400">
                  {song.beats}/{song.noteValue}
                </td>
                <td className="px-4 py-2.5 text-accent">{song.key ?? '—'}</td>
                <td className="px-4 py-2.5">
                  {song.verified ? (
                    <span className="text-good">verified</span>
                  ) : (
                    <span className="text-neutral-600">estimate</span>
                  )}
                </td>
                <td className="px-4 py-2.5 text-right">
                  <form action={deleteSong}>
                    <input type="hidden" name="id" value={song.id} />
                    <button className="text-xs text-neutral-600 hover:text-red-400">Delete</button>
                  </form>
                </td>
              </tr>
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
    </main>
  );
}
