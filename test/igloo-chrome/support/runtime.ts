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
  runtime: 'cold' | 'ready';
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

export function assertNoncePoolHydrated(
  label: string,
  snapshotResult: RuntimeSnapshotResult,
  expectedPeers: number,
  minSignReadyPeers: number
) {
  if (snapshotResult.runtime !== 'ready') {
    throw new Error(`${label}: runtime is not ready`);
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
