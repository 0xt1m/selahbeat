import crypto from 'node:crypto';
import { sql } from 'drizzle-orm';
import { db, ensureMigrated } from '@/db';

/**
 * Accounts with no login.
 *
 * An account is an id and nothing else - no email, no password, nothing that
 * identifies a person. A device proves ownership with a secret it generated
 * itself and sends as `Bearer <deviceId>.<secret>`; only the hash is stored, so
 * the database cannot be read to impersonate anyone.
 *
 * A recovery code is the second way back to the same account, for a phone that
 * has been wiped, lost or replaced.
 */

export type Account = { id: string; revision: number };

const now = () => new Date().toISOString();
const hash = (value: string) => crypto.createHash('sha256').update(value).digest('hex');

/**
 * Crockford base32: no I, L, O or U, so a code read aloud over a noisy stage
 * cannot be written down wrong, and nothing in it spells a word by accident.
 */
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

function randomCode(groups = 3, groupSize = 4): string {
  const bytes = crypto.randomBytes(groups * groupSize);
  const chars = Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]);
  const out: string[] = [];
  for (let i = 0; i < groups; i += 1) {
    out.push(chars.slice(i * groupSize, (i + 1) * groupSize).join(''));
  }
  return out.join('-');
}

/** Accepts what a person actually types: spaces, lower case, missing dashes. */
export function normaliseCode(input: string): string {
  const cleaned = input.toUpperCase().replace(/[^0-9A-Z]/g, '')
    // The characters Crockford drops are exactly the ones people substitute.
    .replace(/O/g, '0').replace(/[IL]/g, '1').replace(/U/g, 'V');
  return cleaned.match(/.{1,4}/g)?.join('-') ?? cleaned;
}

export function createAccount(): { account: Account; deviceId: string; secret: string; recoveryCode: string } {
  ensureMigrated();
  const id = crypto.randomUUID();
  const timestamp = now();

  db.run(sql`INSERT INTO accounts (id, created_at, last_seen_at, revision)
             VALUES (${id}, ${timestamp}, ${timestamp}, 0)`);

  const { deviceId, secret } = addDevice(id);
  const recoveryCode = resetRecoveryCode(id);
  return { account: { id, revision: 0 }, deviceId, secret, recoveryCode };
}

export function addDevice(accountId: string, label?: string): { deviceId: string; secret: string } {
  ensureMigrated();
  const deviceId = crypto.randomUUID();
  const secret = crypto.randomBytes(32).toString('base64url');
  const timestamp = now();

  db.run(sql`INSERT INTO devices (id, account_id, secret_hash, label, created_at, last_seen_at)
             VALUES (${deviceId}, ${accountId}, ${hash(secret)}, ${label ?? null}, ${timestamp}, ${timestamp})`);
  return { deviceId, secret };
}

/** Issues a fresh code and retires the old one, so a leaked code can be cut off. */
export function resetRecoveryCode(accountId: string): string {
  ensureMigrated();
  const code = randomCode();
  db.run(sql`DELETE FROM recovery_codes WHERE account_id = ${accountId}`);
  db.run(sql`INSERT INTO recovery_codes (code_hash, account_id, created_at)
             VALUES (${hash(code)}, ${accountId}, ${now()})`);
  return code;
}

/** Adopts an existing account onto a new device. Returns null if no such code. */
export function redeemRecoveryCode(input: string): { accountId: string; deviceId: string; secret: string } | null {
  ensureMigrated();
  const row = db.get<{ account_id: string }>(
    sql`SELECT account_id FROM recovery_codes WHERE code_hash = ${hash(normaliseCode(input))}`
  );
  if (!row) return null;
  // The code keeps working: losing a second phone is not a different problem
  // from losing the first, and a one-shot code would strand people.
  return { accountId: row.account_id, ...addDevice(row.account_id) };
}

/**
 * Resolves `Authorization: Bearer <deviceId>.<secret>` to an account.
 *
 * Deliberately quiet about why it failed - a caller learns only that it did.
 */
export function authenticate(header: string | null): Account | null {
  ensureMigrated();
  const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return null;

  const separator = token.indexOf('.');
  if (separator < 0) return null;
  const deviceId = token.slice(0, separator);
  const secret = token.slice(separator + 1);

  const device = db.get<{ account_id: string; secret_hash: string }>(
    sql`SELECT account_id, secret_hash FROM devices WHERE id = ${deviceId}`
  );
  if (!device) return null;

  const expected = Buffer.from(device.secret_hash);
  const actual = Buffer.from(hash(secret));
  if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) return null;

  const account = db.get<{ id: string; revision: number }>(
    sql`SELECT id, revision FROM accounts WHERE id = ${device.account_id}`
  );
  if (!account) return null;

  const timestamp = now();
  db.run(sql`UPDATE devices SET last_seen_at = ${timestamp} WHERE id = ${deviceId}`);
  db.run(sql`UPDATE accounts SET last_seen_at = ${timestamp} WHERE id = ${account.id}`);
  return account;
}

/** Everything of theirs, gone. Shares they own go with it; ones they joined do not. */
export function deleteAccount(accountId: string) {
  ensureMigrated();
  db.run(sql`DELETE FROM accounts WHERE id = ${accountId}`);
}
