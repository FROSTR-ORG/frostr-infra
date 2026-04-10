import type { BrowserContext, Page, Worker } from '@playwright/test';
import type { StoredProfile as OnboardedStoredProfile } from '../support/onboarding';
import type { LiveSignerController, LiveSignerFixture } from './live-signer';
import type { TestServer } from './server';
import type { TEST_PROFILE } from './constants';

export type SeedPermissionPolicy = {
  host: string;
  type: string;
  allow: boolean;
  createdAt?: number;
  kind?: number;
};

export type DemoHarnessFixture = {
  relayUrl: string;
  recipient: string;
  onboardPackage: string;
  onboardPassword: string;
  cleanup: () => Promise<void>;
};

export type SeedProfileOverrides = Partial<typeof TEST_PROFILE> & OnboardedStoredProfile;

export type ExtensionFixtures = {
  context: BrowserContext;
  extensionId: string;
  serviceWorker: Worker;
  server: TestServer;
  liveSigner: LiveSignerFixture;
  stableLiveSigner: LiveSignerFixture;
  demoHarness: DemoHarnessFixture;
  openExtensionPage: (path: string) => Promise<Page>;
  activateProfile: (profileId: string) => Promise<void>;
  fetchRuntimeSnapshot: <T>() => Promise<T>;
  fetchRuntimeStatus: <T>() => Promise<T>;
  fetchRuntimeDiagnostics: <T>() => Promise<T>;
  prepareRuntimeReadiness: <T>(operation: 'sign' | 'ecdh') => Promise<T>;
  runRuntimeControl: (action: 'stopRuntime' | 'reloadExtension') => Promise<void>;
  reloadExtension: () => Promise<void>;
  seedProfile: (overrides?: SeedProfileOverrides) => Promise<void>;
  seedPermissionPolicies: (policies: SeedPermissionPolicy[]) => Promise<void>;
  clearSessionUnlocks: () => Promise<void>;
  clearExtensionStorage: () => Promise<void>;
};

export type WorkerFixtures = {
  liveSignerWorker: LiveSignerController;
  onboardedLiveSignerProfile: OnboardedStoredProfile;
};
