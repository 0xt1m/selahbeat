import { headers } from 'next/headers';
import { joinByCode, pullShare } from '@/lib/shares';
import { accountFor, unauthorised, badRequest } from '@/lib/api-auth';
import { checkRateLimit, recordFailure, clearAttempts } from '@/lib/ratelimit';

export const dynamic = 'force-dynamic';

/** Joins a shared service by code, and returns it in full. */
export async function POST(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const forwarded = (await headers()).get('x-forwarded-for');
  const key = `join:${forwarded?.split(',')[0]?.trim() ?? 'unknown'}`;
  const limit = checkRateLimit(key);
  if (!limit.allowed) {
    return Response.json(
      { error: 'Too many attempts. Try again later.' },
      { status: 429, headers: { 'Retry-After': String(limit.retryAfterSeconds) } }
    );
  }

  const body = (await request.json().catch(() => null)) as { code?: string } | null;
  if (!body?.code) return badRequest('A code is required.');

  const share = joinByCode(body.code, account.id);
  if (!share) {
    recordFailure(key);
    return Response.json({ error: 'That code does not match a shared service.' }, { status: 404 });
  }

  clearAttempts(key);
  const contents = pullShare(share.id, 0);
  return Response.json({ share, ...contents });
}
