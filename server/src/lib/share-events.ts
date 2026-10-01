/**
 * Wakes open streams when a share changes.
 *
 * In-process only, which is all this needs: one Node process serves the whole
 * site. If it ever runs behind more than one, this becomes a Redis channel and
 * nothing else changes - clients already fall back to polling, so the worst a
 * missed wake-up costs is a few seconds of staleness.
 */
type Listener = (revision: number) => void;

const globalForEvents = globalThis as unknown as { __selahbeatShareListeners?: Map<string, Set<Listener>> };
const listeners = globalForEvents.__selahbeatShareListeners ?? new Map<string, Set<Listener>>();
globalForEvents.__selahbeatShareListeners = listeners;

export function subscribeToShare(shareId: string, listener: Listener): () => void {
  const set = listeners.get(shareId) ?? new Set<Listener>();
  set.add(listener);
  listeners.set(shareId, set);

  return () => {
    set.delete(listener);
    if (set.size === 0) listeners.delete(shareId);
  };
}

export function bumpShare(shareId: string, revision: number) {
  for (const listener of listeners.get(shareId) ?? []) {
    try {
      listener(revision);
    } catch {
      // A dead stream must not take the writer down with it.
    }
  }
}
