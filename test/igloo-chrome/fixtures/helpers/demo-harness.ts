import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import net from 'node:net';
import { lstat, mkdtemp, readFile, rm, stat } from 'node:fs/promises';

import { logE2E, withLoggedStep } from '../../../shared/observability';
import { REPO_ROOT_DIR } from '../../../shared/repo-paths';
import type { DemoHarnessFixture } from '../types';

const DEMO_SCRIPT = path.join(REPO_ROOT_DIR, 'scripts', 'demo.sh');
const DEMO_RELAY_HOST = process.env.DEV_RELAY_EXTERNAL_HOST ?? 'localhost';
const DEMO_RELAY_PORT = Number(
  process.env.IGLOO_DEMO_RELAY_PORT ?? String(43000 + (process.pid % 1000))
);

async function waitForHarnessArtifact(filePath: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const info = await stat(filePath);
      if (info.size > 0) {
        return await readFile(filePath, 'utf8');
      }
    } catch {
      // Keep polling until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for harness artifact ${filePath}`);
}

async function waitForHarnessSocket(socketPath: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const info = await lstat(socketPath);
      if (info.isSocket() || info.isSymbolicLink()) {
        return;
      }
      return;
    } catch {
      // Keep polling until timeout.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for harness socket ${socketPath}`);
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
    if (ready) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for relay ${host}:${port}`);
}

function readHarnessLogs(projectName: string, env: NodeJS.ProcessEnv) {
  try {
    return execFileSync(
      'docker',
      ['compose', '-p', projectName, '-f', 'compose.test.yml', 'logs', '--tail=200', 'dev-relay', 'igloo-demo'],
      {
        cwd: REPO_ROOT_DIR,
        encoding: 'utf8',
        env,
      }
    );
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

function readHarnessStatus(projectName: string, env: NodeJS.ProcessEnv) {
  try {
    return execFileSync(
      'docker',
      ['compose', '-p', projectName, '-f', 'compose.test.yml', 'ps', 'dev-relay', 'igloo-demo'],
      {
        cwd: REPO_ROOT_DIR,
        encoding: 'utf8',
        env,
      }
    );
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

function readComposeServiceId(projectName: string, env: NodeJS.ProcessEnv, service: string) {
  try {
    return execFileSync(
      'docker',
      ['compose', '-p', projectName, '-f', 'compose.test.yml', 'ps', '-q', service],
      {
        cwd: REPO_ROOT_DIR,
        encoding: 'utf8',
        env,
      }
    ).trim();
  } catch {
    return '';
  }
}

function readContainerHealth(containerId: string, env: NodeJS.ProcessEnv) {
  if (!containerId) return '';
  try {
    return execFileSync(
      'docker',
      [
        'inspect',
        '--format',
        '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}',
        containerId,
      ],
      {
        cwd: REPO_ROOT_DIR,
        encoding: 'utf8',
        env,
      }
    ).trim();
  } catch {
    return '';
  }
}

function execCompose(projectName: string, env: NodeJS.ProcessEnv, args: string[]) {
  execFileSync('docker', ['compose', '-p', projectName, '-f', 'compose.test.yml', ...args], {
    cwd: REPO_ROOT_DIR,
    stdio: 'inherit',
    env,
  });
}

async function waitForComposeServiceHealthy(
  projectName: string,
  env: NodeJS.ProcessEnv,
  service: string,
  timeoutMs: number
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const containerId = readComposeServiceId(projectName, env, service);
    const health = readContainerHealth(containerId, env);
    if (health === 'healthy') {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${service} to become healthy.`);
}

function composeFailureDetails(projectName: string, env: NodeJS.ProcessEnv) {
  return [
    '==> compose status',
    readHarnessStatus(projectName, env),
    '==> compose logs',
    readHarnessLogs(projectName, env),
  ].join('\n');
}

async function composeUpRelayWithRetry(projectName: string, env: NodeJS.ProcessEnv, relayUrl: string) {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      execCompose(projectName, env, ['up', '-d', '--build', 'dev-relay']);
      return;
    } catch (error) {
      lastError = error;
      const detail = composeFailureDetails(projectName, env);
      logE2E('chrome.demo-harness', 'compose-up-relay-failed', {
        relayUrl,
        attempt,
        error_message: error instanceof Error ? error.message : String(error),
        detail,
      });
      try {
        execFileSync('docker', ['compose', '-p', projectName, '-f', 'compose.test.yml', 'down', '-v'], {
          cwd: REPO_ROOT_DIR,
          stdio: 'inherit',
          env,
        });
      } catch {
        // Best-effort cleanup before retry/final failure.
      }
      if (attempt === 2) {
        throw new Error(
          `Relay compose up failed after ${attempt} attempts: ${
            error instanceof Error ? error.message : String(error)
          }\n${detail}`
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError));
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
        }
      );
    } catch {
      // Best-effort only.
    }
    await rm(dir, { recursive: true, force: true }).catch(() => undefined);
  }
}

export async function startDemoHarnessFixture(): Promise<DemoHarnessFixture> {
  const projectName = `igloo-chrome-${process.pid}-${randomBytes(4).toString('hex')}`;
  const hostArtifactDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-chrome-demo-'));
  const demoMember = process.env.IGLOO_SHELL_DEMO_MEMBER ?? 'alice';
  const inviteMembers = process.env.IGLOO_SHELL_DEMO_INVITE_MEMBERS ?? 'bob,carol';
  const containerArtifactDir = `/workspace/.tmp/test-harness/${projectName}`;
  const relayPortNumber = DEMO_RELAY_PORT;
  const relayHost = DEMO_RELAY_HOST;
  const relayPort = String(relayPortNumber);
  const relayUrl = `ws://${relayHost}:${relayPort}`;
  const recipient = process.env.IGLOO_SHELL_DEMO_E2E_MEMBER ?? 'bob';
  const composeEnv = {
    ...process.env,
    DEV_RELAY_PORT: relayPort,
    DEV_RELAY_EXTERNAL_HOST: relayHost,
    FROSTR_TEST_HARNESS_DIR: hostArtifactDir,
    FROSTR_TEST_HARNESS_CONTAINER_DIR: containerArtifactDir,
    IGLOO_TRACE: process.env.IGLOO_TRACE ?? '',
    IGLOO_TRACE_LEVEL: process.env.IGLOO_TRACE_LEVEL ?? '',
    IGLOO_SHELL_DEMO_MEMBER: demoMember,
    IGLOO_SHELL_DEMO_INVITE_MEMBERS: inviteMembers,
    IGLOO_SHELL_DEMO_ARTIFACT_DIR: containerArtifactDir,
    IGLOO_SHELL_DEMO_DIR: `${containerArtifactDir}/demo-2of3`,
    IGLOO_SHELL_DEMO_CONTROL_SOCKET: `${containerArtifactDir}/igloo-shell-${demoMember}.sock`,
    IGLOO_SHELL_DEMO_CONTROL_TOKEN_FILE: `${containerArtifactDir}/igloo-shell-${demoMember}.token`,
  };
  const packagePath = path.join(hostArtifactDir, `onboard-${recipient}.txt`);
  const passwordPath = path.join(hostArtifactDir, `onboard-${recipient}.password.txt`);
  const socketPath = path.join(hostArtifactDir, `igloo-shell-${demoMember}.sock`);

  const cleanup = async () => {
    await withLoggedStep('chrome.demo-harness', 'compose-down', { projectName }, async () => {
      try {
        execFileSync('docker', ['compose', '-p', projectName, '-f', 'compose.test.yml', 'down', '-v'], {
          cwd: REPO_ROOT_DIR,
          stdio: 'inherit',
          env: composeEnv,
        });
      } catch {
        // Best-effort cleanup only.
      }
    });
    await cleanupArtifactDir(hostArtifactDir);
  };

  await withLoggedStep('chrome.demo-harness', 'build-binaries', undefined, async () => {
    execFileSync(DEMO_SCRIPT, ['build-binaries'], {
      cwd: REPO_ROOT_DIR,
      stdio: 'inherit',
    });
  });

  await withLoggedStep('chrome.demo-harness', 'compose-up-relay', { relayUrl }, async () => {
    await composeUpRelayWithRetry(projectName, composeEnv, relayUrl);
  });

  try {
    await withLoggedStep('chrome.demo-harness', 'wait-relay-healthy', { relayUrl }, async () => {
      await waitForComposeServiceHealthy(projectName, composeEnv, 'dev-relay', 300_000);
    });
    await withLoggedStep('chrome.demo-harness', 'wait-relay-port', { relayUrl }, async () => {
      await waitForRelayPort(relayHost, relayPortNumber, 300_000);
    });
    await withLoggedStep('chrome.demo-harness', 'compose-up-demo', { recipient }, async () => {
      execCompose(projectName, composeEnv, ['up', '-d', '--build', '--no-deps', 'igloo-demo']);
    });
    const [onboardPackage, onboardPassword] = await Promise.all([
      withLoggedStep('chrome.demo-harness', 'wait-onboard-package', { packagePath, recipient }, async () =>
        await waitForHarnessArtifact(packagePath, 300_000)
      ),
      withLoggedStep('chrome.demo-harness', 'wait-onboard-password', { passwordPath, recipient }, async () =>
        await waitForHarnessArtifact(passwordPath, 300_000)
      ),
      withLoggedStep('chrome.demo-harness', 'wait-control-socket', { socketPath }, async () =>
        await waitForHarnessSocket(socketPath, 300_000)
      ),
    ]);

    logE2E('chrome.demo-harness', 'fixture-ready', {
      recipient,
      relayUrl,
      onboardLength: onboardPackage.trim().length,
    });

    return {
      relayUrl,
      recipient,
      onboardPackage: onboardPackage.trim(),
      onboardPassword: onboardPassword.trim(),
      cleanup,
    };
  } catch (error) {
    try {
      await cleanup();
    } catch {
      // Preserve the original startup error.
    }
    throw new Error(
      `Failed to start demo harness: ${
        error instanceof Error ? error.message : String(error)
      }\n${composeFailureDetails(projectName, composeEnv)}`
    );
  }
}
