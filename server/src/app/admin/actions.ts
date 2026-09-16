'use server';

import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { headers } from 'next/headers';
import { checkPassword, createSession, destroySession, isAuthenticated } from '@/lib/auth';
import { checkRateLimit, recordFailure, clearAttempts } from '@/lib/ratelimit';
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

/** Client IP as seen through the reverse proxy, which sets X-Forwarded-For. */
async function clientKey(): Promise<string> {
  const h = await headers();
  const forwarded = h.get('x-forwarded-for');
  return forwarded?.split(',')[0]?.trim() || h.get('x-real-ip') || 'unknown';
}

export async function login(_prev: unknown, formData: FormData) {
  const key = await clientKey();

  const limit = checkRateLimit(key);
  if (!limit.allowed) {
    const minutes = Math.ceil(limit.retryAfterSeconds / 60);
    return { error: `Too many attempts. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.` };
  }

  const password = String(formData.get('password') ?? '');
  if (!checkPassword(password)) {
    recordFailure(key);
    // Deliberately does not say whether a password is even configured.
    return { error: 'Incorrect password.' };
  }

  clearAttempts(key);
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

/**
 * Edits one or more fields of a song from the catalog table.
 *
 * Kept separate from `saveSong`, which is form-shaped and redirects: this is
 * called as you tab out of a cell, so it patches only what changed, leaves
 * every other column alone, and returns instead of navigating.
 */
const patchSchema = z.object({
  title: z.string().min(1, 'Title cannot be empty').max(200).optional(),
  artist: z.string().max(200).nullable().optional(),
  bpm: z.coerce.number().min(20, 'Tempo must be 20-400').max(400, 'Tempo must be 20-400').optional(),
  beats: z.coerce.number().int().min(1).max(32).optional(),
  noteValue: z.coerce
    .number()
    .int()
    .refine((v) => [2, 4, 8, 16].includes(v), 'Bad note value')
    .optional(),
  key: z.string().max(10).nullable().optional(),
  verified: z.boolean().optional(),
});

export async function patchSong(id: string, patch: unknown) {
  await requireAdmin();

  const existing = getSong(id);
  if (!existing) return { error: 'That song no longer exists.' };

  const parsed = patchSchema.safeParse(patch);
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'Invalid input.' };
  const data = parsed.data;

  // Every field is read from the row first, so patching the tempo can never
  // blank the notes or flip the verified flag as a side effect.
  upsertSong({
    id: existing.id,
    title: data.title ?? existing.title,
    artist: data.artist !== undefined ? data.artist : existing.artist,
    bpm: data.bpm ?? existing.bpm,
    beats: data.beats ?? existing.beats,
    noteValue: data.noteValue ?? existing.noteValue,
    key: data.key !== undefined ? data.key : existing.key,
    notes: existing.notes,
    verified: data.verified ?? existing.verified,
  });

  revalidatePath('/admin');
  revalidatePath('/');
  return { ok: true };
}
