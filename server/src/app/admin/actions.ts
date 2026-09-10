'use server';

import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { checkPassword, createSession, destroySession, isAuthenticated } from '@/lib/auth';
import { upsertSong, softDeleteSong, slugify, getSong } from '@/lib/catalog';

const songSchema = z.object({
  id: z.string().min(1).max(80).optional(),
  title: z.string().min(1, 'Title is required').max(200),
  artist: z.string().max(200).optional(),
  bpm: z.coerce.number().min(20).max(400),
  beats: z.coerce.number().int().min(1).max(32),
  noteValue: z.coerce.number().int().refine((v) => [2, 4, 8, 16].includes(v), 'Bad note value'),
  key: z.string().max(10).optional(),
  notes: z.string().max(1000).optional(),
  verified: z.coerce.boolean().optional(),
});

async function requireAdmin() {
  if (!(await isAuthenticated())) redirect('/admin/login');
}

export async function login(_prev: unknown, formData: FormData) {
  const password = String(formData.get('password') ?? '');
  if (!checkPassword(password)) {
    return { error: 'Incorrect password.' };
  }
  await createSession();
  redirect('/admin');
}

export async function logout() {
  await destroySession();
  redirect('/admin/login');
}

export async function saveSong(_prev: unknown, formData: FormData) {
  await requireAdmin();

  const parsed = songSchema.safeParse({
    id: formData.get('id') || undefined,
    title: formData.get('title'),
    artist: formData.get('artist') || undefined,
    bpm: formData.get('bpm'),
    beats: formData.get('beats'),
    noteValue: formData.get('noteValue'),
    key: formData.get('key') || undefined,
    notes: formData.get('notes') || undefined,
    verified: formData.get('verified') === 'on',
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? 'Invalid input.' };
  }

  const data = parsed.data;
  // An existing id is never regenerated from the title — clients key their
  // imported copies on it, and changing it would orphan every install.
  let id = data.id;
  if (!id) {
    id = slugify(data.title);
    if (!id) return { error: 'Could not derive an id from that title.' };
    if (getSong(id)) return { error: `A song with id "${id}" already exists.` };
  }

  upsertSong({
    id,
    title: data.title,
    artist: data.artist ?? null,
    bpm: data.bpm,
    beats: data.beats,
    noteValue: data.noteValue,
    key: data.key ?? null,
    notes: data.notes ?? null,
    verified: data.verified ?? false,
  });

  revalidatePath('/admin');
  revalidatePath('/');
  redirect('/admin');
}

export async function deleteSong(formData: FormData) {
  await requireAdmin();
  const id = String(formData.get('id') ?? '');
  if (id) {
    softDeleteSong(id);
    revalidatePath('/admin');
  }
}
