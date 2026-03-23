import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { access, lstat, mkdtemp, readFile, readlink, rm, stat } from 'node:fs/promises';

import { REPO_ROOT_DIR } from '../../shared/repo-paths';
import { requestControl, waitForControlReady, type ControlResponse } from '../../shared/control-socket';

type BobConfig = {
  relays: string[];
  peers: Array<{ pubkey: string }>;
};

type GroupPackage = {
  members: Array<{ idx: number; pubkey: string }>;
};

export type DemoHarness = {
  relayUrl: string;
  bobGroupJson: string;
  bobShareJson: string;
  bobPeerPubkeys: string[];
  bobPubkeyXOnly: string;
  onboardPackage: string;
  onboardPassword: string;
  aliceSocketPath: string;
  aliceToken: string;
  cleanup: () => Promise<void>;
};

export async function ensureDemoHarness(): Promise<DemoHarness> {
  const projectName = `igloo-home-${process.pid}-${randomBytes(4).toString('hex')}`;
  const relayPort = await allocatePort();
  const hostArtifactDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-home-demo-'));
  const demoMember = process.env.IGLOO_SHELL_DEMO_MEMBER ?? 'alice';
  const inviteMembers = process.env.IGLOO_SHELL_DEMO_INVITE_MEMBERS ?? 'bob,carol';
  const containerArtifactDir = `/workspace/test-harness/${projectName}`;
  const composeEnv = {
    ...process.env,
    DEV_RELAY_PORT: String(relayPort),
    DEV_RELAY_EXTERNAL_HOST: '127.0.0.1',
    IGLOO_TRACE: process.env.IGLOO_TRACE ?? '',
    IGLOO_TRACE_LEVEL: process.env.IGLOO_TRACE_LEVEL ?? '',
    IGLOO_SHELL_DEMO_MEMBER: demoMember,
    IGLOO_SHELL_DEMO_INVITE_MEMBERS: inviteMembers,
    IGLOO_SHELL_DEMO_HOST_ARTIFACT_DIR: hostArtifactDir,
    IGLOO_SHELL_DEMO_ARTIFACT_DIR: containerArtifactDir,
    IGLOO_SHELL_DEMO_DIR: `${containerArtifactDir}/demo-2of3`,
    IGLOO_SHELL_DEMO_CONTROL_SOCKET: `${containerArtifactDir}/igloo-shell-${demoMember}.sock`,
    IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE: `${containerArtifactDir}/igloo-shell-${demoMember}.token`,
  };

  const cleanup = async () => {
    try {
      execFileSync(
        'docker',
        ['compose', '-p', projectName, '-f', 'compose.test.yml', 'down', '-v'],
        {
          cwd: REPO_ROOT_DIR,
          stdio: 'inherit',
          env: composeEnv,
        },
      );
    } catch {
      // Preserve the primary test error if teardown fails.
    }
    await cleanupArtifactDir(hostArtifactDir);
  };

  try {
    execCompose(projectName, composeEnv, ['build', 'dev-relay', 'igloo-demo']);
    execCompose(projectName, composeEnv, ['up', '-d', 'dev-relay', 'igloo-demo']);

    const bobConfigPath = path.join(hostArtifactDir, 'demo-2of3', 'igloo-shell-bob.json');
    const groupPath = path.join(hostArtifactDir, 'demo-2of3', 'group.json');
    const bobSharePath = path.join(hostArtifactDir, 'demo-2of3', 'share-bob.json');
    const onboardPath = path.join(hostArtifactDir, 'onboard-bob.txt');
    const onboardPasswordPath = path.join(hostArtifactDir, 'onboard-bob.password.txt');
    const aliceSocketPath = path.join(hostArtifactDir, `igloo-shell-${demoMember}.sock`);
    const aliceTokenPath = path.join(hostArtifactDir, `igloo-shell-${demoMember}.token`);

    await waitForHarnessArtifacts([
      bobConfigPath,
      groupPath,
      bobSharePath,
      onboardPath,
      onboardPasswordPath,
      aliceTokenPath,
    ]);

    const [bobConfigRaw, groupRaw, bobShareJson, onboardPackage, onboardPassword, aliceToken] =
      await Promise.all([
        readFile(bobConfigPath, 'utf8'),
        readFile(groupPath, 'utf8'),
        readFile(bobSharePath, 'utf8'),
        readFile(onboardPath, 'utf8'),
        readFile(onboardPasswordPath, 'utf8'),
        readFile(aliceTokenPath, 'utf8'),
      ]);

    const bobConfig = JSON.parse(bobConfigRaw) as BobConfig;
    const group = JSON.parse(groupRaw) as GroupPackage;
    const bobMember = group.members.find(member => member.idx === 2);
    if (!bobMember) {
      throw new Error('demo group is missing Bob member');
    }

    const token = aliceToken.trim();
    await waitForControlReady(aliceSocketPath, token, 30_000);

    return {
      relayUrl: `ws://127.0.0.1:${relayPort}`,
      bobGroupJson: groupRaw,
      bobShareJson,
      bobPeerPubkeys: bobConfig.peers.map(peer => peer.pubkey),
      bobPubkeyXOnly: bobMember.pubkey.toLowerCase().slice(2),
      onboardPackage: onboardPackage.trim(),
      onboardPassword: onboardPassword.trim(),
      aliceSocketPath,
      aliceToken: token,
      cleanup,
    };
  } catch (error) {
    const diagnostics = await buildHarnessFailureDiagnostics(
      projectName,
      composeEnv,
      path.join(hostArtifactDir, `igloo-shell-${demoMember}.sock`),
    );
    await cleanup();
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`${message}\n\n${diagnostics}`);
  }
}

function execCompose(projectName: string, env: NodeJS.ProcessEnv, args: string[]) {
  execFileSync('docker', ['compose', '-p', projectName, '-f', 'compose.test.yml', ...args], {
    cwd: REPO_ROOT_DIR,
    stdio: 'inherit',
    env,
  });
}

async function allocatePort(): Promise<number> {
  return await new Promise<number>((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close(() => reject(new Error('failed to allocate relay port')));
        return;
      }
      const { port } = address;
      server.close(error => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function cleanupArtifactDir(dir: string) {
  try {
    await rm(dir, { recursive: true, force: true });
    return;
  } catch {
    try {
      execFileSync(
        'docker',
        [
          'run',
          '--rm',
          '-v',
          `${dir}:/target`,
          'ubuntu:24.04',
          'bash',
          '-lc',
          'chmod -R a+rwX /target || true; rm -rf /target/* /target/.[!.]* /target/..?* || true',
        ],
        {
          cwd: REPO_ROOT_DIR,
          stdio: 'ignore',
        },
      );
    } catch {
      // Best-effort only. The primary failure should still surface.
    }
    await rm(dir, { recursive: true, force: true }).catch(() => undefined);
  }
}

async function waitForHarnessArtifacts(paths: string[], timeoutMs = 60_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const results = await Promise.all(
      paths.map(async candidate => {
        try {
          await access(candidate);
          const info = await stat(candidate);
          if (info.size === 0) {
            return false;
          }
          if (candidate.endsWith('onboard-bob.txt')) {
            const value = (await readFile(candidate, 'utf8')).trim();
            return value.startsWith('bfonboard1') && value.length > 32;
          }
          if (candidate.endsWith('.token') || candidate.endsWith('.password.txt')) {
            const value = (await readFile(candidate, 'utf8')).trim();
            return value.length > 0;
          }
          return true;
        } catch {
          return false;
        }
      }),
    );
    if (results.every(Boolean)) {
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 250));
  }

  throw new Error(`timed out waiting for demo harness artifacts: ${paths.join(', ')}`);
}

async function buildHarnessFailureDiagnostics(
  projectName: string,
  env: NodeJS.ProcessEnv,
  socketPath: string,
) {
  const parts: string[] = [];
  parts.push(`project=${projectName}`);
  parts.push(`socket_path=${socketPath}`);
  try {
    const info = await lstat(socketPath);
    parts.push(`socket_lstat=${info.isSocket() ? 'socket' : info.isSymbolicLink() ? 'symlink' : 'other'}`);
    if (info.isSymbolicLink()) {
      const target = await readlink(socketPath);
      parts.push(`socket_symlink_target=${target}`);
    }
  } catch (error) {
    parts.push(`socket_lstat_error=${error instanceof Error ? error.message : String(error)}`);
  }

  try {
    const logs = execFileSync(
      'docker',
      ['compose', '-p', projectName, '-f', 'compose.test.yml', 'logs', '--tail=200', 'igloo-demo'],
      {
        cwd: REPO_ROOT_DIR,
        env,
        encoding: 'utf8',
      },
    );
    if (logs.trim().length > 0) {
      parts.push('igloo_demo_logs:');
      parts.push(logs.trim());
    }
  } catch (error) {
    parts.push(`compose_logs_error=${error instanceof Error ? error.message : String(error)}`);
  }

  return parts.join('\n');
}

export async function pingBob(harness: DemoHarness): Promise<ControlResponse> {
  return requestControl(harness.aliceSocketPath, {
    request_id: 'igloo-home-ping',
    token: harness.aliceToken,
    command: 'ping',
    peer: harness.bobPubkeyXOnly,
    timeout_secs: 20,
  });
}

type ReadinessResponse = {
  runtime?: string;
  readiness?: {
    runtime_ready?: boolean;
    restore_complete?: boolean;
    sign_ready?: boolean;
    ecdh_ready?: boolean;
    signing_peer_count?: number;
    ecdh_peer_count?: number;
    last_refresh_at?: number | null;
  } | null;
  runtime_ready?: boolean;
  restore_complete?: boolean;
  sign_ready?: boolean;
  ecdh_ready?: boolean;
  signing_peer_count?: number;
  ecdh_peer_count?: number;
  last_refresh_at?: number | null;
};

function extractReadiness(result: unknown) {
  const readiness = result as ReadinessResponse | undefined;
  if (!readiness) {
    return null;
  }
  return readiness.readiness ?? readiness;
}

export async function onboardBobFromAlice(harness: DemoHarness): Promise<ControlResponse> {
  return requestControl(harness.aliceSocketPath, {
    request_id: 'igloo-home-onboard',
    token: harness.aliceToken,
    command: 'onboard',
    peer: harness.bobPubkeyXOnly,
    timeout_secs: 20,
  });
}

export async function aliceReadiness(harness: DemoHarness): Promise<ControlResponse> {
  return requestControl(harness.aliceSocketPath, {
    request_id: `igloo-home-readiness-${Date.now()}`,
    token: harness.aliceToken,
    command: 'readiness',
  });
}

export async function aliceRuntimeDiagnostics(harness: DemoHarness): Promise<ControlResponse> {
  return requestControl(harness.aliceSocketPath, {
    request_id: `igloo-home-runtime-diagnostics-${Date.now()}`,
    token: harness.aliceToken,
    command: 'runtime_diagnostics',
  });
}

type DirectReadiness = {
    runtime_ready?: boolean;
    restore_complete?: boolean;
    sign_ready?: boolean;
    ecdh_ready?: boolean;
    signing_peer_count?: number;
    ecdh_peer_count?: number;
    last_refresh_at?: number | null;
};

export async function waitForAliceSignReady(
  harness: DemoHarness,
  timeoutMs = 30_000,
): Promise<ControlResponse> {
  const deadline = Date.now() + timeoutMs;
  let lastResult: unknown;

  while (Date.now() < deadline) {
    const response = await aliceReadiness(harness);
    lastResult = response.result;

    const readiness = extractReadiness(response.result) as DirectReadiness | null;
    if (
      response.ok &&
      readiness?.runtime_ready &&
      readiness.restore_complete &&
      readiness.sign_ready
    ) {
      return response;
    }

    await new Promise(resolve => setTimeout(resolve, 250));
  }

  throw new Error(
    `timed out waiting for alice sign readiness: ${JSON.stringify(lastResult, null, 2)}`,
  );
}

export async function signWithBob(harness: DemoHarness): Promise<ControlResponse> {
  await waitForAliceSignReady(harness);

  let lastResponse: ControlResponse = { ok: false, error: 'sign did not return a response' };
  for (let attempt = 0; attempt < 5; attempt += 1) {
    lastResponse = await requestControl(harness.aliceSocketPath, {
      request_id: `igloo-home-sign-${attempt + 1}`,
      token: harness.aliceToken,
      command: 'sign',
      message_hex32: '1111111111111111111111111111111111111111111111111111111111111111',
      timeout_secs: 20,
    });
    if (lastResponse.ok) {
      return lastResponse;
    }
    await new Promise(resolve => setTimeout(resolve, 1500));
  }
  return lastResponse;
}
