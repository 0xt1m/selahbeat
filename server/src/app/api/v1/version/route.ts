import { NextResponse } from 'next/server';
import { currentRevision } from '@/lib/catalog';

export const dynamic = 'force-dynamic';

/** Cheap health + catalog-revision probe. */
export async function GET() {
  return NextResponse.json({
    ok: true,
    catalogRevision: currentRevision(),
    serverTime: new Date().toISOString(),
  });
}
