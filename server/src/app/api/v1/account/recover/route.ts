import { headers } from 'next/headers';
import { redeemRecoveryCode } from '@/lib/accounts';
import { badRequest } from '@/lib/api-auth';
import { checkRateLimit, recordFailure, clearAttempts } from '@/lib/ratelimit';

export const dynamic = 'force-dynamic';

/**
 * Adopts an existing account onto this device.
 *
 * Rate limited hard: a recovery code is the only thing standing between a
 * stranger and somebody's set lists, so guessing must stay expensive.
 */
export async function POST(request: Request) {
  const forwarded = (await headers()).get('x-forwarded-for');
  const key = `recover:${forwarded?.split(',')[0]?.trim() ?? 'unknown'}`;

  const limit = checkRateLimit(key);
  if (!limit.allowed) {
    return Response.json(
      { error: 'Too many attempts. Try again later.' },
      { status: 429, headers: { 'Retry-After': String(limit.retryAfterSeconds) } }
    );
  }

  const body = (await request.json().catch(() => null)) as { code?: string } | null;
  if (!body?.code) return badRequest('A recovery code is required.');

  const result = redeemRecoveryCode(body.code);
  if (!result) {
    recordFailure(key);
    return Response.json({ error: 'That code does not match an account.' }, { status: 404 });
  }

  clearAttempts(key);
  return Response.json({
    accountId: result.accountId,
    deviceId: result.deviceId,
    secret: result.secret,
    token: `${result.deviceId}.${result.secret}`,
  });
}
