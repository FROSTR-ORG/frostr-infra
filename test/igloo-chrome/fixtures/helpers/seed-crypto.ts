import { webcrypto } from 'node:crypto';

import type { LocalEncryptedProfileBlob, LocalProfileBlobPayload, LocalProfileBlobRecord } from '../../../../repos/igloo-chrome/src/lib/profile-blob';

const PASSWORD = 'playwright-passphrase';
const PBKDF2_ITERATIONS = 200_000;

function bytesToBase64(bytes: Uint8Array) {
  return Buffer.from(bytes).toString('base64');
}

async function deriveAesKey(password: string, salt: Uint8Array) {
  const baseKey = await webcrypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveKey']
  );
  return await webcrypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      hash: 'SHA-256',
      salt,
      iterations: PBKDF2_ITERATIONS,
    },
    baseKey,
    {
      name: 'AES-GCM',
      length: 256,
    },
    true,
    ['encrypt', 'decrypt']
  );
}

async function exportSessionKey(key: CryptoKey) {
  return bytesToBase64(new Uint8Array(await webcrypto.subtle.exportKey('raw', key)));
}

async function encryptPayload(
  payload: LocalProfileBlobPayload,
  password: string
): Promise<{ blob: LocalEncryptedProfileBlob; sessionKeyB64: string }> {
  const salt = webcrypto.getRandomValues(new Uint8Array(16));
  const iv = webcrypto.getRandomValues(new Uint8Array(12));
  const key = await deriveAesKey(password, salt);
  const ciphertext = await webcrypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv,
    },
    key,
    new TextEncoder().encode(JSON.stringify(payload))
  );
  return {
    blob: {
      version: 1,
      kdf: {
        saltB64: bytesToBase64(salt),
        iterations: PBKDF2_ITERATIONS,
        hash: 'SHA-256',
      },
      cipher: {
        ivB64: bytesToBase64(iv),
        ciphertextB64: bytesToBase64(new Uint8Array(ciphertext)),
      },
    },
    sessionKeyB64: await exportSessionKey(key),
  };
}

export async function createSeededProfileRecord(input: {
  profileId: string;
  label: string;
  payload: LocalProfileBlobPayload;
  now?: number;
}): Promise<{ storedBlobRecord: LocalProfileBlobRecord; sessionKeyB64: string }> {
  const now = input.now ?? Date.now();
  const encrypted = await encryptPayload(input.payload, PASSWORD);
  return {
    storedBlobRecord: {
      id: input.profileId,
      label: input.label,
      blob: encrypted.blob,
      createdAt: now,
      updatedAt: now,
    },
    sessionKeyB64: encrypted.sessionKeyB64,
  };
}
