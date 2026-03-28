import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn, type ChildProcess } from 'node:child_process';
import { existsSync } from 'node:fs';
import { cp, mkdtemp, readFile, rm } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';

import { SimplePool, nip44, type Event, type Filter } from 'nostr-tools';

import { logE2E, withLoggedStep } from '../../shared/observability';
import { ensureBifrostDevtoolsBinary } from '../../shared/bifrost-devtools-binaries';
import { loadBridgeWasmModule } from '../../shared/bridge-wasm';
import { IGLOO_SHELL_DIR } from '../../shared/repo-paths';
import {
  IGLOO_SHELL_TARGET_DIR,
  ensureIglooShellBinary as ensureSharedIglooShellBinary
} from '../../shared/igloo-shell-binaries';

type LiveSignerProfile = {
  groupName: string;
  onboardPackage?: string;
  onboardPassword?: string;
  relays: string[];
  publicKey: string;
  peerPubkey: string;
};

type ManagedResponderSetup = {
  demoDir: string;
  profileId: string;
  shellEnv: NodeJS.ProcessEnv;
};

export type LiveSignerBackupPublishResult = {
  profileId: string;
  relays: string[];
  eventId: string;
  authorPubkey: string;
};

export type LiveSignerFixture = {
  relayUrl: string;
  profile: LiveSignerProfile;
  requestOnboardNonceCount: () => Promise<number>;
  publishBackup: () => Promise<LiveSignerBackupPublishResult>;
  stopRelay: () => Promise<void>;
  stopResponder: () => Promise<void>;
  close: () => Promise<void>;
};

export type LiveSignerController = {
  currentForTest: () => Promise<LiveSignerFixture>;
  resetForTest: () => Promise<LiveSignerFixture>;
  close: () => Promise<void>;
};

const BIFROST_EVENT_KIND = 20_000;

function hexToBytes(value: string): Uint8Array {
  const clean = value.toLowerCase();
  if (clean.length % 2 !== 0) {
    throw new Error('hex string must have even length');
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function normalizeNip44PayloadForJs(value: string): string {
  const trimmed = value.trim();
  const mod = trimmed.length % 4;
  if (mod === 0) return trimmed;
  return `${trimmed}${'='.repeat(4 - mod)}`;
}

async function readJson<T>(filePath: string): Promise<T> {
  const raw = await readFile(filePath, 'utf8');
  return JSON.parse(raw) as T;
}

function cloneLiveSignerProfile(profile: LiveSignerProfile): LiveSignerProfile {
  return {
    ...profile,
    relays: [...profile.relays],
  };
}

async function ensureIglooShellBinary() {
  await withLoggedStep('chrome.live-signer', 'build-igloo-shell-binary', undefined, async () => {
    ensureSharedIglooShellBinary();
  });
  return ensureSharedIglooShellBinary();
}

function managedShellEnv(root: string): NodeJS.ProcessEnv {
  const xdgRoot = path.join(root, 'xdg');
  return {
    ...process.env,
    CARGO_TARGET_DIR: IGLOO_SHELL_TARGET_DIR,
    XDG_CONFIG_HOME: path.join(xdgRoot, 'config'),
    XDG_DATA_HOME: path.join(xdgRoot, 'data'),
    XDG_STATE_HOME: path.join(xdgRoot, 'state'),
    IGLOO_SHELL_VAULT_PASSPHRASE: 'playwright-live-passphrase'
  };
}

function runIglooShellJson(args: string[], env: NodeJS.ProcessEnv) {
  const raw = execFileSync(awaitlessEnsureIglooShellBinary(), args, {
    cwd: IGLOO_SHELL_DIR,
    encoding: 'utf8',
    env
  }).trim();
  return JSON.parse(raw) as Record<string, unknown>;
}

function awaitlessEnsureIglooShellBinary() {
  return ensureSharedIglooShellBinary();
}

function findStringField(value: unknown, field: string): string | null {
  if (!value || typeof value !== 'object') return null;
  if (Array.isArray(value)) {
    for (const entry of value) {
      const found = findStringField(entry, field);
      if (found) return found;
    }
    return null;
  }

  const record = value as Record<string, unknown>;
  if (typeof record[field] === 'string') {
    return record[field] as string;
  }
  for (const entry of Object.values(record)) {
    const found = findStringField(entry, field);
    if (found) return found;
  }
  return null;
}

async function waitForRelayPort(host: string, port: number, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ready = await new Promise<boolean>((resolve) => {
      const socket = net.createConnection({ host, port });
      socket.once('connect', () => {
        socket.destroy();
        resolve(true);
      });
      socket.once('error', () => {
        socket.destroy();
        resolve(false);
      });
    });
    if (ready) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for relay ${host}:${port}`);
}

class ManagedRelayProcess {
  private child: ChildProcess | null = null;

  constructor(private readonly port: number) {}

  url(): string {
    return `ws://127.0.0.1:${this.port}`;
  }

  isRunning(): boolean {
    return this.child !== null && this.child.exitCode === null;
  }

  async start(): Promise<void> {
    if (this.isRunning()) return;

    const relayBinary = ensureBifrostDevtoolsBinary();
    const child = spawn(
      relayBinary,
      ['relay', '--host', '127.0.0.1', '--port', String(this.port)],
      {
        cwd: path.join(IGLOO_SHELL_DIR, '..', 'bifrost-rs'),
        env: process.env,
        stdio: ['ignore', 'pipe', 'pipe'],
      },
    );

    child.stdout?.on('data', (chunk: Buffer) => {
      logE2E('chrome.live-signer', 'relay-stdout', {
        port: this.port,
        message: chunk.toString('utf8').trim(),
      });
    });
    child.stderr?.on('data', (chunk: Buffer) => {
      logE2E('chrome.live-signer', 'relay-stderr', {
        port: this.port,
        message: chunk.toString('utf8').trim(),
      });
    });

    this.child = child;

    try {
      await waitForRelayPort('127.0.0.1', this.port, 5_000);
    } catch (error) {
      await this.stop();
      throw error;
    }
  }

  async stop(): Promise<void> {
    const child = this.child;
    if (!child) return;

    this.child = null;
    child.kill('SIGTERM');
    await new Promise<void>((resolve) => {
      const timeout = setTimeout(() => {
        child.kill('SIGKILL');
      }, 1_000);
      child.once('exit', () => {
        clearTimeout(timeout);
        resolve();
      });
      child.once('close', () => {
        clearTimeout(timeout);
        resolve();
      });
    });
  }
}

async function generateDemoResponderConfig(
  relayUrl: string,
  root: string
): Promise<ManagedResponderSetup> {
  const demoDir = path.join(root, 'demo-2of3');
  const devtoolsBinary = ensureBifrostDevtoolsBinary();
  await withLoggedStep('chrome.live-signer', 'generate-demo-material', { demoDir, relayUrl }, async () => {
    execFileSync(
      devtoolsBinary,
      [
        'keygen',
        '--out-dir',
        demoDir,
        '--threshold',
        '2',
        '--count',
        '3',
        '--relay',
        relayUrl
      ],
      {
        cwd: path.join(IGLOO_SHELL_DIR, '..', 'bifrost-rs'),
        encoding: 'utf8',
        env: process.env
      }
    );
  });

  const shellEnv = managedShellEnv(root);
  await withLoggedStep('chrome.live-signer', 'relays-set', { relayUrl }, async () => {
    execFileSync(await ensureIglooShellBinary(), ['relays', 'set', 'local', relayUrl], {
      cwd: IGLOO_SHELL_DIR,
      encoding: 'utf8',
      env: shellEnv
    });
  });

  const importJson = await withLoggedStep(
    'chrome.live-signer',
    'profile-import',
    { demoDir },
    async () =>
      runIglooShellJson(
        [
          'import',
          '--group',
          path.join(demoDir, 'group.json'),
          '--share',
          path.join(demoDir, 'share-alice.json'),
          '--label',
          'alice-live',
          '--vault-secret',
          'playwright-live-passphrase',
          '--relay-profile',
          'local',
          '--json'
        ],
        shellEnv
      )
  );
  const profileId = findStringField(importJson, 'id');
  if (!profileId) {
    throw new Error('profile import did not return an id');
  }

  return {
    demoDir,
    profileId,
    shellEnv
  };
}

async function buildLiveProfile(
  relayUrl: string,
  profileId: string,
  shellEnv: NodeJS.ProcessEnv,
  demoDir: string
): Promise<LiveSignerProfile> {
  return await withLoggedStep(
    'chrome.live-signer',
    'build-live-profile',
    { relayUrl },
    async () => {
      const group = await readJson<{
        group_pk: string;
        members: Array<{ idx: number; pubkey: string }>;
      }>(path.join(demoDir, 'group.json'));
      const share = await readJson<{ idx: number; seckey: string }>(
        path.join(demoDir, 'share-bob.json')
      );

      const peerMember = group.members.find((member) => member.idx === 1);
      if (!peerMember) {
        throw new Error('demo group is missing member 1');
      }
      const onboardingPassword = 'playwright-password';
      const onboardingPath = path.join(demoDir, 'share-bob.bfonboard');
      await withLoggedStep(
        'chrome.live-signer',
        'profile-export-bfonboard',
        { profileId, relayUrl },
        async () => {
          execFileSync(
            await ensureIglooShellBinary(),
            [
              'export',
              profileId,
              '--format',
              'bfonboard',
              '--out',
              onboardingPath,
              '--recipient-share',
              path.join(demoDir, 'share-bob.json'),
              '--vault-passphrase-env',
              'IGLOO_SHELL_VAULT_PASSPHRASE',
              '--package-password-env',
              'LIVE_ONBOARD_PASSWORD'
            ],
            {
              cwd: IGLOO_SHELL_DIR,
              encoding: 'utf8',
              env: {
                ...shellEnv,
                LIVE_ONBOARD_PASSWORD: onboardingPassword
              }
            }
          );
        }
      );
      const onboardingPackage = (await readFile(onboardingPath, 'utf8')).trim();

      return {
        groupName: 'Playwright Live',
        onboardPackage: onboardingPackage,
        onboardPassword: onboardingPassword,
        relays: [relayUrl],
        publicKey: group.group_pk.toLowerCase(),
        peerPubkey: peerMember.pubkey.toLowerCase().slice(2)
      };
    }
  );
}

async function requestOnboardNonceCount(relayUrl: string, demoDir: string): Promise<number> {
  const group = await readJson<{
    members: Array<{ idx: number; pubkey: string }>;
  }>(path.join(demoDir, 'group.json'));
  const share = await readJson<{ idx: number; seckey: string }>(path.join(demoDir, 'share-bob.json'));
  const peerMember = group.members.find((member) => member.idx === 1);
  if (!peerMember) {
    throw new Error('demo group is missing required members');
  }

  const now = Math.floor(Date.now() / 1000);
  const conversationKey = nip44.v2.utils.getConversationKey(
    hexToBytes(share.seckey),
    peerMember.pubkey.toLowerCase().slice(2)
  );
  const bridgeWasm = await loadBridgeWasmModule();
  const requestBundle = JSON.parse(
    bridgeWasm.create_onboarding_request_bundle(
      share.seckey,
      peerMember.pubkey.toLowerCase().slice(2),
      BigInt(BIFROST_EVENT_KIND),
      now,
    ),
  ) as {
    request_id: string;
    local_pubkey32: string;
    event_json: string;
  };
  const requestId = requestBundle.request_id;

  const pool = new SimplePool();
  const filter = {
    kinds: [BIFROST_EVENT_KIND],
    authors: [peerMember.pubkey.toLowerCase().slice(2)],
    '#p': [requestBundle.local_pubkey32.toLowerCase()],
    since: now - 5
  } as Filter;

  try {
    logE2E('chrome.live-signer', 'manual-onboard:start', {
      relayUrl,
      requestId,
      shareIdx: share.idx
    });
    return await new Promise<number>((resolve, reject) => {
      let settled = false;
      const timeout = setTimeout(() => {
        finish(() => {
          subscription.close('timeout');
          reject(new Error(`Timed out waiting for OnboardResponse for request ${requestId}`));
        });
      }, 10_000);
      const finish = (fn: () => void) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        fn();
      };

      const subscription = pool.subscribeMany([relayUrl], filter, {
        onevent: (event: Event) => {
          try {
            const decrypted = nip44.v2.decrypt(
              normalizeNip44PayloadForJs(event.content),
              conversationKey
            );
            const envelope = JSON.parse(decrypted) as {
              request_id?: string;
              payload?: {
                type?: string;
                data?: {
                  nonces?: unknown[];
                };
              };
            };
            if (envelope.request_id !== requestId) return;
            if (envelope.payload?.type !== 'OnboardResponse') return;
            const nonces = Array.isArray(envelope.payload.data?.nonces)
              ? envelope.payload.data.nonces
              : [];
            finish(() => {
              subscription.close('resolved');
              logE2E('chrome.live-signer', 'manual-onboard:response', {
                relayUrl,
                requestId,
                nonceCount: nonces.length
              });
              resolve(nonces.length);
            });
          } catch {
            // Ignore unrelated events.
          }
        },
        onclose: (reasons) => {
          finish(() => {
            reject(new Error(`Relay closed before onboard response: ${reasons.join(', ')}`));
          });
        }
      });

      const event = JSON.parse(requestBundle.event_json) as Event;

      const results = pool.publish([relayUrl], event);
      Promise.allSettled(results).then((entries) => {
        logE2E('chrome.live-signer', 'manual-onboard:publish', {
          relayUrl,
          requestId,
          relaysOk: entries.filter((entry) => entry.status === 'fulfilled').length,
          relaysTotal: entries.length
        });
        const hasSuccess = entries.some((entry) => entry.status === 'fulfilled');
        if (!hasSuccess) {
          finish(() => {
            subscription.close('publish-failed');
            reject(new Error('Failed to publish onboard request'));
          });
        }
      });
    });
  } finally {
    pool.close([relayUrl]);
    pool.destroy();
  }
}

function randomPort() {
  return 18_000 + Math.floor(Math.random() * 10_000);
}

class SharedLiveSignerController implements LiveSignerController {
  private readonly port: number;
  private readonly relay: ManagedRelayProcess;
  private readonly tempRootPromise: Promise<string>;
  private snapshotRoot = '';
  private demoDir = '';
  private binaryPath = '';
  private responderProfileId = '';
  private shellEnv: NodeJS.ProcessEnv | null = null;
  private needsResponderRestart = false;
  private baseProfile: LiveSignerProfile | null = null;
  private currentProfile: LiveSignerProfile | null = null;

  constructor(port: number) {
    this.port = port;
    this.relay = new ManagedRelayProcess(port);
    this.tempRootPromise = mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-live-'));
  }

  static async create(): Promise<SharedLiveSignerController> {
    const controller = new SharedLiveSignerController(randomPort());
    await controller.initialize();
    return controller;
  }

  async currentForTest(): Promise<LiveSignerFixture> {
    await withLoggedStep('chrome.live-signer', 'prepare-current-fixture', { relayUrl: this.relay.url() }, async () => {
      await this.ensureRelay();
      await this.ensureResponder();
      if (!this.currentProfile && this.baseProfile) {
        this.currentProfile = cloneLiveSignerProfile(this.baseProfile);
      }
    });
    return this.buildFixture();
  }

  async resetForTest(): Promise<LiveSignerFixture> {
    await withLoggedStep('chrome.live-signer', 'reset-fixture', { relayUrl: this.relay.url() }, async () => {
      await this.relay.stop();
      await this.ensureRelay();
      await this.stopResponderProcess();
      await this.restoreResponderSnapshot();
      this.needsResponderRestart = true;
      await this.ensureResponder();
      if (!this.baseProfile) {
        throw new Error('live signer base profile is not configured');
      }
      this.currentProfile = cloneLiveSignerProfile(this.baseProfile);
    });

    return this.buildFixture();
  }

  private buildFixture(): LiveSignerFixture {
    const controller = this;
    return {
      relayUrl: controller.relay.url(),
      profile: controller.currentProfile!,
      requestOnboardNonceCount: async () => {
        controller.requireProfile();
        return await requestOnboardNonceCount(controller.relay.url(), controller.demoDir);
      },
      publishBackup: async () => {
        controller.requireProfile();
        return await controller.publishBackup();
      },
      stopRelay: async () => {
        await controller.relay.stop();
        controller.needsResponderRestart = true;
      },
      stopResponder: async () => {
        await controller.stopResponderProcess();
      },
      close: async () => {
        await controller.close();
      }
    };
  }

  async close(): Promise<void> {
    await this.stopResponderProcess();
    await this.relay.stop();
    const tempRoot = await this.tempRootPromise;
    await rm(tempRoot, { recursive: true, force: true });
  }

  private requireProfile(): LiveSignerProfile {
    if (!this.currentProfile) {
      throw new Error('live signer profile has not been prepared for this test');
    }
    return this.currentProfile;
  }

  private async publishBackup(): Promise<LiveSignerBackupPublishResult> {
    if (!this.shellEnv || !this.responderProfileId) {
      throw new Error('live signer responder profile is not configured');
    }
    const result = await withLoggedStep(
      'chrome.live-signer',
      'profile-publish-backup',
      { profileId: this.responderProfileId, relayUrl: this.relay.url() },
      async () =>
        runIglooShellJson(
          [
            'profile',
            'backup',
            this.responderProfileId,
            '--vault-passphrase-env',
            'IGLOO_SHELL_VAULT_PASSPHRASE'
          ],
          this.shellEnv!,
        ),
    );

    return {
      profileId: String(result.profile_id),
      relays: Array.isArray(result.relays)
        ? result.relays.filter((value): value is string => typeof value === 'string')
        : [],
      eventId: String(result.event_id),
      authorPubkey: String(result.author_pubkey),
    };
  }

  private async initialize(): Promise<void> {
    await this.ensureRelay();
    const tempRoot = await this.tempRootPromise;
    this.binaryPath = await ensureIglooShellBinary();
    const regenerated = await generateDemoResponderConfig(this.relay.url(), tempRoot);
    this.demoDir = regenerated.demoDir;
    this.responderProfileId = regenerated.profileId;
    this.shellEnv = regenerated.shellEnv;
    this.snapshotRoot = path.join(tempRoot, 'seed-xdg');
    await this.captureResponderSnapshot();
    this.baseProfile = await buildLiveProfile(
      this.relay.url(),
      this.responderProfileId,
      this.shellEnv,
      this.demoDir
    );
    this.currentProfile = cloneLiveSignerProfile(this.baseProfile);
    this.needsResponderRestart = true;
    await this.ensureResponder();
  }

  private async ensureRelay(): Promise<void> {
    if (this.relay.isRunning()) return;
    await withLoggedStep('chrome.live-signer', 'start-relay', { port: this.port }, async () => {
      await this.relay.start();
    });
  }

  private async ensureResponder(): Promise<void> {
    if (!this.shellEnv || !this.responderProfileId) {
      throw new Error('live signer responder profile is not configured');
    }
    if (!this.needsResponderRestart) {
      return;
    }

    try {
      await this.stopResponderProcess({ preserveRestartFlag: true });
      await withLoggedStep(
        'chrome.live-signer',
        'daemon-start',
        { profileId: this.responderProfileId },
        async () => {
          execFileSync(
            this.binaryPath,
            ['daemon', 'start', '--profile', this.responderProfileId],
            {
              cwd: IGLOO_SHELL_DIR,
              encoding: 'utf8',
              env: this.shellEnv!
            }
          );
        }
      );
      this.needsResponderRestart = false;
    } catch (error) {
      throw new Error(
        `Failed to start live signer responder: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  private async stopResponderProcess(options?: { preserveRestartFlag?: boolean }): Promise<void> {
    if (!this.shellEnv || !this.responderProfileId) {
      return;
    }
    const stateRoot = this.shellEnv.XDG_STATE_HOME;
    if (stateRoot) {
      const metadataPath = path.join(
        stateRoot,
        'igloo-shell',
        'profiles',
        this.responderProfileId,
        'daemon.json'
      );
      if (!existsSync(metadataPath)) {
        if (!options?.preserveRestartFlag) {
          this.needsResponderRestart = false;
        }
        return;
      }
    }
    try {
      execFileSync(this.binaryPath, ['daemon', 'stop', '--profile', this.responderProfileId], {
        cwd: IGLOO_SHELL_DIR,
        encoding: 'utf8',
        env: this.shellEnv
      });
    } catch {
      // Ignore already-stopped daemons during fixture cleanup.
    }
    if (!options?.preserveRestartFlag) {
      this.needsResponderRestart = false;
    }
  }

  private async captureResponderSnapshot(): Promise<void> {
    const tempRoot = await this.tempRootPromise;
    const stateRoot = path.join(tempRoot, 'xdg');
    await withLoggedStep(
      'chrome.live-signer',
      'snapshot-shell-state',
      { snapshotRoot: this.snapshotRoot },
      async () => {
        await rm(this.snapshotRoot, { recursive: true, force: true });
        await cp(stateRoot, this.snapshotRoot, { recursive: true });
      }
    );
  }

  private async restoreResponderSnapshot(): Promise<void> {
    if (!this.snapshotRoot) {
      throw new Error('live signer shell-state snapshot is not configured');
    }
    const tempRoot = await this.tempRootPromise;
    const stateRoot = path.join(tempRoot, 'xdg');
    await withLoggedStep(
      'chrome.live-signer',
      'restore-shell-state',
      { snapshotRoot: this.snapshotRoot },
      async () => {
        await rm(stateRoot, { recursive: true, force: true });
        await cp(this.snapshotRoot, stateRoot, { recursive: true });
      }
    );
    this.needsResponderRestart = true;
  }
}

export async function startLiveSignerFixture(): Promise<LiveSignerController> {
  return await SharedLiveSignerController.create();
}
