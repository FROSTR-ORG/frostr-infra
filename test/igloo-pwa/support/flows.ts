import { type Page } from '@playwright/test';

import { pages, type PwaPages } from './pages';

export interface GotoDistributeOptions {
  groupName?: string;
  localShareIdx?: number;
  profileName: string;
  password: string;
}

// Drives the create flow Welcome → Generate → Select Share → Save Profile and
// lands on Distribute Shares. Returns the page objects for follow-up steps.
// (For the rotate variant, drive selectMode('rotate') + the rotate panel via the
// page objects directly.)
export async function gotoCreateDistribute(
  page: Page,
  opts: GotoDistributeOptions,
): Promise<PwaPages> {
  const p = pages(page);
  await p.welcome.startGenerate();
  await p.create.fillGenerate({ groupName: opts.groupName });
  await p.create.generateNext();
  if (opts.localShareIdx != null) await p.create.selectShare(opts.localShareIdx);
  await p.create.selectShareNext();
  await p.create.fillSaveProfile({ name: opts.profileName, password: opts.password });
  await p.create.saveProfileNext();
  return p;
}

export interface CreateAndDistributeOptions extends GotoDistributeOptions {
  remotePackagePassword: string;
  finish?: boolean;
}

// Full path: create the profile, then prepare + mark-delivered every remote
// share, optionally clicking Finish Setup.
export async function createGeneratedProfileAndDistribute(
  page: Page,
  opts: CreateAndDistributeOptions,
): Promise<PwaPages> {
  const p = await gotoCreateDistribute(page, opts);
  const count = await p.distribute.cards().count();
  for (let i = 0; i < count; i += 1) {
    const card = p.distribute.cards().nth(i);
    await p.distribute.preparePackage(card, opts.remotePackagePassword);
    await p.distribute.markDelivered(card);
  }
  if (opts.finish) await p.distribute.finish();
  return p;
}
