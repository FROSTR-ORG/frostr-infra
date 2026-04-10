import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

import { IGLOO_CHROME_DIR } from './repo-paths';

type ProfileWasmNodeModule = {
  default: (options?: {
    module_or_path?: string | URL | ArrayBuffer | ArrayBufferView;
  }) => Promise<unknown>;
  bf_package_version: () => number;
  bfshare_prefix: () => string;
  bfonboard_prefix: () => string;
  bfprofile_prefix: () => string;
  profile_backup_event_kind: () => number;
  profile_backup_key_domain: () => string;
  encode_bfshare_package: (payloadJson: string, password: string) => string;
  decode_bfshare_package: (packageText: string, password: string) => string;
  encode_bfonboard_package: (payloadJson: string, password: string) => string;
  decode_bfonboard_package: (packageText: string, password: string) => string;
  derive_profile_id_from_share_secret: (shareSecret: string) => string;
  derive_profile_id_from_share_pubkey: (sharePubkey: string) => string;
  encode_bfprofile_package: (payloadJson: string, password: string) => string;
  decode_bfprofile_package: (packageText: string, password: string) => string;
  create_profile_package_pair: (payloadJson: string, password: string) => string;
  create_encrypted_profile_backup: (profileJson: string) => string;
  derive_profile_backup_conversation_key_hex: (shareSecret: string) => string;
  encrypt_profile_backup_content: (backupJson: string, shareSecret: string) => string;
  decrypt_profile_backup_content: (ciphertext: string, shareSecret: string) => string;
  build_profile_backup_event: (
    shareSecret: string,
    backupJson: string,
    createdAtSeconds?: number | null,
  ) => string;
  parse_profile_backup_event: (eventJson: string, shareSecret: string) => string;
  recover_profile_from_share_and_backup: (shareJson: string, backupJson: string) => string;
};

let profileWasmModulePromise: Promise<ProfileWasmNodeModule> | null = null;

export async function loadProfileWasmModule() {
  if (profileWasmModulePromise) {
    return await profileWasmModulePromise;
  }

  profileWasmModulePromise = (async () => {
    const loaderUrl = pathToFileURL(
      path.join(IGLOO_CHROME_DIR, 'public', 'wasm', 'bifrost_profile_wasm.js'),
    ).href;
    const wasmBytes = await readFile(
      path.join(IGLOO_CHROME_DIR, 'public', 'wasm', 'bifrost_profile_wasm_bg.wasm'),
    );
    const imported = (await import(loaderUrl)) as ProfileWasmNodeModule;
    await imported.default({
      module_or_path: wasmBytes,
    });
    return imported;
  })();

  return await profileWasmModulePromise;
}
