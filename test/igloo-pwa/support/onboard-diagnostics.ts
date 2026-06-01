import { SimplePool, type Event } from 'nostr-tools';

// Bifrost wraps its protocol messages (onboard request/response, sign, ecdh, ping)
// as ephemeral Nostr events of this kind. Mirrors BIFROST_EVENT_KIND in
// repos/igloo-shared/src/browser-runtime-core.ts (default 20000).
const BIFROST_EVENT_KIND = 20000;

export type RecordedRelayEvent = {
  at_ms: number;
  id: string;
  pubkey: string;
  created_at: number;
  p_tags: string[];
};

export type RelayEventRecorder = {
  events: RecordedRelayEvent[];
  /** First event authored by `pubkey` (e.g. the recipient's onboard request). */
  firstFrom: (pubkey: string) => RecordedRelayEvent | undefined;
  /** First event authored by `pubkey` and #p-targeted at `target`, optionally after `afterMs`. */
  firstFromTo: (pubkey: string, target: string, afterMs?: number) => RecordedRelayEvent | undefined;
  /** Human-readable trace, optionally labelling known pubkeys (e.g. inviter/recipient). */
  format: (labels?: Record<string, string>) => string;
  stop: () => void;
};

/**
 * Passively subscribes to every bifrost (kind 20000) event on a relay and records
 * author + #p targets with arrival timestamps. Because bifrost events are ephemeral
 * (relays neither store nor replay them), this MUST be started before the handshake
 * begins so it observes the live request/response exchange.
 */
export function startRelayEventRecorder(relayUrl: string): RelayEventRecorder {
  const pool = new SimplePool();
  const events: RecordedRelayEvent[] = [];

  const sub = pool.subscribeMany([relayUrl], { kinds: [BIFROST_EVENT_KIND] }, {
    onevent: (event: Event) => {
      events.push({
        at_ms: Date.now(),
        id: event.id,
        pubkey: event.pubkey,
        created_at: event.created_at,
        p_tags: event.tags.filter(([name]) => name === 'p').map(([, value]) => value),
      });
    },
  });

  const label = (labels: Record<string, string> | undefined, pubkey: string) => {
    const key = pubkey?.toLowerCase();
    const match = labels && key ? labels[key] : undefined;
    return match ? `${match} (${pubkey.slice(0, 8)})` : pubkey.slice(0, 12);
  };

  return {
    events,
    firstFrom(pubkey) {
      const key = pubkey.toLowerCase();
      return events.find((event) => event.pubkey.toLowerCase() === key);
    },
    firstFromTo(pubkey, target, afterMs = 0) {
      const from = pubkey.toLowerCase();
      const to = target.toLowerCase();
      return events.find(
        (event) =>
          event.pubkey.toLowerCase() === from &&
          event.at_ms >= afterMs &&
          event.p_tags.some((p) => p.toLowerCase() === to),
      );
    },
    format(labels) {
      const lower = labels
        ? Object.fromEntries(Object.entries(labels).map(([k, v]) => [k.toLowerCase(), v]))
        : undefined;
      if (events.length === 0) return '(no bifrost kind-20000 events observed on relay)';
      const base = events[0].at_ms;
      return events
        .map((event) => {
          const targets = event.p_tags.map((p) => label(lower, p)).join(', ') || '(none)';
          return `  +${String(event.at_ms - base).padStart(5)}ms  from=${label(lower, event.pubkey)}  -> p=[${targets}]  id=${event.id.slice(0, 8)}`;
        })
        .join('\n');
    },
    stop() {
      try {
        sub.close();
      } catch {
        // ignore
      }
      try {
        pool.close([relayUrl]);
      } catch {
        // ignore
      }
    },
  };
}
