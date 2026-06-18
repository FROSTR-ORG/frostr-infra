import path from 'node:path';

import { IGLOO_CHROME_DIST_DIR } from '../shared/repo-paths';
import { runTestPrebuild, targetsForClient } from '../shared/test-prebuild';
import { assertWasmProvenance } from '../shared/wasm-provenance';

export default async function globalSetup() {
  runTestPrebuild(targetsForClient('chrome'));
  // Fail fast if the built extension's WASM is not byte-identical to the WASM the
  // test process encrypts/signs with — otherwise a skew surfaces later as a
  // cryptic decryption failure. See ADR-013 (WASM provenance).
  await assertWasmProvenance({
    appWasmDir: path.join(IGLOO_CHROME_DIST_DIR, 'wasm'),
    label: 'igloo-chrome dist',
  });
}
