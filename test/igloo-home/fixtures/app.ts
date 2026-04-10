import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawn, type ChildProcess } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';

import { IGLOO_HOME_DIR } from '../../shared/repo-paths';

type TestResponse<T = unknown> = {
  request_id: string;
  ok: boolean;
  result?: T;
  error?: string;
};

export type IglooHomeHarness = {
  appDataDir: string;
  port: number;
  request: <T = unknown>(command: string, input?: unknown) => Promise<T>;
  close: () => Promise<void>;
};

function nextPort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close(() => reject(new Error('failed to allocate igloo-home test server port')));
        return;
      }
      const { port } = address;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function waitForServer(port: number, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      await requestServer(port, 'health');
      return;
    } catch {
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
  throw new Error(`timed out waiting for igloo-home test server on ${port}`);
}

function requestServer<T>(port: number, command: string, input?: unknown): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const client = net.createConnection({ host: '127.0.0.1', port });
    const chunks: Buffer[] = [];
    client.once('error', reject);
    client.on('data', chunk => chunks.push(chunk));
    client.on('end', () => {
      try {
        const response = JSON.parse(Buffer.concat(chunks).toString('utf8')) as TestResponse<T>;
        if (!response.ok) {
          reject(new Error(response.error ?? `igloo-home ${command} failed`));
          return;
        }
        resolve(response.result as T);
      } catch (error) {
        reject(error);
      }
    });
    client.on('connect', () => {
      client.end(
        `${JSON.stringify({
          request_id: randomBytes(8).toString('hex'),
          command,
          input: input ?? null,
        })}\n`,
      );
    });
  });
}

function buildIglooHome() {
  execFileSync('npm', ['run', 'build'], {
    cwd: IGLOO_HOME_DIR,
    stdio: 'inherit',
  });
  execFileSync('cargo', ['build', '--manifest-path', 'src-tauri/Cargo.toml'], {
    cwd: IGLOO_HOME_DIR,
    stdio: 'inherit',
  });
}

function binaryPath() {
  return path.join(IGLOO_HOME_DIR, 'src-tauri', 'target', 'debug', 'igloo-home');
}

function shouldBuildIglooHome() {
  return process.env.IGLOO_HOME_TEST_SKIP_BUILD !== '1';
}

function resolvedBinaryPath() {
  return process.env.IGLOO_HOME_TEST_BINARY?.trim() || binaryPath();
}

export async function launchIglooHome(): Promise<IglooHomeHarness> {
  if (!process.env.DISPLAY && !process.env.WAYLAND_DISPLAY) {
    throw new Error('desktop tests require DISPLAY or WAYLAND_DISPLAY');
  }

  if (shouldBuildIglooHome()) {
    buildIglooHome();
  }
  const appDataDir = await mkdtemp(path.join(os.tmpdir(), 'igloo-home-test-'));
  const port = await nextPort();
  const child = spawn(resolvedBinaryPath(), [], {
    cwd: IGLOO_HOME_DIR,
    stdio: 'inherit',
    env: {
      ...process.env,
      IGLOO_HOME_TEST_MODE: '1',
      IGLOO_HOME_TEST_SHOW_WINDOW: '0',
      IGLOO_HOME_TEST_PORT: String(port),
      IGLOO_HOME_TEST_APP_DATA_DIR: appDataDir,
    },
  });

  try {
    await waitForServer(port, 30_000);
  } catch (error) {
    child.kill('SIGTERM');
    await rm(appDataDir, { recursive: true, force: true });
    throw error;
  }

  return {
    appDataDir,
    port,
    request: <T>(command: string, input?: unknown) => requestServer<T>(port, command, input),
    close: async () => {
      if (!child.killed) {
        child.kill('SIGTERM');
        await waitForExit(child);
      }
      await rm(appDataDir, { recursive: true, force: true });
    },
  };
}

function waitForExit(child: ChildProcess) {
  return new Promise<void>(resolve => {
    child.once('exit', () => resolve());
    setTimeout(() => resolve(), 5_000);
  });
}
