import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type { Page } from '@playwright/test';

import { REPO_ROOT_DIR } from './repo-paths';

// Single source for visual/agent capture (ADR-013 Q3). Replaces the per-spec
// `capture()` helpers that were copy-pasted across the 7 pwa `@visual` specs and
// the chrome/home `@agent` capture tools.

// --- @visual storage-seeded snapshots ---------------------------------------
// Output tree: .tmp/visual/<client>/<section>/<name>.png (the paths the pwa
// visual-manifest.json references — unchanged by this consolidation).
export function visualSectionDir(client: string, section: string): string {
  return path.join(REPO_ROOT_DIR, '.tmp', 'visual', client, section);
}

export async function captureVisual(
  page: Page,
  opts: { client: string; section: string; name: string },
): Promise<string> {
  const dir = visualSectionDir(opts.client, opts.section);
  await mkdir(dir, { recursive: true });
  const fileName = opts.name.endsWith('.png') ? opts.name : `${opts.name}.png`;
  const file = path.join(dir, fileName);
  await page.screenshot({ path: file, fullPage: true });
  return file;
}

// --- @agent "render + see a screen" tool artifacts --------------------------
// Output dir: .tmp/agent/ (the documented `make screenshot` contract — a full-page
// PNG, a visible-text dump, and a machine-readable screenshot.json an agent can
// read instead of scraping stdout).
export const AGENT_OUT_DIR = path.join(REPO_ROOT_DIR, '.tmp', 'agent');

export async function captureAgentArtifact(
  page: Page,
  // `baseName` overrides the artifact file stem; it defaults to `<client>-<state>`
  // (chrome/home), but the pwa tool is the default client and writes a bare
  // `<state>` per the documented `make screenshot` contract.
  opts: { client: string; state: string; baseName?: string },
): Promise<{ png: string; txt: string }> {
  await mkdir(AGENT_OUT_DIR, { recursive: true });
  const base = opts.baseName ?? `${opts.client}-${opts.state}`;
  const png = path.join(AGENT_OUT_DIR, `${base}.png`);
  const txt = path.join(AGENT_OUT_DIR, `${base}.txt`);
  await page.screenshot({ path: png, fullPage: true });
  await writeFile(txt, await page.locator('body').innerText(), 'utf8');
  await writeFile(
    path.join(AGENT_OUT_DIR, 'screenshot.json'),
    `${JSON.stringify({ ok: true, client: opts.client, state: opts.state, png, txt }, null, 2)}\n`,
    'utf8',
  );
  return { png, txt };
}
