import { getPublicKey, nip19 } from 'nostr-tools';

// Local hex→bytes (mirrors test/shared/browser-artifacts.ts) to avoid depending on
// a @noble/curves subpath export that isn't published in this workspace version.
function hexToBytes(hex: string): Uint8Array {
  const normalized = hex.trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(normalized)) {
    throw new Error('Invalid hex string.');
  }
  const bytes = new Uint8Array(normalized.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(normalized.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

// Deterministic key vectors for byte-stable visual captures and exact-assertion
// functional tests. Live keygen (createGeneratedBrowserArtifacts) is random and
// unfit for screenshots, so we pin a few fixed 32-byte secrets and DERIVE their
// real x-only public keys + npub at module load using the same nostr-tools the
// app uses. This guarantees valid secp256k1 points and correct npub encodings
// (not arbitrary '22'×32 bytes, which need not be valid points).

export type DeterministicKey = {
  /** Fixed 32-byte secret (hex). */
  secretHex: string;
  /** Derived x-only public key (hex). */
  pubHex: string;
  /** Derived npub (bech32). */
  npub: string;
};

function deriveKey(secretHex: string): DeterministicKey {
  const pubHex = getPublicKey(hexToBytes(secretHex));
  return { secretHex, pubHex, npub: nip19.npubEncode(pubHex) };
}

// Pinned secrets — stable across runs, chosen only for determinism.
export const DETERMINISTIC_GROUP_KEY = deriveKey(
  '1111111111111111111111111111111111111111111111111111111111111111',
);
export const DETERMINISTIC_SHARE_KEY = deriveKey(
  '2222222222222222222222222222222222222222222222222222222222222222',
);

/** Truncated npub display matching the dashboard's `toDashboardKey` format. */
export function npubDisplay(npub: string): string {
  return `${npub.slice(0, 8)}...${npub.slice(-4)}`;
}
