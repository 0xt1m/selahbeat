import { sql } from 'drizzle-orm';
import { db, ensureMigrated } from '@/db';

/**
 * Document sync for one account.
 *
 * The client is the source of truth for what a song or service *is*: `body` is
 * opaque JSON the server never parses, so a phone running an older build can
 * never have its documents rewritten into a shape it cannot read.
 *
 * Ordering uses the same per-account monotonic revision the catalog uses, so a
 * pull is one indexed range scan and an offline week is just a bigger range.
 */

export type SyncDocument = {
  id: string;
  kind: string;
  body: unknown;
  deleted?: boolean;
  /** The client's own clock. Only ever used to settle which of two edits wins. */
  clientUpdatedAt: string;
};

export type StoredDocument = SyncDocument & { revision: number; deleted: boolean };

type DocumentRow = {
  id: string;
  kind: string;
  body: string;
  revision: number;
  deleted: number;
  client_updated_at: string;
};

const MAX_BODY_BYTES = 256 * 1024;
const MAX_DOCUMENTS_PER_PUSH = 500;

function toDocument(row: DocumentRow): StoredDocument {
  return {
    id: row.id,
    kind: row.kind,
    body: JSON.parse(row.body),
    revision: row.revision,
    deleted: row.deleted === 1,
    clientUpdatedAt: row.client_updated_at,
  };
}

export function currentRevision(accountId: string): number {
  ensureMigrated();
  return db.get<{ revision: number }>(sql`SELECT revision FROM accounts WHERE id = ${accountId}`)?.revision ?? 0;
}

/** Everything that changed above `since`, tombstones included. */
export function pull(accountId: string, since: number, limit = 1000): {
  revision: number;
  documents: StoredDocument[];
  more: boolean;
} {
  ensureMigrated();
  const rows = db.all<DocumentRow>(sql`
    SELECT id, kind, body, revision, deleted, client_updated_at
    FROM documents
    WHERE account_id = ${accountId} AND revision > ${since}
    ORDER BY revision
    LIMIT ${limit + 1}
  `);

  const more = rows.length > limit;
  const page = more ? rows.slice(0, limit) : rows;
  return {
    // With more to come, report the last revision actually sent: a client that
    // stops early and resumes later must not skip the remainder.
    revision: more ? page[page.length - 1].revision : currentRevision(accountId),
    documents: page.map(toDocument),
    more,
  };
}

/**
 * Applies a client's changes.
 *
 * Last write wins, settled by the client's own timestamp rather than arrival
 * order: a phone that was offline all week and syncs on Sunday must not
 * overwrite Saturday's edit made on the Mac. An edit that loses is not an
 * error - the client gets the winning version back in its next pull.
 */
export function push(accountId: string, documents: SyncDocument[]): {
  revision: number;
  rejected: { id: string; reason: string }[];
} {
  ensureMigrated();
  const rejected: { id: string; reason: string }[] = [];

  if (documents.length > MAX_DOCUMENTS_PER_PUSH) {
    return { revision: currentRevision(accountId), rejected: [{ id: '*', reason: 'too many documents' }] };
  }

  // One transaction for the whole push: a client that loses its connection
  // halfway through must not leave half a set list behind.
  db.transaction((tx) => {
    for (const document of documents) {
      const body = JSON.stringify(document.body ?? null);
      if (body.length > MAX_BODY_BYTES) {
        rejected.push({ id: document.id, reason: 'too large' });
        continue;
      }

      const existing = tx.get<{ client_updated_at: string }>(sql`
        SELECT client_updated_at FROM documents
        WHERE account_id = ${accountId} AND id = ${document.id}
      `);
      if (existing && existing.client_updated_at > document.clientUpdatedAt) {
        rejected.push({ id: document.id, reason: 'older than stored version' });
        continue;
      }

      tx.run(sql`UPDATE accounts SET revision = revision + 1 WHERE id = ${accountId}`);
      const revision =
        tx.get<{ revision: number }>(sql`SELECT revision FROM accounts WHERE id = ${accountId}`)?.revision ?? 1;
      const timestamp = new Date().toISOString();

      tx.run(sql`
        INSERT INTO documents (id, account_id, kind, body, revision, deleted, client_updated_at, updated_at)
        VALUES (${document.id}, ${accountId}, ${document.kind}, ${body}, ${revision},
                ${document.deleted ? 1 : 0}, ${document.clientUpdatedAt}, ${timestamp})
        ON CONFLICT(account_id, id) DO UPDATE SET
          kind = excluded.kind,
          body = excluded.body,
          revision = excluded.revision,
          deleted = excluded.deleted,
          client_updated_at = excluded.client_updated_at,
          updated_at = excluded.updated_at
      `);
    }
  });

  return { revision: currentRevision(accountId), rejected };
}

export const limits = { MAX_BODY_BYTES, MAX_DOCUMENTS_PER_PUSH };
