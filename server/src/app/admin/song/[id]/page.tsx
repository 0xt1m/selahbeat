import { notFound, redirect } from 'next/navigation';
import { isAuthenticated } from '@/lib/auth';
import { getSong } from '@/lib/catalog';
import { SongForm } from '../SongForm';

export const dynamic = 'force-dynamic';

export default async function EditSongPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthenticated())) redirect('/admin/login');

  const { id } = await params;
  const song = getSong(id);
  if (!song || song.deleted) notFound();

  return (
    <main className="mx-auto max-w-6xl px-6 py-10">
      <h1 className="mb-8 text-2xl font-bold tracking-tight">Edit song</h1>
      <SongForm
        isNew={false}
        initial={{
          id: song.id,
          title: song.title,
          artist: song.artist ?? '',
          bpm: song.bpm,
          beats: song.beats,
          noteValue: song.noteValue,
          key: song.key ?? '',
          notes: song.notes ?? '',
          verified: song.verified,
        }}
      />
    </main>
  );
}
