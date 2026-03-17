import { SimplePool } from 'nostr-tools';

import { test, expect } from '../fixtures/extension';

const PROFILE_BACKUP_EVENT_KIND = 10_000;

test.describe('encrypted profile backup publish @live', () => {
  test.setTimeout(120_000);

  test('publishes the latest encrypted profile backup to the live relay', async ({
    liveSigner,
  }) => {
    const published = await liveSigner.publishBackup();

    expect(published.relays).toContain(liveSigner.relayUrl);
    expect(published.eventId).toMatch(/^[0-9a-f]{64}$/);
    expect(published.authorPubkey).toMatch(/^[0-9a-f]{64}$/);

    const pool = new SimplePool();
    try {
      const event = await pool.get(
        [liveSigner.relayUrl],
        {
          ids: [published.eventId],
        },
        { maxWait: 3_000 },
      );

      expect(event).not.toBeNull();
      expect(event?.id).toBe(published.eventId);
      expect(event?.kind).toBe(PROFILE_BACKUP_EVENT_KIND);
      expect(event?.pubkey).toBe(published.authorPubkey);
      expect(typeof event?.content).toBe('string');
      expect(event?.content.length).toBeGreaterThan(0);
    } finally {
      pool.close([liveSigner.relayUrl]);
      pool.destroy();
    }
  });
});
