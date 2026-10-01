import { membership, pullShare, pushShare, rotateCode, revokeShare, leaveShare } from '@/lib/shares';
import type { SyncDocument } from '@/lib/sync';
import { accountFor, unauthorised, badRequest } from '@/lib/api-auth';
import { bumpShare } from '@/lib/share-events';

export const dynamic = 'force-dynamic';

type Context = { params: Promise<{ id: string }> };

export async function GET(request: Request, { params }: Context) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const { id } = await params;
  const share = membership(id, account.id);
  if (!share) return Response.json({ error: 'Not a member of that service.' }, { status: 404 });

  const since = Number(new URL(request.url).searchParams.get('since') ?? 0);
  return Response.json({ share, ...pullShare(id, Number.isFinite(since) ? since : 0) });
}

export async function POST(request: Request, { params }: Context) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const { id } = await params;
  const share = membership(id, account.id);
  if (!share) return Response.json({ error: 'Not a member of that service.' }, { status: 404 });
  if (share.revoked) return Response.json({ error: 'This share has been turned off.' }, { status: 410 });

  const body = (await request.json().catch(() => null)) as { documents?: SyncDocument[] } | null;
  if (!Array.isArray(body?.documents)) return badRequest('documents must be an array.');

  const result = pushShare(id, account.id, body.documents, { isOwner: share.role === 'owner' });
  // Wakes every open stream on this share so the other phones redraw now
  // rather than on their next poll.
  bumpShare(id, result.revision);
  return Response.json(result);
}

/** Owner-only housekeeping: a new code, or turning the share off. */
export async function PATCH(request: Request, { params }: Context) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const { id } = await params;
  const share = membership(id, account.id);
  if (!share) return Response.json({ error: 'Not a member of that service.' }, { status: 404 });

  const body = (await request.json().catch(() => null)) as { action?: string } | null;
  if (share.role !== 'owner') return Response.json({ error: 'Only the owner can do that.' }, { status: 403 });

  if (body?.action === 'rotate') return Response.json({ code: rotateCode(id) });
  if (body?.action === 'revoke') {
    revokeShare(id);
    return Response.json({ revoked: true });
  }
  return badRequest('Unknown action.');
}

/** Leaving is for members; the owner revokes instead. */
export async function DELETE(request: Request, { params }: Context) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const { id } = await params;
  const share = membership(id, account.id);
  if (!share) return Response.json({ error: 'Not a member of that service.' }, { status: 404 });
  if (share.role === 'owner') return Response.json({ error: 'The owner cannot leave; revoke instead.' }, { status: 400 });

  leaveShare(id, account.id);
  return Response.json({ left: true });
}
