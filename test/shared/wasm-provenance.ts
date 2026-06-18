import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { resolveTestBrowserWasmDir } from './browser-wasm-paths';

// The browser WASM artifacts the test process encrypts/signs with (via the
// injected module) must be byte-identical to the WASM an app build under test
// loads — otherwise the app's SHA-384 loader rejects the mismatched binary and it
// surfaces deep inside a spec as a cryptic "Incorrect password" /
// wasm_integrity_check_failed. The skew is intermittent: it appears when a
// prebuild refreshes one client's scratch WASM but not another's (the
// chrome-target prebuild refreshes shared+chrome but not igloo-pwa), and
// prepare-browser-wasm builds one shared WASM then copies it per client. This
// asserts provenance up front, with an actionable message. See ADR-013 (WASM
// provenance) and dev/BACKLOG.md (P0 #4).

const WASM_BINARIES = ['bifrost_profile_wasm_bg.wasm', 'bifrost_bridge_wasm_bg.wasm'];

async function sha384(filePath: string): Promise<string> {
  const bytes = await readFile(filePath);
  return `sha384-${createHash('sha384').update(bytes).digest('base64')}`;
}

/**
 * Throw (fail fast) unless every browser WASM binary the `appWasmDir` build will
 * load is byte-identical to the test-injected WASM (`resolveTestBrowserWasmDir`).
 * `label` names the app build in the error (e.g. "igloo-chrome dist").
 */
export async function assertWasmProvenance(input: {
  appWasmDir: string;
  label: string;
}): Promise<void> {
  const testDir = resolveTestBrowserWasmDir();
  for (const file of WASM_BINARIES) {
    const testPath = path.join(testDir, file);
    const appPath = path.join(input.appWasmDir, file);

    let testHash: string;
    try {
      testHash = await sha384(testPath);
    } catch {
      throw new Error(
        `WASM provenance: missing test-injected artifact ${testPath} — run the client prebuild (make test-prep) first.`,
      );
    }

    let appHash: string;
    try {
      appHash = await sha384(appPath);
    } catch {
      throw new Error(
        `WASM provenance: missing ${input.label} artifact ${appPath} — was the build produced before the test ran?`,
      );
    }

    if (testHash !== appHash) {
      throw new Error(
        [
          `WASM provenance mismatch for ${file}:`,
          `  test-injected (${testDir}): ${testHash}`,
          `  ${input.label} (${input.appWasmDir}): ${appHash}`,
          'The build under test was produced from a different WASM than the test process',
          'encrypts with (an asymmetric prebuild left this client\'s WASM lagging). Rebuild it',
          `from the test WASM dir (set the client's IGLOO_*_WASM_SOURCE_DIR=${testDir}) or`,
          're-run the prebuild for this client. See ADR-013 (WASM provenance).',
        ].join('\n'),
      );
    }
  }
}
