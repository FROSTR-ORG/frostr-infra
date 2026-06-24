import type { BrowserContext } from '@playwright/test';

import { openPageForStorage } from './transport';
import type { SeedPermissionPolicy, SeedProfileOverrides } from '../types';
import { buildSeedProfile } from './seed-profile';
import { createSeededProfileRecord } from './seed-crypto';
import { PROFILE_BLOB_PASSWORD } from '../../../shared/test-secrets';

export async function seedProfileIntoExtension(
  context: BrowserContext,
  extensionId: string,
  overrides: SeedProfileOverrides = {}
) {
  const page = await openPageForStorage(context, extensionId);
  try {
    const seeded =
      overrides.storedBlobRecord
        ? {
            storedBlobRecord: overrides.storedBlobRecord,
          }
        : await createSeededProfileRecord(buildSeedProfile(overrides));
    const verified = await page.evaluate(
      async (input) => {
        await chrome.storage.local.set({
          'igloo.v3.ext.profiles': [
            input.storedBlobRecord,
          ],
          'igloo.v3.ext.activeProfileId': input.storedBlobRecord.id,
        });
        const unlockResponse = await chrome.runtime.sendMessage({
          type: 'ext.debug.seedProfileUnlock',
          profileId: input.storedBlobRecord.id,
          password: input.password,
        });
        const local = await chrome.storage.local.get([
          'igloo.v3.ext.profiles',
          'igloo.v3.ext.activeProfileId',
        ]);
        return {
          activeProfileId: local['igloo.v3.ext.activeProfileId'],
          profileIds: Array.isArray(local['igloo.v3.ext.profiles'])
            ? local['igloo.v3.ext.profiles'].map((entry) => entry.id)
            : [],
          unlocked: unlockResponse?.ok === true,
          unlockError: unlockResponse?.error ?? null,
        };
      },
      {
        ...seeded,
        password: overrides.onboardPassword ?? PROFILE_BLOB_PASSWORD,
      }
    );
    if (
      verified.activeProfileId !== seeded.storedBlobRecord.id ||
      !verified.profileIds.includes(seeded.storedBlobRecord.id) ||
      !verified.unlocked
    ) {
      throw new Error(`Failed to verify seeded extension profile state: ${verified.unlockError ?? 'unlock failed'}`);
    }
  } finally {
    await page.close().catch(() => undefined);
  }
}

export async function seedPermissionPoliciesIntoExtension(
  context: BrowserContext,
  extensionId: string,
  policies: SeedPermissionPolicy[]
) {
  const page = await openPageForStorage(context, extensionId);
  try {
    const verified = await page.evaluate(async (entries) => {
      await chrome.storage.local.set({
        'igloo.v3.ext.permissions': entries.map((entry) => ({
          ...entry,
          createdAt: entry.createdAt ?? Date.now(),
        })),
      });
      const stored = await chrome.storage.local.get('igloo.v3.ext.permissions');
      return Array.isArray(stored['igloo.v3.ext.permissions']) ? stored['igloo.v3.ext.permissions'] : [];
    }, policies);
    if (
      verified.length !== policies.length ||
      verified.some(
        (entry, index) =>
          entry.host !== policies[index]?.host ||
          entry.type !== policies[index]?.type ||
          entry.allow !== policies[index]?.allow,
      )
    ) {
      throw new Error('Failed to verify seeded extension permission policies.');
    }
  } finally {
    await page.close().catch(() => undefined);
  }
}

export async function clearSessionUnlocksInExtension(context: BrowserContext, extensionId: string) {
  const page = await openPageForStorage(context, extensionId);
  try {
    await page.evaluate(async () => {
      const response = (await chrome.runtime.sendMessage({
        type: 'ext.debug.clearProfileUnlocks',
      })) as { ok?: boolean; error?: string } | undefined;
      if (!response?.ok) {
        throw new Error(response?.error || 'Failed to clear profile unlocks');
      }
    });
  } finally {
    await page.close().catch(() => undefined);
  }
}

export async function clearExtensionStorageState(context: BrowserContext, extensionId: string) {
  const page = await openPageForStorage(context, extensionId);
  try {
    await page.evaluate(async () => {
      await chrome.storage.local.clear();
      await chrome.storage.session.clear();
    });
  } finally {
    await page.close().catch(() => undefined);
  }
}
