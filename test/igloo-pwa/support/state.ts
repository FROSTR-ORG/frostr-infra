import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';

export const PWA_STORAGE_KEY = 'igloo-pwa.state.v2';

// igloo-pwa now partitions persisted state per browser tab by an instance id
// kept in sessionStorage (so tabs are isolated instances). Tests pin a fixed
// instance id and seed the matching partition so seeding stays deterministic.
export const PWA_TEST_INSTANCE_ID = 'e2e';
export const PWA_INSTANCE_ID_KEY = 'igloo-pwa.instanceId';
export const PWA_INSTANCE_REGISTRY_KEY = 'igloo-pwa.instances.v1';

export function pwaPartitionKey(instanceId: string = PWA_TEST_INSTANCE_ID): string {
  return `${PWA_STORAGE_KEY}::${instanceId}`;
}

export type PwaSeedPayload = {
  instanceIdKey: string;
  instanceId: string;
  partitionKey: string;
  registryKey: string;
  state: unknown;
};

/** Build the browser-context seed payload for {@link applyPwaSeed}. */
export function pwaSeedPayload(
  state: unknown,
  instanceId: string = PWA_TEST_INSTANCE_ID,
): PwaSeedPayload {
  return {
    instanceIdKey: PWA_INSTANCE_ID_KEY,
    instanceId,
    partitionKey: pwaPartitionKey(instanceId),
    registryKey: PWA_INSTANCE_REGISTRY_KEY,
    state,
  };
}

/**
 * Runs inside the browser (via page.addInitScript / page.evaluate): pins the
 * instance id and writes the seeded blob to its partition + a registry record,
 * matching the app's per-tab storage layout.
 */
export function applyPwaSeed(payload: PwaSeedPayload): void {
  window.sessionStorage.setItem(payload.instanceIdKey, payload.instanceId);
  window.localStorage.setItem(payload.partitionKey, JSON.stringify(payload.state));
  const profiles = (payload.state as { profiles?: unknown[] } | null)?.profiles;
  const profileCount = Array.isArray(profiles) ? profiles.length : 0;
  const now = Date.now();
  window.localStorage.setItem(
    payload.registryKey,
    JSON.stringify([
      { id: payload.instanceId, label: null, createdAt: now, updatedAt: now, profileCount },
    ]),
  );
}

export function buildPwaPersistedState(input?: {
  profiles?: PwaStoredProfileSeed[];
  selectedProfileId?: string;
  activeView?: string;
  activeDashboardTab?: 'signer' | 'permissions' | 'settings';
  runtimeSnapshot?: unknown;
  peerPermissionStates?: unknown[];
  pendingOnboardConnection?: unknown;
  pendingLoadConfirmation?: unknown;
  drafts?: Record<string, unknown>;
}) {
  const profiles = input?.profiles ?? [];
  return {
    schemaVersion: 2,
    profiles,
    peerPermissionStates: input?.peerPermissionStates ?? [],
    selectedProfileId: input?.selectedProfileId ?? '',
    activeView: input?.activeView ?? 'landing',
    activeDashboardTab: input?.activeDashboardTab ?? 'signer',
    unlockPhrase: '',
    generatedKeyset: null,
    selectedGeneratedShareIdx: null,
    pendingLoadConfirmation: input?.pendingLoadConfirmation ?? null,
    pendingOnboardConnection: input?.pendingOnboardConnection ?? null,
    pendingRotationConnection: null,
    distributionSession: null,
    runtimeSnapshot: input?.runtimeSnapshot ?? null,
    settings: {
      remember_browser_state: true,
      auto_open_signer: true,
      prefer_install_prompt: true,
    },
    drafts: {
      createForm: {
        mode: 'new',
        groupName: '',
        threshold: '2',
        count: '3',
      },
      rotationForm: {
        sourceProfileId: '',
        sources: [{ packageText: '', password: '' }],
      },
      profileForm: {
        label: '',
        password: '',
        confirmPassword: '',
        relayUrls: 'wss://relay.primal.net',
      },
      distributionForms: {},
      importProfileForm: {
        profileString: '',
        password: '',
      },
      onboardConnectForm: {
        packageText: '',
        password: '',
      },
      onboardSaveForm: {
        label: '',
        password: '',
        confirmPassword: '',
      },
      rotateConnectForm: {
        packageText: '',
        password: '',
      },
      ...input?.drafts,
    },
  };
}
