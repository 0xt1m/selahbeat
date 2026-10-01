import { pull, push, type SyncDocument } from '@/lib/sync';
import { accountFor, unauthorised, badRequest } from '@/lib/api-auth';

export const dynamic = 'force-dynamic';

/** Everything that changed above `since`, tombstones included. */
export async function GET(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const since = Number(new URL(request.url).searchParams.get('since') ?? 0);
  return Response.json(pull(account.id, Number.isFinite(since) ? since : 0));
}

/** Applies a client's queued changes. Losing an edit is not an error. */
export async function POST(request: Request) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const body = (await request.json().catch(() => null)) as { documents?: SyncDocument[] } | null;
  if (!Array.isArray(body?.documents)) return badRequest('documents must be an array.');

  return Response.json(push(account.id, body.documents));
}
