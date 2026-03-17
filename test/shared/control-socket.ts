import net from 'node:net';
import { randomBytes } from 'node:crypto';

export type ControlResponse = {
  ok: boolean;
  error?: string;
  result?: unknown;
};

export async function waitForControlReady(socketPath: string, token: string, timeoutMs: number) {
  const deadline = Date.now() + timeoutMs;
  let lastError = 'unknown';

  while (Date.now() < deadline) {
    try {
      const response = await requestControl(socketPath, {
        request_id: randomBytes(8).toString('hex'),
        token,
        command: 'status',
      });
      if (response.ok) return;
      lastError = response.error ?? 'status not ok';
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }

  throw new Error(`Timed out waiting for control socket: ${lastError}`);
}

export function requestControl(
  socketPath: string,
  request: Record<string, unknown>,
): Promise<ControlResponse> {
  return new Promise<ControlResponse>((resolve, reject) => {
    const client = net.createConnection(socketPath);
    const chunks: Buffer[] = [];

    client.once('error', reject);
    client.on('data', chunk => {
      chunks.push(chunk);
    });
    client.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')) as ControlResponse);
      } catch (error) {
        reject(error);
      }
    });
    client.on('connect', () => {
      client.end(JSON.stringify(request));
    });
  });
}
