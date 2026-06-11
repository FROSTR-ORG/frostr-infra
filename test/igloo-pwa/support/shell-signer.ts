import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';

import { IGLOO_SHELL_DIR } from '../../shared/repo-paths';
import { IGLOO_SHELL_TARGET_DIR, ensureIglooShellBinary } from '../../shared/igloo-shell-binaries';

// A headless igloo-shell co-signer that imports a bfprofile share into a
// throwaway store, runs its signer daemon, and INITIATES real threshold
// signatures over the control socket. The igloo-pwa runtime is responder-only,
// so something else has to start the sign — igloo-shell is the CI-friendly
// initiator (a headless Rust daemon, no desktop display, unlike igloo-home).
// Mirrors the chrome live-signer fixture, but as the initiator and driven
// entirely through the igloo-shell CLI (which owns the daemon lifecycle and
// control socket for us).

export type ShellSigner = {
  profileId: string;
  // Best-effort wait until the shell daemon reports it can sign. The PWA's own
  // expectPwaSignerSignReady is the authoritative mutual-readiness gate; this is
  // a secondary guard so the first sign attempt is less likely to race nonces.
  // Wait until the daemon has restored and is serving (does NOT require a peer);
  // gate the PWA onboard on this so the handshake can't race an unsubscribed shell.
  waitConnected(timeoutMs?: number): Promise<void>;
  signReady(timeoutMs?: number): Promise<void>;
  // The shell daemon's current runtime status (peers/readiness) — for diagnostics.
  status(): unknown;
  // Drive a real threshold sign over a 32-byte (64-hex) message; returns the
  // SignPayload.signatures_hex aggregate signature(s). Retries a few times to
  // absorb transient nonce-availability races.
  requestSign(messageHex32: string, attempts?: number): Promise<string[]>;
  close(): Promise<void>;
};

// The local passphrase that encrypts the imported share in the throwaway store.
const SHELL_LOCAL_PASSPHRASE = 'playwright-shell-passphrase';

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function shellEnv(root: string): NodeJS.ProcessEnv {
  const xdgRoot = path.join(root, 'xdg');
  return {
    ...process.env,
    CARGO_TARGET_DIR: IGLOO_SHELL_TARGET_DIR,
    XDG_CONFIG_HOME: path.join(xdgRoot, 'config'),
    XDG_DATA_HOME: path.join(xdgRoot, 'data'),
    XDG_STATE_HOME: path.join(xdgRoot, 'state'),
    // The XDG_STATE_HOME daemon socket path blows past the 104-byte sun_path
    // limit on macOS; the daemon falls back to $XDG_RUNTIME_DIR/<hash>.sock when
    // that dir exists. `root` is a short mkdtemp dir, keeping the socket in
    // range. (Same rationale as the chrome live-signer fixture.)
    XDG_RUNTIME_DIR: root,
  };
}

function runShellJson(binary: string, args: string[], env: NodeJS.ProcessEnv): unknown {
  const raw = execFileSync(binary, args, { cwd: IGLOO_SHELL_DIR, encoding: 'utf8', env }).trim();
  return raw ? JSON.parse(raw) : null;
}

// The import JSON nests the created profile under `import.profile.id`; fall back
// to a couple of shapes defensively.
function extractProfileId(value: unknown): string | null {
  const record = (value ?? null) as Record<string, unknown> | null;
  const candidates = [
    (record?.import as Record<string, unknown> | undefined)?.profile,
    record?.profile,
  ];
  for (const candidate of candidates) {
    const id = (candidate as Record<string, unknown> | undefined)?.id;
    if (typeof id === 'string' && id) return id;
  }
  return null;
}

// The runtime-status JSON shape varies; resiliently detect a sign-ready snapshot
// without over-fitting to exact field nesting.
function looksSignReady(status: unknown): boolean {
  return JSON.stringify(status ?? {}).includes('"sign_ready":true');
}

export async function startShellSigner(input: {
  bfprofile: string;
  packageSecret: string;
  relayUrl: string;
  label?: string;
}): Promise<ShellSigner> {
  const binary = ensureIglooShellBinary();
  const root = await mkdtemp(path.join(os.tmpdir(), 'igloo-pwa-shell-signer-'));
  const env = shellEnv(root);

  // For a bfprofile import, igloo-shell honors --relay-profile but ignores bare
  // --relay (see igloo-shell imports.rs), so register the relay as a named profile
  // first and import against it — the proven chrome-fixture pattern.
  runShellJson(binary, ['relays', 'set', 'local', input.relayUrl], env);
  const importResult = runShellJson(
    binary,
    [
      'import',
      input.bfprofile,
      '--package-secret',
      input.packageSecret,
      '--passphrase',
      SHELL_LOCAL_PASSPHRASE,
      '--relay-profile',
      'local',
      '--label',
      input.label ?? 'Shell Signer',
      '--json',
    ],
    env,
  );
  const profileId = extractProfileId(importResult);
  if (!profileId) {
    throw new Error(`igloo-shell import did not return a profile id: ${JSON.stringify(importResult)}`);
  }

  runShellJson(binary, ['daemon', 'start', '--profile', profileId, '--passphrase', SHELL_LOCAL_PASSPHRASE], env);

  return {
    profileId,
    status() {
      try {
        return runShellJson(binary, ['runtime', 'status', '--profile', profileId], env);
      } catch (error) {
        return { error: error instanceof Error ? error.message : String(error) };
      }
    },
    async waitConnected(timeoutMs = 15_000) {
      const deadline = Date.now() + timeoutMs;
      let last: unknown = null;
      while (Date.now() < deadline) {
        try {
          last = runShellJson(binary, ['runtime', 'status', '--profile', profileId], env);
          if (JSON.stringify(last ?? {}).includes('"restore_complete":true')) return;
        } catch (error) {
          last = error instanceof Error ? error.message : String(error);
        }
        await delay(300);
      }
      throw new Error(`igloo-shell daemon never finished restoring: ${JSON.stringify(last, null, 2)}`);
    },
    async signReady(timeoutMs = 30_000) {
      const deadline = Date.now() + timeoutMs;
      let last: unknown = null;
      while (Date.now() < deadline) {
        try {
          last = runShellJson(binary, ['runtime', 'status', '--profile', profileId], env);
          if (looksSignReady(last)) return;
        } catch (error) {
          last = error instanceof Error ? error.message : String(error);
        }
        await delay(500);
      }
      throw new Error(`igloo-shell never became sign-ready: ${JSON.stringify(last, null, 2)}`);
    },
    async requestSign(messageHex32, attempts = 5) {
      let lastError: unknown = null;
      for (let attempt = 0; attempt < attempts; attempt += 1) {
        try {
          const result = runShellJson(binary, ['runtime', 'sign', '--profile', profileId, messageHex32], env) as {
            signatures_hex?: string[];
          } | null;
          const signatures = result?.signatures_hex ?? [];
          if (signatures.length > 0) return signatures;
          lastError = new Error(`sign returned no signatures: ${JSON.stringify(result)}`);
        } catch (error) {
          lastError = error;
        }
        await delay(1_000);
      }
      throw new Error(
        `igloo-shell runtime sign failed after ${attempts} attempts: ${lastError instanceof Error ? lastError.message : String(lastError)}`,
      );
    },
    async close() {
      try {
        runShellJson(binary, ['daemon', 'stop', '--profile', profileId], env);
      } catch {
        // best effort — the daemon is in a throwaway store and the process exits with the test
      }
      await rm(root, { recursive: true, force: true }).catch(() => undefined);
    },
  };
}
