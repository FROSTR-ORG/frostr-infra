import type { PwaStoredProfileSeed } from '../../shared/browser-artifacts';

export const PWA_STORAGE_KEY = 'igloo-pwa.state.v1';

export function buildPwaPersistedState(input?: {
  profiles?: PwaStoredProfileSeed[];
  selectedProfileId?: string;
  activeView?: string;
  activeDashboardTab?: 'signer' | 'permissions' | 'settings';
  runtimeSnapshot?: unknown;
}) {
  const profiles = input?.profiles ?? [];
  return {
    profiles,
    peerPermissionStates: [],
    selectedProfileId: input?.selectedProfileId ?? '',
    activeView: input?.activeView ?? 'landing',
    activeDashboardTab: input?.activeDashboardTab ?? 'signer',
    unlockPhrase: '',
    generatedKeyset: null,
    selectedGeneratedShareIdx: null,
    pendingLoadConfirmation: null,
    pendingOnboardConnection: null,
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
        keysetName: '',
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
      recoverProfileForm: {
        shareString: '',
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
    },
  };
}
