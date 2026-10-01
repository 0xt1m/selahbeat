import { createShare, sharesFor } from '@/lib/shares';
import type { SyncDocument } from '@/lib/sync';
import { accountFor, unauthorised, badRequest } from '@/lib/api-auth';

export const dynamic = 'force-dynamic';

/** Every share this account owns or has joined. */
export async function GET(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();
  return Response.json({ shares: sharesFor(account.id) });
}

/**
 * Shares a service, returning the code to hand out.
 *
 * The documents sent here are the service and its items as they stand now:
 * the share starts as a snapshot and diverges from the owner's own copy from
 * that moment on.
 */
export async function POST(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const body = (await request.json().catch(() => null)) as { documents?: SyncDocument[] } | null;
  if (!Array.isArray(body?.documents)) return badRequest('documents must be an array.');

  return Response.json(createShare(account.id, body.documents));
}
