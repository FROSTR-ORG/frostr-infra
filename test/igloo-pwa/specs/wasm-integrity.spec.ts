import { expect, test } from '@playwright/test';

// PR20 (remediation 2026-04-22): the generated `_loader.mjs` wrappers embed the
// SHA-384 of their `_bg.wasm` and refuse to instantiate a binary whose hash
// does not match. These tests exercise that wrapper directly (rather than
// driving the whole keyset UI) so the integrity contract is covered by a
// fast, deterministic regression test.
//
// The PWA configures the runtime to import these `_loader.mjs` wrappers (see
// `repos/igloo-pwa/src/lib/configure-igloo-shared.ts`), so this is the real
// code path a tampered deployment would hit.

const LOADERS = [
  {
    name: 'bridge',
    loader: '/wasm/bifrost_bridge_wasm_loader.mjs',
    binary: '/wasm/bifrost_bridge_wasm_bg.wasm',
  },
  {
    name: 'profile',
    loader: '/wasm/bifrost_profile_wasm_loader.mjs',
    binary: '/wasm/bifrost_profile_wasm_bg.wasm',
  },
] as const;

test.describe('wasm subresource integrity', () => {
  for (const { name, loader, binary } of LOADERS) {
    test(`${name} loader rejects a tampered _bg.wasm`, async ({ page }) => {
      // Flip a byte of the served wasm so its SHA-384 no longer matches the
      // value embedded in the loader at build time.
      await page.route(`**${binary}`, async (route) => {
        const response = await route.fetch();
        const body = await response.body();
        body[0] ^= 0xff;
        await route.fulfill({ response, body });
      });

      await page.goto('/');

      const result = await page.evaluate(
        async ({ loaderUrl, binaryUrl }) => {
          try {
            const mod = await import(/* @vite-ignore */ loaderUrl);
            await mod.default({
              module_or_path: new URL(binaryUrl, location.origin).toString(),
            });
            return 'loaded';
          } catch (error) {
            return error instanceof Error ? error.message : String(error);
          }
        },
        { loaderUrl: loader, binaryUrl: binary },
      );

      expect(result).toContain('wasm_integrity_check_failed');
    });

    test(`${name} loader accepts the untampered _bg.wasm`, async ({ page }) => {
      await page.goto('/');

      const result = await page.evaluate(
        async ({ loaderUrl }) => {
          try {
            const mod = await import(/* @vite-ignore */ loaderUrl);
            await mod.default();
            // The embedded __integrity export should be present and frozen.
            return typeof mod.__integrity?.wasmSha384 === 'string' ? 'loaded' : 'missing_integrity';
          } catch (error) {
            return error instanceof Error ? error.message : String(error);
          }
        },
        { loaderUrl: loader },
      );

      expect(result).toBe('loaded');
    });
  }
});
