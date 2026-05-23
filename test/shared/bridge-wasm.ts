import {
  readTestBrowserWasmFile,
  testBrowserWasmLoaderUrl,
} from './browser-wasm-paths';

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
    const loaderUrl = testBrowserWasmLoaderUrl('bifrost_bridge_wasm.js');
    const wasmBytes = await readTestBrowserWasmFile('bifrost_bridge_wasm_bg.wasm');
    const imported = (await import(loaderUrl)) as BridgeWasmNodeModule;
    await imported.default({
      module_or_path: wasmBytes,
    });
    return imported;
  })();

  return await bridgeWasmModulePromise;
}
