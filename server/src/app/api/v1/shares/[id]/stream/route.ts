import { membership } from '@/lib/shares';
import { subscribeToShare } from '@/lib/share-events';
import { accountFor, unauthorised } from '@/lib/api-auth';

export const dynamic = 'force-dynamic';

/**
 * Live updates for one shared service, as Server-Sent Events.
 *
 * The stream carries only a revision number, never the change itself: the
 * client already knows how to pull "everything above N", and a client that
 * missed a message or was asleep converges on the next pull either way.
 *
 * SSE rather than a WebSocket because this is one-way, survives a proxy that
 * knows nothing about it, and reconnects on its own.
 */
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const account = accountFor(request);
  if (!account) return unauthorised();

  const { id } = await params;
  const share = membership(id, account.id);
  if (!share) return Response.json({ error: 'Not a member of that service.' }, { status: 404 });

  const encoder = new TextEncoder();
  let unsubscribe = () => {};
  let heartbeat: ReturnType<typeof setInterval> | undefined;

  const stream = new ReadableStream({
    start(controller) {
      const send = (event: string, data: unknown) => {
        try {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
        } catch {
          // Client vanished mid-write; the abort handler cleans up.
        }
      };

      send('hello', { shareId: id, revision: share.revision });
      unsubscribe = subscribeToShare(id, (revision) => send('changed', { shareId: id, revision }));

      // Proxies drop a silent connection, and a phone on mobile data drops it
      // sooner. A comment every 20 seconds keeps it alive and costs nothing.
      heartbeat = setInterval(() => {
        try {
          controller.enqueue(encoder.encode(': keep-alive\n\n'));
        } catch {
          /* closing */
        }
      }, 20_000);

      request.signal.addEventListener('abort', () => {
        unsubscribe();
        if (heartbeat) clearInterval(heartbeat);
        try {
          controller.close();
        } catch {
          /* already closed */
        }
      });
    },
    cancel() {
      unsubscribe();
      if (heartbeat) clearInterval(heartbeat);
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      // Tells nginx not to buffer; Caddy already does not.
      'X-Accel-Buffering': 'no',
    },
  });
}
