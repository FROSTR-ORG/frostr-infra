import net from 'node:net';
import { spawn } from 'node:child_process';

import { ensureBifrostDevtoolsBinary } from './bifrost-devtools-binaries';
import { BIFROST_RS_DIR } from './repo-paths';
import { allocatePort } from './port-allocation';
import { closeChild } from './process-lifecycle';
import { registerProcess, unregisterProcess } from './process-registry';

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

export async function startLocalRelay(port?: number): Promise<LocalRelayHandle> {
  const resolvedPort = port ?? (await allocatePort());
  const relayBinary = ensureBifrostDevtoolsBinary();
  const child = spawn(relayBinary, ['relay', '--host', '127.0.0.1', '--port', String(resolvedPort)], {
    cwd: BIFROST_RS_DIR,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  registerProcess(child.pid);

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
    await waitForRelayPort('127.0.0.1', resolvedPort, 10_000);
  } catch (error) {
    child.kill('SIGKILL');
    unregisterProcess(child.pid);
    throw new Error(
      `Failed to start local relay on ${resolvedPort}: ${error instanceof Error ? error.message : String(error)} | ${output.join(' | ')}`
    );
  }

  return {
    url: `ws://127.0.0.1:${resolvedPort}`,
    async close() {
      await closeChild(child);
      unregisterProcess(child.pid);
    },
  };
}
