import type { BrowserContext } from '@playwright/test';

import { openPageForStorage } from './transport';
import type { SeedPermissionPolicy, SeedProfileOverrides } from '../types';
import { buildSeedProfile } from './seed-profile';
import { createSeededProfileRecord } from './seed-crypto';

export async function seedProfileIntoExtension(
  context: BrowserContext,
  extensionId: string,
  overrides: SeedProfileOverrides = {}
) {
  const page = await openPageForStorage(context, extensionId);
  try {
    const seeded =
      overrides.storedBlobRecord && typeof overrides.sessionKeyB64 === 'string'
        ? {
            storedBlobRecord: overrides.storedBlobRecord,
            sessionKeyB64: overrides.sessionKeyB64,
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
        await chrome.storage.session.set({
          'igloo.v3.ext.sessionUnlocks': {
            [input.storedBlobRecord.id]: {
              keyB64: input.sessionKeyB64,
              updatedAt: Date.now(),
            },
          },
        });
        const local = await chrome.storage.local.get([
          'igloo.v3.ext.profiles',
          'igloo.v3.ext.activeProfileId',
        ]);
        const session = await chrome.storage.session.get('igloo.v3.ext.sessionUnlocks');
        return {
          activeProfileId: local['igloo.v3.ext.activeProfileId'],
          profileIds: Array.isArray(local['igloo.v3.ext.profiles'])
            ? local['igloo.v3.ext.profiles'].map((entry) => entry.id)
            : [],
          unlockKey:
            session['igloo.v3.ext.sessionUnlocks']?.[input.storedBlobRecord.id]?.keyB64 ?? null,
        };
      },
      seeded
    );
    if (
      verified.activeProfileId !== seeded.storedBlobRecord.id ||
      !verified.profileIds.includes(seeded.storedBlobRecord.id) ||
      verified.unlockKey !== seeded.sessionKeyB64
    ) {
      throw new Error('Failed to verify seeded extension profile state.');
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
      await chrome.storage.session.clear();
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
