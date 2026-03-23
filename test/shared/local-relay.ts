import net from 'node:net';
import { spawn, type ChildProcess } from 'node:child_process';

import { ensureBifrostDevtoolsBinary } from './bifrost-devtools-binaries';
import { BIFROST_RS_DIR } from './repo-paths';

function randomRelayPort() {
  return 24_000 + Math.floor(Math.random() * 20_000);
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
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for relay ${host}:${port}`);
}

export type LocalRelayHandle = {
  url: string;
  close: () => Promise<void>;
};

export async function startLocalRelay(port = randomRelayPort()): Promise<LocalRelayHandle> {
  const relayBinary = ensureBifrostDevtoolsBinary();
  const child = spawn(relayBinary, ['relay', '--host', '127.0.0.1', '--port', String(port)], {
    cwd: BIFROST_RS_DIR,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const output: string[] = [];
  const remember = (prefix: string) => (chunk: Buffer) => {
    output.push(`${prefix}${chunk.toString('utf8').trim()}`);
    if (output.length > 20) {
      output.splice(0, output.length - 20);
    }
  };
  child.stdout?.on('data', remember('stdout: '));
  child.stderr?.on('data', remember('stderr: '));

  try {
    await waitForRelayPort('127.0.0.1', port, 10_000);
  } catch (error) {
    child.kill('SIGKILL');
    throw new Error(
      `Failed to start local relay on ${port}: ${error instanceof Error ? error.message : String(error)} | ${output.join(' | ')}`
    );
  }

  return {
    url: `ws://127.0.0.1:${port}`,
    async close() {
      await new Promise<void>((resolve) => {
        const processRef = child as ChildProcess;
        if (processRef.exitCode !== null) {
          resolve();
          return;
        }
        const timeout = setTimeout(() => {
          processRef.kill('SIGKILL');
        }, 1_000);
        processRef.once('exit', () => {
          clearTimeout(timeout);
          resolve();
        });
        processRef.once('close', () => {
          clearTimeout(timeout);
          resolve();
        });
        processRef.kill('SIGTERM');
      });
    },
  };
}
