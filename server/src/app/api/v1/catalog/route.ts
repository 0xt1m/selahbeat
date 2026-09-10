import { NextRequest, NextResponse } from 'next/server';
import { getDelta } from '@/lib/catalog';

export const dynamic = 'force-dynamic';

/**
 * GET /v1/catalog?since=<revision>
 *
 * The app syncs the whole catalog once and then pulls deltas, so tempo lookup
 * keeps working with no connection. A steady-state call returns a few hundred
 * bytes.
 */
export async function GET(request: NextRequest) {
  const sinceRaw = request.nextUrl.searchParams.get('since') ?? '0';
  const since = Number.parseInt(sinceRaw, 10);

  const delta = getDelta(Number.isFinite(since) ? since : 0);

  return NextResponse.json(delta, {
    headers: {
      // Clients poll on launch; a short cache absorbs a congregation's worth of
      // simultaneous Sunday-morning launches without hitting SQLite each time.
      'Cache-Control': 'public, max-age=60',
    },
  });
}
