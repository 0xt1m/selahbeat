/**
 * In-memory rate limiting for the admin login.
 *
 * /admin is reachable from the internet and a single password is the only
 * thing in front of the catalog, so unlimited guessing is the obvious attack.
 * A fixed window per client IP makes that impractical without needing Redis.
 *
 * In-memory is sufficient because the app runs as one process; the counters
 * reset on restart, which is acceptable for this threat.
 */
type Entry = { count: number; resetAt: number };

const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 8;

const attempts = new Map<string, Entry>();

/** Stops the map growing without bound from spoofed or rotating addresses. */
function prune(now: number) {
  if (attempts.size < 5000) return;
  for (const [key, entry] of attempts) {
    if (entry.resetAt <= now) attempts.delete(key);
  }
}

export function checkRateLimit(key: string): { allowed: boolean; retryAfterSeconds: number } {
  const now = Date.now();
  const entry = attempts.get(key);

  if (!entry || entry.resetAt <= now) {
    return { allowed: true, retryAfterSeconds: 0 };
  }
  if (entry.count < MAX_ATTEMPTS) {
    return { allowed: true, retryAfterSeconds: 0 };
  }
  return {
    allowed: false,
    retryAfterSeconds: Math.max(1, Math.ceil((entry.resetAt - now) / 1000)),
  };
}

export function recordFailure(key: string) {
  const now = Date.now();
  prune(now);
  const entry = attempts.get(key);

  if (!entry || entry.resetAt <= now) {
    attempts.set(key, { count: 1, resetAt: now + WINDOW_MS });
  } else {
    entry.count += 1;
  }
}

export function clearAttempts(key: string) {
  attempts.delete(key);
}
