import crypto from 'node:crypto';
import { sql } from 'drizzle-orm';
import { db, ensureMigrated } from '@/db';
import { normaliseCode } from './accounts';
import type { SyncDocument, StoredDocument } from './sync';

/**
 * A service several people edit, reached by a code rather than an invitation.
 *
 * Its documents live here rather than inside any account: joining a share puts
 * nothing in your library, and leaving takes nothing out of anyone else's. The
 * service carries its own copy of each song's tempo, meter, key and mix, so a
 * band mate correcting a tempo here never reaches into your own songs.
 */

const hash = (value: string) => crypto.createHash('sha256').update(value).digest('hex');
const now = () => new Date().toISOString();

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/**
 * 12 characters of Crockford base32 is about 60 bits: unguessable at any rate
 * an attacker could sustain, still short enough to read out to a drummer.
 */
function randomCode(): string {
  const bytes = crypto.randomBytes(12);
  const chars = Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]);
  return [chars.slice(0, 4), chars.slice(4, 8), chars.slice(8, 12)].map((g) => g.join('')).join('-');
}

export type Share = {
  id: string;
  code?: string;
  ownerAccountId: string;
  role: 'owner' | 'member';
  revision: number;
  revoked: boolean;
};

export function createShare(accountId: string, documents: SyncDocument[]): { shareId: string; code: string; revision: number } {
  ensureMigrated();
  const shareId = crypto.randomUUID();
  const code = randomCode();
  const timestamp = now();

  db.run(sql`INSERT INTO shares (id, code_hash, owner_account_id, created_at, revoked, revision)
             VALUES (${shareId}, ${hash(code)}, ${accountId}, ${timestamp}, 0, 0)`);
  db.run(sql`INSERT INTO share_members (share_id, account_id, role, joined_at)
             VALUES (${shareId}, ${accountId}, 'owner', ${timestamp})`);

  const { revision } = pushShare(shareId, accountId, documents, { isOwner: true });
  return { shareId, code, revision };
}

/** A fresh code, cutting off anyone who has the old one but keeping members. */
export function rotateCode(shareId: string): string {
  ensureMigrated();
  const code = randomCode();
  db.run(sql`UPDATE shares SET code_hash = ${hash(code)}, revoked = 0 WHERE id = ${shareId}`);
  return code;
}

export function revokeShare(shareId: string) {
  ensureMigrated();
  db.run(sql`UPDATE shares SET revoked = 1 WHERE id = ${shareId}`);
}

export function membership(shareId: string, accountId: string): Share | null {
  ensureMigrated();
  const row = db.get<{ id: string; owner_account_id: string; revision: number; revoked: number; role: string }>(sql`
    SELECT s.id, s.owner_account_id, s.revision, s.revoked, m.role
    FROM shares s JOIN share_members m ON m.share_id = s.id
    WHERE s.id = ${shareId} AND m.account_id = ${accountId}
  `);
  if (!row) return null;
  return {
    id: row.id,
    ownerAccountId: row.owner_account_id,
    role: row.role === 'owner' ? 'owner' : 'member',
    revision: row.revision,
    revoked: row.revoked === 1,
  };
}

export function joinByCode(code: string, accountId: string): Share | null {
  ensureMigrated();
  const row = db.get<{ id: string; owner_account_id: string; revision: number; revoked: number }>(
    sql`SELECT id, owner_account_id, revision, revoked FROM shares WHERE code_hash = ${hash(normaliseCode(code))}`
  );
  if (!row || row.revoked === 1) return null;

  db.run(sql`INSERT INTO share_members (share_id, account_id, role, joined_at)
             VALUES (${row.id}, ${accountId}, 'member', ${now()})
             ON CONFLICT(share_id, account_id) DO NOTHING`);

  return membership(row.id, accountId);
}

export function leaveShare(shareId: string, accountId: string) {
  ensureMigrated();
  db.run(sql`DELETE FROM share_members WHERE share_id = ${shareId} AND account_id = ${accountId}`);
}

export function sharesFor(accountId: string): Share[] {
  ensureMigrated();
  return db.all<{ id: string; owner_account_id: string; revision: number; revoked: number; role: string }>(sql`
    SELECT s.id, s.owner_account_id, s.revision, s.revoked, m.role
    FROM shares s JOIN share_members m ON m.share_id = s.id
    WHERE m.account_id = ${accountId}
  `).map((row) => ({
    id: row.id,
    ownerAccountId: row.owner_account_id,
    role: row.role === 'owner' ? 'owner' : 'member',
    revision: row.revision,
    revoked: row.revoked === 1,
  }));
}

type ShareDocumentRow = {
  id: string; kind: string; body: string; revision: number;
  deleted: number; client_updated_at: string; updated_by: string | null;
};

export function pullShare(shareId: string, since: number, limit = 1000): {
  revision: number; documents: (StoredDocument & { updatedBy: string | null })[]; more: boolean;
} {
  ensureMigrated();
  const rows = db.all<ShareDocumentRow>(sql`
    SELECT id, kind, body, revision, deleted, client_updated_at, updated_by
    FROM share_documents
    WHERE share_id = ${shareId} AND revision > ${since}
    ORDER BY revision
    LIMIT ${limit + 1}
  `);
  const more = rows.length > limit;
  const page = more ? rows.slice(0, limit) : rows;
  const current = db.get<{ revision: number }>(sql`SELECT revision FROM shares WHERE id = ${shareId}`)?.revision ?? 0;

  return {
    revision: more ? page[page.length - 1].revision : current,
    documents: page.map((row) => ({
      id: row.id,
      kind: row.kind,
      body: JSON.parse(row.body),
      revision: row.revision,
      deleted: row.deleted === 1,
      clientUpdatedAt: row.client_updated_at,
      updatedBy: row.updated_by,
    })),
    more,
  };
}

/**
 * Applies changes from one member.
 *
 * Members may edit the set list - add, remove, reorder, retune. Only the owner
 * may rename or delete the service itself, so one wrong tap on a Sunday
 * morning cannot take the whole thing out from under the band.
 */
export function pushShare(
  shareId: string,
  accountId: string,
  documents: SyncDocument[],
  options: { isOwner: boolean }
): { revision: number; rejected: { id: string; reason: string }[] } {
  ensureMigrated();
  const rejected: { id: string; reason: string }[] = [];

  db.transaction((tx) => {
    for (const document of documents) {
      // The service document carries the name and date; the items carry the
      // set list. Members own the set list, the owner owns the service.
      if (document.kind === 'service' && !options.isOwner) {
        rejected.push({ id: document.id, reason: 'only the owner can rename or delete this service' });
        continue;
      }

      const existing = tx.get<{ client_updated_at: string }>(sql`
        SELECT client_updated_at FROM share_documents WHERE share_id = ${shareId} AND id = ${document.id}
      `);
      if (existing && existing.client_updated_at > document.clientUpdatedAt) {
        rejected.push({ id: document.id, reason: 'older than stored version' });
        continue;
      }

      tx.run(sql`UPDATE shares SET revision = revision + 1 WHERE id = ${shareId}`);
      const revision =
        tx.get<{ revision: number }>(sql`SELECT revision FROM shares WHERE id = ${shareId}`)?.revision ?? 1;
      const timestamp = now();

      tx.run(sql`
        INSERT INTO share_documents (id, share_id, kind, body, revision, deleted,
                                     client_updated_at, updated_at, updated_by)
        VALUES (${document.id}, ${shareId}, ${document.kind}, ${JSON.stringify(document.body ?? null)},
                ${revision}, ${document.deleted ? 1 : 0}, ${document.clientUpdatedAt}, ${timestamp}, ${accountId})
        ON CONFLICT(share_id, id) DO UPDATE SET
          kind = excluded.kind,
          body = excluded.body,
          revision = excluded.revision,
          deleted = excluded.deleted,
          client_updated_at = excluded.client_updated_at,
          updated_at = excluded.updated_at,
          updated_by = excluded.updated_by
      `);
    }
  });

  const revision = db.get<{ revision: number }>(sql`SELECT revision FROM shares WHERE id = ${shareId}`)?.revision ?? 0;
  return { revision, rejected };
}
