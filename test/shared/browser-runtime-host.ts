import {
  connectSignerNode,
  createBrowserRuntimeNodeInit,
  createSignerNode,
  getRuntimeConfigFromNode,
  getRuntimeMetadata,
  getRuntimePeerPermissionStatesFromNode,
  getRuntimeReadiness,
  getRuntimeSnapshot,
  getRuntimeStatus,
  refreshAllPeersOnNode,
  stopSignerNode,
  type NodeWithEvents,
  type RuntimeMetadata,
  type RuntimePeerPermissionState,
  type RuntimeReadiness,
  type RuntimeStatusSummary,
  type SignerSettings,
  normalizeSignerSettings,
} from 'igloo-shared';

export type BrowserStoredProfile = {
  groupName?: string;
  relays: string[];
  groupPublicKey?: string;
  sharePublicKey?: string;
  peerPubkey?: string;
  signerSettings?: Partial<SignerSettings>;
  runtimeSnapshotJson?: string | null;
};

export type BrowserBootstrapProfile = BrowserStoredProfile & {
  groupPackageJson: string;
  sharePackageJson: string;
};

export type BrowserRuntimeSessionSnapshot = {
  runtimeStatus: RuntimeStatusSummary;
  metadata: RuntimeMetadata;
  readiness: RuntimeReadiness;
  peerPermissionStates: RuntimePeerPermissionState[];
  signerSettings: SignerSettings;
  runtimeSnapshotJson: string;
};

export type BrowserRuntimeSession = {
  collectLogs: () => string[];
  read: () => BrowserRuntimeSessionSnapshot;
  refreshPeers: () => Promise<BrowserRuntimeSessionSnapshot>;
  stop: () => BrowserRuntimeSessionSnapshot;
};

function formatLogLine(level: 'info' | 'error', payload: unknown) {
  if (payload && typeof payload === 'object') {
    const record = payload as Record<string, unknown>;
    const domain = typeof record.domain === 'string' ? record.domain : 'runtime';
    const event = typeof record.event === 'string' ? record.event : 'message';
    const detailParts: string[] = [];
    if (typeof record.request_id === 'string') detailParts.push(`request_id=${record.request_id}`);
    if (Array.isArray(record.reasons) && record.reasons.length > 0) {
      detailParts.push(`reasons=${JSON.stringify(record.reasons)}`);
    }
    if (Array.isArray(record.close_reasons) && record.close_reasons.length > 0) {
      detailParts.push(`close_reasons=${JSON.stringify(record.close_reasons)}`);
    }
    if (typeof record.relays_ok === 'number' && typeof record.relays_total === 'number') {
      detailParts.push(`publish=${record.relays_ok}/${record.relays_total}`);
    }
    if (typeof record.event_id === 'string') detailParts.push(`event_id=${record.event_id}`);
    if (typeof record.error_message === 'string') {
      detailParts.push(`error=${record.error_message}`);
    }
    return detailParts.length > 0
      ? `[${level}] ${domain}.${event} ${detailParts.join(' ')}`
      : `[${level}] ${domain}.${event}`;
  }
  const text = payload instanceof Error ? payload.message : String(payload);
  return `[${level}] ${text}`;
}

function attachLogBuffer(node: NodeWithEvents) {
  const lines: string[] = [];

  const onMessage = (payload: unknown) => {
    lines.push(formatLogLine('info', payload));
  };
  const onError = (payload: unknown) => {
    lines.push(formatLogLine('error', payload));
  };

  node.on('message', onMessage);
  node.on('error', onError);

  return {
    collect: () => [...lines],
    detach: () => {
      if (typeof node.off === 'function') {
        node.off('message', onMessage);
        node.off('error', onError);
      } else if (typeof node.removeListener === 'function') {
        node.removeListener('message', onMessage);
        node.removeListener('error', onError);
      }
    },
  };
}

function buildSessionSnapshot(node: NodeWithEvents): BrowserRuntimeSessionSnapshot {
  return {
    runtimeStatus: getRuntimeStatus(node),
    metadata: getRuntimeMetadata(node),
    readiness: getRuntimeReadiness(node),
    peerPermissionStates: getRuntimePeerPermissionStatesFromNode(node),
    signerSettings: normalizeSignerSettings(getRuntimeConfigFromNode(node)),
    runtimeSnapshotJson: JSON.stringify(getRuntimeSnapshot(node)),
  };
}

function createSession(node: NodeWithEvents, logs: ReturnType<typeof attachLogBuffer>): BrowserRuntimeSession {
  let stopped = false;

  return {
    collectLogs() {
      return logs.collect();
    },
    read() {
      return buildSessionSnapshot(node);
    },
    async refreshPeers() {
      refreshAllPeersOnNode(node);
      await new Promise((resolve) => setTimeout(resolve, 250));
      return buildSessionSnapshot(node);
    },
    stop() {
      if (!stopped) {
        stopped = true;
        logs.detach();
        stopSignerNode(node);
      }
      return buildSessionSnapshot(node);
    },
  };
}

export async function startBrowserRuntimeSession(
  profile: BrowserBootstrapProfile
): Promise<BrowserRuntimeSession> {
  const init = createBrowserRuntimeNodeInit(profile);
  const node = createSignerNode(init.config, init.restoreOptions);
  const logs = attachLogBuffer(node);
  await connectSignerNode(node);
  refreshAllPeersOnNode(node);
  return createSession(node, logs);
}
