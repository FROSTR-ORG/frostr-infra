import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn, type ChildProcess } from 'node:child_process';
import { copyFile, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';

import { SimplePool, finalizeEvent, nip44, type Event, type Filter } from 'nostr-tools';
import { WebSocketServer, type WebSocket } from 'ws';

import { logE2E, withLoggedStep } from '../../shared/observability';
import { BIFROST_RS_DIR } from '../../shared/repo-paths';
import { assembleOnboardingPackage } from '../../shared/onboarding-package';
import { TEST_PEER_PUBLIC_KEY, TEST_PUBLIC_KEY } from './constants';

type RelayFilter = {
  kinds?: number[];
  authors?: string[];
  since?: number;
  until?: number;
};

type RelayClientState = {
  socket: WebSocket;
  subs: Map<string, RelayFilter[]>;
};

type NostrEventWire = {
  id: string;
  pubkey: string;
  created_at: number;
  kind: number;
  tags: string[][];
  content: string;
  sig: string;
};

type LiveSignerProfile = {
  keysetName: string;
  onboardPackage?: string;
  onboardPassword?: string;
  inviteChallengeHex32?: string;
  relays: string[];
  publicKey: string;
  peerPubkey: string;
};

export type LiveSignerFixture = {
  relayUrl: string;
  profile: LiveSignerProfile;
  requestOnboardNonceCount: () => Promise<number>;
  stopRelay: () => Promise<void>;
  stopResponder: () => Promise<void>;
  close: () => Promise<void>;
};

const DEMO_DIR = path.join(BIFROST_RS_DIR, 'dev', 'demo-2of2');
const BIFROST_TARGET_DIR = path.join(os.tmpdir(), 'igloo-chrome-bifrost-target');
const BIFROST_BINARY_PATH = path.join(BIFROST_TARGET_DIR, 'debug', 'bifrost');
const BIFROST_EVENT_KIND = 20_000;

let binaryPrepared = false;

function bytesToHex(value: Uint8Array) {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

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

function normalizeNip44PayloadForRust(value: string): string {
  return value.trim().replace(/=+$/g, '');
}

async function readJson<T>(filePath: string): Promise<T> {
  const raw = await readFile(filePath, 'utf8');
  return JSON.parse(raw) as T;
}

async function ensureBifrostBinary() {
  if (binaryPrepared) return BIFROST_BINARY_PATH;
  await withLoggedStep('chrome.live-signer', 'build-bifrost-binary', undefined, async () => {
    execFileSync(
      'cargo',
      ['build', '--offline', '-p', 'bifrost-app', '--bin', 'bifrost'],
      {
        cwd: BIFROST_RS_DIR,
        stdio: 'inherit',
        env: {
          ...process.env,
          CARGO_TARGET_DIR: BIFROST_TARGET_DIR
        }
      }
    );
  });
  binaryPrepared = true;
  return BIFROST_BINARY_PATH;
}

class LocalNostrRelay {
  private server: WebSocketServer | null = null;
  private readonly events = new Map<string, NostrEventWire>();
  private readonly clients = new Map<WebSocket, RelayClientState>();

  constructor(private readonly port: number) {}

  async start(): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      this.server = new WebSocketServer({ port: this.port }, () => resolve());
      this.server.once('error', reject);
      this.server.on('connection', (socket) => this.attachClient(socket));
    });
  }

  url(): string {
    return `ws://127.0.0.1:${this.port}`;
  }

  async stop(): Promise<void> {
    for (const state of this.clients.values()) {
      state.socket.terminate();
    }
    this.clients.clear();
    if (!this.server) return;

    await new Promise<void>((resolve) => {
      this.server?.close(() => resolve());
    });
    this.server = null;
  }

  private attachClient(socket: WebSocket): void {
    const state: RelayClientState = { socket, subs: new Map() };
    this.clients.set(socket, state);

    socket.on('message', (raw) => {
      try {
        this.handleMessage(state, raw.toString());
      } catch {
        // Keep the relay permissive for tests.
      }
    });

    socket.on('close', () => {
      this.clients.delete(socket);
    });
  }

  private handleMessage(state: RelayClientState, raw: string): void {
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed) || parsed.length === 0) return;

    const kind = parsed[0];
    if (kind === 'REQ') {
      const subId = parsed[1];
      if (typeof subId !== 'string') return;
      const filters = parsed.slice(2).filter((v): v is RelayFilter => !!v && typeof v === 'object');
      state.subs.set(subId, filters.length ? filters : [{}]);

      for (const event of this.events.values()) {
        if (this.matchesAnyFilter(event, filters)) {
          state.socket.send(JSON.stringify(['EVENT', subId, event]));
        }
      }
      state.socket.send(JSON.stringify(['EOSE', subId]));
      return;
    }

    if (kind === 'CLOSE') {
      const subId = parsed[1];
      if (typeof subId === 'string') {
        state.subs.delete(subId);
      }
      return;
    }

    if (kind === 'EVENT') {
      const event = parsed[1] as NostrEventWire | undefined;
      if (!event || typeof event.id !== 'string') return;
      this.events.set(event.id, event);
      this.broadcastEvent(event);
      state.socket.send(JSON.stringify(['OK', event.id, true, '']));
    }
  }

  private broadcastEvent(event: NostrEventWire): void {
    for (const state of this.clients.values()) {
      for (const [subId, filters] of state.subs.entries()) {
        if (!this.matchesAnyFilter(event, filters)) continue;
        state.socket.send(JSON.stringify(['EVENT', subId, event]));
      }
    }
  }

  private matchesAnyFilter(event: NostrEventWire, filters: RelayFilter[]): boolean {
    if (filters.length === 0) return true;
    return filters.some((filter) => this.matchesFilter(event, filter));
  }

  private matchesFilter(event: NostrEventWire, filter: RelayFilter): boolean {
    if (Array.isArray(filter.kinds) && !filter.kinds.includes(event.kind)) return false;
    if (Array.isArray(filter.authors) && !filter.authors.includes(event.pubkey)) return false;
    if (typeof filter.since === 'number' && event.created_at < filter.since) return false;
    if (typeof filter.until === 'number' && event.created_at > filter.until) return false;

    const pTags = (filter as Record<string, unknown>)['#p'];
    if (Array.isArray(pTags) && pTags.length > 0) {
      const targets = pTags.filter((value): value is string => typeof value === 'string');
      const eventPTags = event.tags
        .filter((tag) => Array.isArray(tag) && tag[0] === 'p' && typeof tag[1] === 'string')
        .map((tag) => tag[1]);
      if (!targets.some((target) => eventPTags.includes(target))) {
        return false;
      }
    }

    return true;
  }
}

async function waitForControlReady(socketPath: string, token: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  let lastError = 'unknown';

  while (Date.now() < deadline) {
    try {
      const response = await requestControl(socketPath, {
        request_id: randomBytes(8).toString('hex'),
        token,
        command: 'status'
      });
      if (response.ok) return;
      lastError = response.error ?? 'status not ok';
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error(`Timed out waiting for bifrost control socket: ${lastError}`);
}

function requestControl(
  socketPath: string,
  request: Record<string, unknown>
): Promise<{ ok: boolean; error?: string; result?: unknown }> {
  return awaitableControl(socketPath, JSON.stringify(request));
}

function awaitableControl(socketPath: string, payload: string) {
  return new Promise<{ ok: boolean; error?: string; result?: unknown }>((resolve, reject) => {
    const client = net.createConnection(socketPath);
    const chunks: Buffer[] = [];

    client.once('error', reject);
    client.on('data', (chunk) => {
      chunks.push(chunk);
    });
    client.on('end', () => {
      try {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(JSON.parse(text) as { ok: boolean; error?: string; result?: unknown });
      } catch (error) {
        reject(error);
      }
    });
    client.on('connect', () => {
      client.end(payload);
    });
  });
}

async function copyDemoResponderConfig(relayUrl: string, root: string) {
  const config = await readJson<Record<string, unknown>>(path.join(DEMO_DIR, 'bifrost-alice.json'));
  await copyFile(path.join(DEMO_DIR, 'group.json'), path.join(root, 'group.json'));
  await copyFile(path.join(DEMO_DIR, 'share-alice.json'), path.join(root, 'share-alice.json'));

  config.group_path = path.join(root, 'group.json');
  config.share_path = path.join(root, 'share-alice.json');
  config.state_path = path.join(root, 'state-alice.json');
  config.relays = [relayUrl];

  const configPath = path.join(root, 'bifrost-alice.json');
  await writeFile(configPath, JSON.stringify(config, null, 2));
  return configPath;
}

async function buildLiveProfile(relayUrl: string, configPath: string): Promise<LiveSignerProfile> {
  return await withLoggedStep(
    'chrome.live-signer',
    'build-live-profile',
    { relayUrl },
    async () => {
      const group = await readJson<{
        members: Array<{ idx: number; pubkey: string }>;
      }>(path.join(DEMO_DIR, 'group.json'));
      const share = await readJson<{ idx: number; seckey: string }>(
        path.join(DEMO_DIR, 'share-bob.json')
      );

      const peerMember = group.members.find((member) => member.idx === 1);
      if (!peerMember) {
        throw new Error('demo group is missing member 1');
      }

      const inviteToken = execFileSync(
        await ensureBifrostBinary(),
        ['--config', configPath, 'invite', 'create', '--relay', relayUrl],
        {
          cwd: BIFROST_RS_DIR,
          encoding: 'utf8',
          env: {
            ...process.env,
            CARGO_TARGET_DIR: BIFROST_TARGET_DIR
          }
        }
      ).trim();

      const assembled = assembleOnboardingPackage({
        shareIdx: share.idx,
        shareSecretHex32: share.seckey,
        peerPubkey32: peerMember.pubkey.toLowerCase().slice(2),
        relays: [relayUrl],
        inviteToken,
        password: 'playwright-password'
      });

      return {
        keysetName: 'Playwright Live',
        onboardPackage: assembled.onboardingPackage,
        onboardPassword: assembled.onboardingPassword,
        inviteChallengeHex32: assembled.challengeHex32,
        relays: [relayUrl],
        publicKey: TEST_PUBLIC_KEY,
        peerPubkey: TEST_PEER_PUBLIC_KEY
      };
    }
  );
}

async function requestOnboardNonceCount(
  relayUrl: string,
  challengeHex32?: string
): Promise<number> {
  const group = await readJson<{
    members: Array<{ idx: number; pubkey: string }>;
  }>(path.join(DEMO_DIR, 'group.json'));
  const share = await readJson<{ idx: number; seckey: string }>(path.join(DEMO_DIR, 'share-bob.json'));
  const peerMember = group.members.find((member) => member.idx === 1);
  const selfMember = group.members.find((member) => member.idx === share.idx);
  if (!peerMember || !selfMember) {
    throw new Error('demo group is missing required members');
  }

  const now = Math.floor(Date.now() / 1000);
  const requestId = `${now}-${share.idx}-${Date.now()}-${Math.floor(Math.random() * 1_000_000_000)}`;
  const conversationKey = nip44.v2.utils.getConversationKey(
    hexToBytes(share.seckey),
    peerMember.pubkey.toLowerCase().slice(2)
  );

  const pool = new SimplePool();
  const filter = {
    kinds: [BIFROST_EVENT_KIND],
    authors: [peerMember.pubkey.toLowerCase().slice(2)],
    '#p': [selfMember.pubkey.toLowerCase().slice(2)],
    since: now - 5
  } as Filter;

  try {
    logE2E('chrome.live-signer', 'manual-onboard:start', {
      relayUrl,
      requestId,
      shareIdx: share.idx,
      challengeHex32: challengeHex32 ?? null
    });
    return await new Promise<number>((resolve, reject) => {
      let settled = false;
      const timeout = setTimeout(() => {
        finish(() => {
          subscription.close('timeout');
          reject(
            new Error(
              `Timed out waiting for OnboardResponse for request ${requestId}${challengeHex32 ? ` (challenge=${challengeHex32})` : ''}`
            )
          );
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

      const event = finalizeEvent(
        {
          kind: BIFROST_EVENT_KIND,
          tags: [['p', peerMember.pubkey.toLowerCase().slice(2)]],
          content: normalizeNip44PayloadForRust(
            nip44.v2.encrypt(
              JSON.stringify({
                request_id: requestId,
                sent_at: now,
                payload: {
                  type: 'OnboardRequest',
                  data: {
                    share_pk: selfMember.pubkey.toLowerCase().slice(2),
                    idx: share.idx,
                    ...(challengeHex32 ? { challenge: challengeHex32 } : {})
                  }
                }
              }),
              conversationKey
            )
          ),
          created_at: now
        },
        hexToBytes(share.seckey)
      );

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

function waitForProcessExit(child: ChildProcess, timeoutMs = 5_000) {
  return new Promise<void>((resolve) => {
    const timer = setTimeout(() => {
      if (!child.killed) child.kill('SIGKILL');
      resolve();
    }, timeoutMs);

    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function randomPort() {
  return 18_000 + Math.floor(Math.random() * 10_000);
}

export async function startLiveSignerFixture(): Promise<LiveSignerFixture> {
  const port = randomPort();
  const relay = new LocalNostrRelay(port);
  await withLoggedStep('chrome.live-signer', 'start-relay', { port }, async () => {
    await relay.start();
  });

  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-live-'));
  const configPath = await withLoggedStep(
    'chrome.live-signer',
    'copy-responder-config',
    { tempRoot, relayUrl: relay.url() },
    async () => await copyDemoResponderConfig(relay.url(), tempRoot)
  );
  const controlSocketPath = path.join(tempRoot, 'control.sock');
  const controlToken = bytesToHex(randomBytes(16));
  const binaryPath = await ensureBifrostBinary();
  const profile = await buildLiveProfile(relay.url(), configPath);

  const child = spawn(
    binaryPath,
    [
      ...(process.env.BIFROST_DEBUG === '1'
        ? ['--debug']
        : process.env.BIFROST_VERBOSE === '0'
          ? []
          : ['--verbose']),
      '--config',
      configPath,
      'listen',
      '--control-socket',
      controlSocketPath,
      '--control-token',
      controlToken
    ],
    {
      cwd: BIFROST_RS_DIR,
      env: {
        ...process.env,
        CARGO_TARGET_DIR: BIFROST_TARGET_DIR
      },
      stdio: ['ignore', 'pipe', 'pipe']
    }
  );

  child.stdout?.on('data', (chunk) => {
    for (const line of chunk.toString().split('\n')) {
      const trimmed = line.trim();
      if (trimmed) logE2E('chrome.live-signer.stdout', 'line', { line: trimmed });
    }
  });

  let stderr = '';
  child.stderr?.on('data', (chunk) => {
    const text = chunk.toString();
    stderr += text;
    for (const line of text.split('\n')) {
      const trimmed = line.trim();
      if (trimmed) logE2E('chrome.live-signer.stderr', 'line', { line: trimmed });
    }
  });

  try {
    await withLoggedStep(
      'chrome.live-signer',
      'wait-control-ready',
      { controlSocketPath },
      async () => await waitForControlReady(controlSocketPath, controlToken, 20_000)
    );
  } catch (error) {
    child.kill('SIGINT');
    await waitForProcessExit(child);
    await relay.stop();
    await rm(tempRoot, { recursive: true, force: true });
    const detail = stderr.trim();
    throw new Error(
      `Failed to start live signer responder: ${error instanceof Error ? error.message : String(error)}${detail ? `\n${detail}` : ''}`
    );
  }

  return {
    relayUrl: relay.url(),
    profile,
    requestOnboardNonceCount: async () =>
      await requestOnboardNonceCount(relay.url(), profile.inviteChallengeHex32),
    stopRelay: async () => {
      await relay.stop();
    },
    stopResponder: async () => {
      if (!child.killed && child.exitCode === null) {
        child.kill('SIGINT');
      }
      await waitForProcessExit(child);
    },
    close: async () => {
      if (!child.killed && child.exitCode === null) {
        child.kill('SIGINT');
      }
      await waitForProcessExit(child);
      await relay.stop();
      await rm(tempRoot, { recursive: true, force: true });
    }
  };
}
