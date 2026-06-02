import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';

export const PWA_STORAGE_KEY = 'igloo-pwa.state.v1';

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
