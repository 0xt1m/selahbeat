import { redirect } from 'next/navigation';
import { isAuthenticated } from '@/lib/auth';
import { SongForm } from '../SongForm';

export const dynamic = 'force-dynamic';

export default async function NewSongPage() {
  if (!(await isAuthenticated())) redirect('/admin/login');

  return (
    <main className="mx-auto max-w-6xl px-6 py-10">
      <h1 className="mb-2 text-2xl font-bold tracking-tight">New song</h1>
      <p className="mb-8 text-sm text-neutral-500">
        The id is generated from the title and then fixed permanently.
      </p>
      <SongForm
        isNew
        initial={{ title: '', artist: '', bpm: 72, beats: 4, noteValue: 4, key: '', notes: '', verified: false }}
      />
    </main>
  );
}
