import { getPublicKey } from 'nostr-tools';
import { secp256k1 } from '@noble/curves/secp256k1.js';

import { assembleOnboardingPackage } from '../../shared/onboarding-package';
import type { GroupPackageWire, OnboardFixture } from './types';

function hexToBytes(value: string): Uint8Array {
  const clean = value.toLowerCase();
  if (clean.length % 2 !== 0) {
    throw new Error('hex string must have even length');
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function compressed33FromSecret(secretHex32: string): string {
  return bytesToHex(secp256k1.getPublicKey(hexToBytes(secretHex32), true)).toLowerCase();
}

const DEFAULT_ACTOR_SECRET = '11'.repeat(32);
const DEFAULT_SHARE_SECRET = '22'.repeat(32);

export function createOnboardFixture(params: {
  relayUrl: string;
  eventKind?: number;
  shareIdx?: number;
  actorSecretHex32?: string;
  shareSecretHex32?: string;
}): OnboardFixture {
  const eventKind = params.eventKind ?? 20_000;
  const shareIdx = params.shareIdx ?? 2;
  const actorSecretHex32 = (params.actorSecretHex32 ?? DEFAULT_ACTOR_SECRET).toLowerCase();
  const shareSecretHex32 = (params.shareSecretHex32 ?? DEFAULT_SHARE_SECRET).toLowerCase();

  const actorPubkeyXonly = getPublicKey(hexToBytes(actorSecretHex32)).toLowerCase();
  const sharePubkeyXonly = getPublicKey(hexToBytes(shareSecretHex32)).toLowerCase();
  const actorPubkey33 = compressed33FromSecret(actorSecretHex32);
  const sharePubkey33 = compressed33FromSecret(shareSecretHex32);

  const group: GroupPackageWire = {
    group_pk: actorPubkeyXonly,
    threshold: 2,
    members: [
      {
        idx: 1,
        pubkey: actorPubkey33
      },
      {
        idx: shareIdx,
        pubkey: sharePubkey33
      }
    ]
  };

  const assembled = assembleOnboardingPackage({
    shareIdx,
    shareSecretHex32,
    peerPubkey32: actorPubkeyXonly,
    relays: [params.relayUrl],
    password: 'playwright-password'
  });

  return {
    relayUrl: params.relayUrl,
    eventKind,
    onboardingPackage: assembled.onboardingPackage,
    onboardingPassword: assembled.onboardingPassword,
    actorSecretHex32,
    actorPubkeyXonly,
    actorPubkey33,
    shareSecretHex32,
    sharePubkeyXonly,
    sharePubkey33,
    shareIdx,
    group
  };
}
