import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';

// igloo-pwa stores the device list in a GLOBAL store shared across tabs and the
// per-tab UI/session state in a partition keyed by an instance id kept in
// sessionStorage. Tests pin a fixed instance id and seed both stores so seeding
// stays deterministic.
export const PWA_GLOBAL_STORE_KEY = 'igloo-pwa.profiles.v1';
export const PWA_SESSION_STORE_KEY = 'igloo-pwa.session.v1';
export const PWA_TEST_INSTANCE_ID = 'e2e';
export const PWA_INSTANCE_ID_KEY = 'igloo-pwa.instanceId';

// Legacy pre-split keys, retained only for specs that still write the old
// partition directly (they migrate into the global store on first boot).
export const PWA_STORAGE_KEY = 'igloo-pwa.state.v2';
export const PWA_INSTANCE_REGISTRY_KEY = 'igloo-pwa.instances.v1';

export function pwaPartitionKey(instanceId: string = PWA_TEST_INSTANCE_ID): string {
  return `${PWA_STORAGE_KEY}::${instanceId}`;
}

export function pwaSessionKey(instanceId: string = PWA_TEST_INSTANCE_ID): string {
  return `${PWA_SESSION_STORE_KEY}::${instanceId}`;
}

export type PwaSeedPayload = {
  instanceIdKey: string;
  instanceId: string;
  globalKey: string;
  sessionKey: string;
  state: unknown;
  // Specs that call page.reload() set this so the seed (an addInitScript that
  // re-runs on every load) only applies once and does not clobber state the app
  // persisted between loads.
  ifAbsent?: boolean;
};

/** Build the browser-context seed payload for {@link applyPwaSeed}. */
export function pwaSeedPayload(
  state: unknown,
  instanceId: string = PWA_TEST_INSTANCE_ID,
): PwaSeedPayload {
  return {
    instanceIdKey: PWA_INSTANCE_ID_KEY,
    instanceId,
    globalKey: PWA_GLOBAL_STORE_KEY,
    sessionKey: pwaSessionKey(instanceId),
    state,
  };
}

/**
 * Runs inside the browser (via page.addInitScript / page.evaluate): pins the
 * instance id and splits the combined seed blob across the app's two stores —
 * profiles + settings into the GLOBAL store, the selection/view/drafts into this
 * tab's SESSION partition.
 */
export function applyPwaSeed(payload: PwaSeedPayload): void {
  if (payload.ifAbsent && window.localStorage.getItem(payload.globalKey)) return;
  window.sessionStorage.setItem(payload.instanceIdKey, payload.instanceId);
  const state = (payload.state ?? {}) as Record<string, unknown>;
  window.localStorage.setItem(
    payload.globalKey,
    JSON.stringify({
      schemaVersion: 1,
      profiles: Array.isArray(state.profiles) ? state.profiles : [],
      settings: state.settings,
    }),
  );
  window.localStorage.setItem(
    payload.sessionKey,
    JSON.stringify({
      schemaVersion: 1,
      selectedProfileId: state.selectedProfileId ?? '',
      activeView: state.activeView ?? 'landing',
      activeDashboardTab: state.activeDashboardTab ?? 'signer',
      drafts: state.drafts ?? {},
    }),
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
