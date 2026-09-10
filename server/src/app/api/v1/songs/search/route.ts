import { NextRequest, NextResponse } from 'next/server';
import { searchSongs } from '@/lib/catalog';

export const dynamic = 'force-dynamic';

/**
 * GET /v1/songs/search?q=&limit=
 *
 * Fallback path. The app normally searches its local mirror; this exists for
 * when the catalog outgrows the snapshot approach.
 */
export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get('q') ?? '';
  const limitRaw = Number.parseInt(request.nextUrl.searchParams.get('limit') ?? '25', 10);
  const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 100) : 25;

  return NextResponse.json({ songs: searchSongs(q, limit) });
}
