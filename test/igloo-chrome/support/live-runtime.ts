import { expect } from '@playwright/test';

import {
  assertRuntimeReadiness,
  assertNoncePoolHydrated,
  type RuntimeReadinessResult,
  type RuntimeSnapshotResult,
} from './runtime';

type RuntimePrepareReadinessResult = {
  runtime: RuntimeReadinessResult['runtime'];
  readiness: RuntimeReadinessResult;
};

export function unwrapRuntimePrepareReadinessResult(
  result: RuntimePrepareReadinessResult
): RuntimeReadinessResult {
  return result.readiness;
}

export async function waitForLiveSignReady(
  fetchRuntimeSnapshot: <T>() => Promise<T>,
  label: string,
  expectedPeers = 2,
  minSignReadyPeers = 1
) {
  await expect
    .poll(async () => {
      try {
        const snapshot = await fetchRuntimeSnapshot<RuntimeSnapshotResult>();
        assertNoncePoolHydrated(label, snapshot, expectedPeers, minSignReadyPeers);
        return 'ready';
      } catch (error) {
        return error instanceof Error ? error.message : String(error);
      }
    }, {
      timeout: 10_000,
      intervals: [250, 500, 1_000],
    })
    .toBe('ready');
}

export async function waitForLiveEcdhReady(
  prepareRuntimeReadiness: <T>(operation: 'sign' | 'ecdh') => Promise<T>,
  label: string
) {
  await expect
    .poll(async () => {
      try {
        const result = await prepareRuntimeReadiness<RuntimePrepareReadinessResult>('ecdh');
        const readiness = unwrapRuntimePrepareReadinessResult(result);
        assertRuntimeReadiness(label, readiness, 'ecdh');
        return 'ready';
      } catch (error) {
        return error instanceof Error ? error.message : String(error);
      }
    }, {
      timeout: 10_000,
      intervals: [250, 500, 1_000],
    })
    .toBe('ready');
}

export async function seedAndActivateLiveProfile(input: {
  seedProfile: (profile: { id?: string | null }) => Promise<unknown>;
  activateProfile: (profileId: string) => Promise<unknown>;
  profile: { id?: string | null };
}) {
  await input.seedProfile(input.profile);
  if (!input.profile.id) {
    throw new Error('Live signer profile is missing an id');
  }
  await input.activateProfile(input.profile.id);
}

export async function prepareLiveProfileForSigning(input: {
  seedProfile: (profile: { id?: string | null }) => Promise<unknown>;
  activateProfile: (profileId: string) => Promise<unknown>;
  fetchRuntimeSnapshot: <T>() => Promise<T>;
  profile: { id?: string | null };
  label: string;
  expectedPeers?: number;
  minSignReadyPeers?: number;
}) {
  await seedAndActivateLiveProfile(input);
  await waitForLiveSignReady(
    input.fetchRuntimeSnapshot,
    input.label,
    input.expectedPeers,
    input.minSignReadyPeers
  );
}
