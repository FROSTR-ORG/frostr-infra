import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

import { IGLOO_CHROME_DIR } from './repo-paths';

type BridgeWasmNodeModule = {
  default: (options?: {
    module_or_path?: string | URL | ArrayBuffer | ArrayBufferView;
  }) => Promise<unknown>;
  create_onboarding_request_bundle: (
    shareSecret: string,
    peerPubkey32Hex: string,
    eventKind: bigint,
    sentAtSeconds?: number | null,
  ) => string;
};

let bridgeWasmModulePromise: Promise<BridgeWasmNodeModule> | null = null;

export async function loadBridgeWasmModule() {
  if (bridgeWasmModulePromise) {
    return await bridgeWasmModulePromise;
  }

  bridgeWasmModulePromise = (async () => {
    const loaderUrl = pathToFileURL(
      path.join(IGLOO_CHROME_DIR, 'public', 'wasm', 'bifrost_bridge_wasm.js'),
    ).href;
    const wasmBytes = await readFile(
      path.join(IGLOO_CHROME_DIR, 'public', 'wasm', 'bifrost_bridge_wasm_bg.wasm'),
    );
    const imported = (await import(loaderUrl)) as BridgeWasmNodeModule;
    await imported.default({
      module_or_path: wasmBytes,
    });
    return imported;
  })();

  return await bridgeWasmModulePromise;
}
