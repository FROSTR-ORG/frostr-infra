import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

import { expect, test, type Page } from '@playwright/test';

import { IGLOO_UI_DIR, REPO_ROOT_DIR } from '../../shared/repo-paths';

const screenshotDir = path.join(REPO_ROOT_DIR, '.tmp', 'igloo-ui-showcase');
const stylesPath = path.join(screenshotDir, 'styles.css');

test.beforeAll(() => {
  mkdirSync(screenshotDir, { recursive: true });
  // igloo-ui is source-only (no dist build). Compile its source styles through the
  // shared Tailwind preset into a temp file for the showcase to inline.
  execFileSync(
    'npx',
    [
      'tailwindcss',
      '-c',
      path.join(IGLOO_UI_DIR, 'tailwind.config.js'),
      '-i',
      path.join(IGLOO_UI_DIR, 'src', 'styles.css'),
      '-o',
      stylesPath,
    ],
    {
      cwd: IGLOO_UI_DIR,
      env: { ...process.env, BROWSERSLIST_IGNORE_OLD_DATA: '1' },
      stdio: 'inherit',
    },
  );
});

test.describe('igloo-ui Paper reference showcase @fast', () => {
  test('welcome returning profiles reference screen is visible and captured', async ({ page }) => {
    await loadShowcase(page, welcomeReturningProfiles());

    await expect(page.getByText('Primary Browser Device')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Load Profile' }).first()).toBeVisible();
    await writeScreenshot(page, 'welcome-returning-profiles.png');
  });

  test('create keyset reference screen is visible and captured', async ({ page }) => {
    await loadShowcase(page, createKeyset());

    await expect(page.getByText('Create New Keyset')).toBeVisible();
    await expect(page.getByText('Any 2 of 3 shares can sign')).toBeVisible();
    await writeScreenshot(page, 'create-keyset.png');
  });

  test('signer dashboard reference screen is visible and captured', async ({ page }) => {
    await loadShowcase(page, signerDashboard());

    await expect(page.getByText('My Signing Key')).toBeVisible();
    await expect(page.getByText('Connected to wss://relay.primal.net, wss://relay.damus.io')).toBeVisible();
    await writeScreenshot(page, 'signer-dashboard.png');
  });

  test('policies reference screen is visible and captured', async ({ page }) => {
    await loadShowcase(page, policies());

    await expect(page.getByText('Signer Policies')).toBeVisible();
    await expect(page.getByText('Peer Policies')).toBeVisible();
    await writeScreenshot(page, 'policies.png');
  });
});

async function loadShowcase(page: Page, content: string) {
  const styles = readFileSync(stylesPath, 'utf8');
  await page.setContent(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>${styles}</style>
      </head>
      <body>
        <main class="min-h-screen bg-igloo-page text-igloo-text" style="background-image: linear-gradient(160deg, #030712 0%, #111827 50%, #1E3A8A 100%);">
          ${content}
        </main>
      </body>
    </html>
  `);
}

async function writeScreenshot(page: Page, filename: string) {
  await page.screenshot({
    path: path.join(screenshotDir, filename),
    fullPage: true,
  });
}

function header(mode: 'welcome' | 'task' | 'dashboard', label = 'Create') {
  const right =
    mode === 'welcome'
      ? ['Website', 'Docs', 'GitHub'].map((item) => `<a class="font-sharetech text-[13px] leading-4 text-[#8494A7]">${item}</a>`).join('')
      : mode === 'task'
        ? `<span class="font-sharetech text-[13px] leading-4 text-[#8494A7]">${label}</span>`
        : `<div class="flex items-center gap-2"><button class="rounded-md px-3 py-1.5 text-sm text-igloo-primary">Recover</button><button class="rounded-md px-3 py-1.5 text-sm text-igloo-primary">Policies</button><button class="rounded-md px-3 py-1.5 text-sm text-igloo-primary">Settings</button></div>`;

  return `
    <header class="flex w-full justify-center px-20 py-5">
      <div class="flex w-full max-w-[1000px] items-center justify-between rounded-xl border border-igloo-border bg-igloo-panel px-5 py-3.5">
        <div>
          <div class="text-[28px] font-bold leading-8 tracking-[-0.01em] text-igloo-primary">Igloo</div>
          ${mode === 'dashboard' ? '' : '<div class="text-xs leading-4 tracking-[0.01em] text-igloo-subtle">Threshold Signing for Nostr</div>'}
        </div>
        <div class="flex items-center gap-5">${right}</div>
      </div>
    </header>
  `;
}

function welcomeReturningProfiles() {
  const card = (label: string, meta: string) => `
    <section class="flex h-26 w-[480px] items-center gap-4 rounded-xl border border-igloo-border bg-igloo-panel px-7 py-4">
      <div class="flex size-10 items-center justify-center rounded-[10px] border border-igloo-border bg-igloo-primary/15 text-igloo-primary">#</div>
      <div class="min-w-0 flex-1">
        <div class="font-sharetech text-[17px] leading-[22px] text-igloo-primary">${label}</div>
        <div class="mt-1 flex items-center gap-2 font-sharetech text-[13px] leading-4 text-[#8494A7]">${meta}<span class="text-igloo-border">.</span><span>2/3</span></div>
      </div>
      <div class="grid w-24 gap-1.5">
        <button class="h-8 rounded-lg bg-igloo-action text-sm font-medium text-white">Load Profile</button>
        <button class="h-8 rounded-lg border border-igloo-border text-sm font-medium text-igloo-primary">Delete</button>
      </div>
    </section>
  `;

  return `
    ${header('welcome')}
    <section class="flex flex-col items-center gap-8 pt-24">
      <div class="text-center">
        <h1 class="font-sharetech text-4xl leading-[44px] text-igloo-primary">Igloo Web</h1>
        <p class="mt-1 text-[15px] leading-[22px] text-[#8494A7]">Select a profile to unlock this browser workspace.</p>
      </div>
      <div class="grid gap-2">
        ${card('Primary Browser Device', 'npub1qe3...7k4m')}
        ${card('Backup Device', 'npub1w8j...9q2p')}
        ${card('Travel Laptop', 'npub1c0d...3a7x')}
      </div>
    </section>
  `;
}

function createKeyset() {
  return `
    ${header('task', 'Create')}
    <section class="mx-auto flex w-[640px] flex-col gap-5 pt-4">
      <button class="inline-flex min-h-8 items-center text-[13px] leading-[18px] text-igloo-muted">Back to Welcome</button>
      <div class="grid grid-cols-3 items-start gap-0">
        ${step('1', 'Create Keyset', true)}
        ${step('2', 'Setup Profile', false)}
        ${step('3', 'Distribute', false)}
      </div>
      <div>
        <h1 class="font-sharetech text-2xl leading-8 text-igloo-primary">Create New Keyset</h1>
        <p class="mt-2 text-sm leading-5 text-[#8494A7]">Define the group profile for a new keyset. After generation, this browser keeps one share locally.</p>
      </div>
      <label class="grid gap-1.5 text-[13px] font-medium text-igloo-primary">Group Name
        <div class="rounded-lg border border-igloo-border bg-igloo-panel px-3.5 py-2.5 text-sm text-igloo-subtle">e.g. Treasury Signers</div>
      </label>
      <div class="grid grid-cols-[1fr_auto_1fr] gap-4">
        ${counter('Threshold', '2')}
        <div class="flex items-end pb-3 font-sharetech text-xl text-igloo-subtle">/</div>
        ${counter('Total Shares', '3')}
      </div>
      <p class="text-xs leading-4 text-igloo-subtle">Any 2 of 3 shares can sign - min threshold is 2, min shares is 3</p>
      <button class="rounded-lg bg-igloo-action px-5 py-3 text-sm font-semibold text-white">Continue</button>
    </section>
  `;
}

function step(index: string, label: string, active: boolean) {
  return `
    <div class="flex flex-col items-center gap-2">
      <div class="flex size-9 items-center justify-center rounded-full border-2 ${active ? 'border-igloo-action text-igloo-primary' : 'border-igloo-border text-igloo-muted'}">${index}</div>
      <div class="text-center text-xs font-medium ${active ? 'text-igloo-primary' : 'text-igloo-muted'}">${label}</div>
    </div>
  `;
}

function counter(label: string, value: string) {
  return `
    <label class="grid gap-1.5 text-[13px] font-medium text-igloo-primary">${label}
      <div class="grid h-10 grid-cols-[40px_1fr_40px] overflow-hidden rounded-lg border border-igloo-border bg-igloo-panel">
        <span class="grid place-items-center border-r border-igloo-border-muted text-igloo-subtle">-</span>
        <span class="grid place-items-center font-sharetech text-base text-igloo-text">${value}</span>
        <span class="grid place-items-center border-l border-igloo-border-muted text-igloo-primary">+</span>
      </div>
    </label>
  `;
}

function signerDashboard() {
  return `
    ${header('dashboard')}
    <section class="mx-auto flex w-[1000px] flex-col gap-4 pt-2">
      <div class="rounded-[10px] border border-igloo-border-muted bg-igloo-panel px-5 py-3.5">
        <span class="font-sharetech text-sm text-igloo-primary">My Signing Key</span>
        <span class="mx-2 text-igloo-subtle">.</span>
        <span class="text-xs text-[#8494A7]">2/3</span>
        <span class="mx-4 inline-block h-4 border-l border-igloo-border"></span>
        <span class="text-xs text-[#8494A7]">Share #1</span>
      </div>
      <div class="flex items-start justify-between rounded-[14px] border border-igloo-info/20 bg-igloo-panel-strong px-5 py-4">
        <div>
          <div class="font-semibold text-green-100">Signer online</div>
          <div class="mt-2 text-[15px] leading-[22px] text-igloo-muted">Connected to wss://relay.primal.net, wss://relay.damus.io</div>
        </div>
        <button class="h-10 rounded-xl border border-igloo-error/35 px-4 text-igloo-error">Stop Signer</button>
      </div>
      <section class="overflow-hidden rounded-[10px] border border-igloo-border-muted bg-[#11182766]">
        <header class="border-b border-igloo-border-muted px-5 py-4 font-semibold text-igloo-text">Peer Pool</header>
        ${peer('Alice Tablet', 'READY', '90%', '75%', 'text-igloo-success')}
        ${peer('Bob Phone', 'LOW', '40%', '27%', 'text-igloo-warning')}
        ${peer('Cold Storage', 'OFFLINE', '0%', '0%', 'text-igloo-subtle')}
      </section>
    </section>
  `;
}

function peer(name: string, status: string, inWidth: string, outWidth: string, tone: string) {
  return `
    <div class="flex items-center gap-4 border-b border-igloo-border-muted px-5 py-3 last:border-b-0">
      <div class="size-2.5 rounded-full bg-current ${tone}"></div>
      <div class="w-40 font-sharetech text-sm text-igloo-text">${name}</div>
      <div class="rounded-sm border border-current/30 px-1.5 py-0.5 font-sharetech text-[11px] ${tone}">${status}</div>
      <div class="w-20"><div class="h-1 rounded bg-slate-700"><div class="h-1 rounded bg-igloo-primary" style="width:${inWidth}"></div></div></div>
      <div class="w-20"><div class="h-1 rounded bg-slate-700"><div class="h-1 rounded bg-igloo-primary/60" style="width:${outWidth}"></div></div></div>
    </div>
  `;
}

function policies() {
  return `
    ${header('dashboard')}
    <section class="mx-auto flex w-[1000px] flex-col gap-4 pt-2">
      <div class="rounded-[10px] border border-igloo-border-muted bg-igloo-panel px-5 py-3.5">
        <span class="font-sharetech text-sm text-igloo-primary">My Signing Key</span>
        <span class="mx-2 text-igloo-subtle">.</span>
        <span class="text-xs text-[#8494A7]">Share #1</span>
      </div>
      <section class="rounded-[10px] border border-igloo-border-muted bg-[#11182766]">
        <header class="border-b border-igloo-border-muted px-5 py-3.5 font-semibold text-igloo-text">Signer Policies</header>
        <div class="p-5 text-sm text-igloo-muted">Effective signer permissions are derived from runtime policy state.</div>
        ${policyRow('request', ['ping', 'onboard', 'sign'])}
        ${policyRow('respond', ['ping', 'sign', 'ecdh'])}
      </section>
      <section class="rounded-[10px] border border-igloo-border-muted bg-[#11182766]">
        <header class="border-b border-igloo-border-muted px-5 py-3.5 font-semibold text-igloo-text">Peer Policies</header>
        ${peerPolicy('npub1qe3...7k4m', ['ping', 'sign', 'ecdh'])}
        ${peerPolicy('npub1w8j...9q2p', ['ping', 'ecdh'])}
        ${peerPolicy('npub1c0d...3a7x', [])}
      </section>
    </section>
  `;
}

function policyRow(label: string, tags: string[]) {
  return `<div class="flex items-center gap-3 px-5 py-2"><span class="w-20 font-sharetech text-igloo-subtle">${label}</span>${tags.map(tag).join('')}</div>`;
}

function peerPolicy(pubkey: string, tags: string[]) {
  return `<div class="flex items-center justify-between border-b border-igloo-border-muted px-5 py-3 last:border-b-0"><span class="font-sharetech text-sm text-igloo-primary">${pubkey}</span><div class="flex gap-1.5">${tags.length ? tags.map(tag).join('') : tag('unset')}</div></div>`;
}

function tag(label: string) {
  const muted = label === 'unset';
  return `<span class="rounded-sm border ${muted ? 'border-igloo-subtle/30 bg-igloo-subtle/15 text-igloo-muted' : 'border-igloo-success/30 bg-igloo-success/15 text-igloo-success'} px-2 py-0.5 font-sharetech text-[11px] uppercase">${label}</span>`;
}
