import net from 'node:net';

/**
 * Allocate a free TCP port by binding to port 0 (the OS assigns a free one), then
 * releasing it. The single source of truth for test port allocation — replaces the
 * ad-hoc random-range pickers that overlapped across local-relay (24k–44k), the
 * chrome live-signer (18k–28k), and the demo harness (43k+pid) and collided under
 * parallel load. There is a small TOCTOU window between release and the caller's
 * re-bind; callers bind promptly.
 */
export async function allocatePort(host = '127.0.0.1'): Promise<number> {
  return await new Promise<number>((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, host, () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close(() => reject(new Error('failed to allocate a test port')));
        return;
      }
      const { port } = address;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}
