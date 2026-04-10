export type RuntimeDiagnosticEvent = {
  ts: number;
  level: string;
  component: string;
  domain: string;
  event: string;
};

export type RuntimeSnapshotPeer = {
  idx: number;
  pubkey: string;
  incoming_available: number;
  outgoing_available: number;
  outgoing_spent: number;
  can_sign: boolean;
  should_send_nonces: boolean;
};

export type RuntimeSnapshotResult = {
  runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
  status: unknown;
  snapshot: {
    state?: {
      nonce_pool?: {
        peers?: RuntimeSnapshotPeer[];
      };
    };
  } | null;
  snapshotError: string | null;
};

export type RuntimeReadiness = {
  runtime_ready: boolean;
  restore_complete: boolean;
  sign_ready: boolean;
  ecdh_ready: boolean;
  threshold: number;
  signing_peer_count: number;
  ecdh_peer_count: number;
  last_refresh_at: number | null;
  degraded_reasons?: string[];
};

export type RuntimeReadinessResult = {
  runtime: 'cold' | 'restoring' | 'ready' | 'degraded';
  readiness: RuntimeReadiness | null;
};

const RECOVERED_PENDING_OPS_REASON = 'pending_operations_recovered';
const INSUFFICIENT_SIGNING_PEERS_REASON = 'insufficient_signing_peers';
const INSUFFICIENT_ECDH_PEERS_REASON = 'insufficient_ecdh_peers';

function canProceedWhileDegraded(operation: 'sign' | 'ecdh', degradedReasons: string[]) {
  if (degradedReasons.length === 0) {
    return false;
  }

  const allowedReasons =
    operation === 'sign'
      ? new Set([RECOVERED_PENDING_OPS_REASON, INSUFFICIENT_ECDH_PEERS_REASON])
      : new Set([RECOVERED_PENDING_OPS_REASON, INSUFFICIENT_SIGNING_PEERS_REASON]);

  return degradedReasons.every((reason) => allowedReasons.has(reason));
}

export function assertNoncePoolHydrated(
  label: string,
  snapshotResult: RuntimeSnapshotResult,
  expectedPeers: number,
  minSignReadyPeers: number
) {
  if (snapshotResult.runtime !== 'ready' && snapshotResult.runtime !== 'degraded') {
    throw new Error(`${label}: runtime is neither ready nor degraded`);
  }
  if (snapshotResult.snapshotError) {
    throw new Error(`${label}: snapshot error: ${snapshotResult.snapshotError}`);
  }

  const peers = snapshotResult.snapshot?.state?.nonce_pool?.peers ?? [];
  if (peers.length !== expectedPeers) {
    throw new Error(
      `${label}: expected ${expectedPeers} nonce peers, got ${peers.length}\n${JSON.stringify(peers, null, 2)}`
    );
  }

  const signReadyPeers = peers.filter((peer) => peer.can_sign);
  if (signReadyPeers.length < minSignReadyPeers) {
    throw new Error(
      `${label}: expected at least ${minSignReadyPeers} sign-ready peers, got ${signReadyPeers.length}\n${JSON.stringify(
        peers,
        null,
        2
      )}`
    );
  }
}

export function assertRuntimeReadiness(
  label: string,
  readinessResult: RuntimeReadinessResult,
  operation: 'sign' | 'ecdh'
) {
  if (readinessResult.runtime === 'cold') {
    throw new Error(`${label}: runtime is cold`);
  }
  if (!readinessResult.readiness) {
    throw new Error(`${label}: readiness payload is missing`);
  }
  const degradedReasons = readinessResult.readiness.degraded_reasons ?? [];
  if (!readinessResult.readiness.restore_complete && !canProceedWhileDegraded(operation, degradedReasons)) {
    throw new Error(`${label}: runtime restore is not complete`);
  }
  const ready =
    operation === 'sign'
      ? readinessResult.readiness.sign_ready
      : readinessResult.readiness.ecdh_ready;
  if (!ready) {
    throw new Error(
      `${label}: ${operation} is not ready\n${JSON.stringify(readinessResult.readiness, null, 2)}`
    );
  }
}
