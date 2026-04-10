import { getPublicKey } from 'nostr-tools';

import type { LocalProfileBlobPayload } from '../../../../repos/igloo-chrome/src/lib/profile-blob';
import type { SeedProfileOverrides } from '../types';
import { TEST_PROFILE } from '../constants';

const DEFAULT_SEED_LABEL = 'Playwright Smoke';
const FALLBACK_PROFILE_ID = '11'.repeat(32);
const FALLBACK_GROUP_PUBLIC_KEY = '33'.repeat(32);
const FALLBACK_SHARE_SECRET = '22'.repeat(32);

export const DEFAULT_SEED_SIGNER_SETTINGS = {
  sign_timeout_secs: 30,
  ping_timeout_secs: 15,
  request_ttl_secs: 300,
  state_save_interval_secs: 30,
  peer_selection_strategy: 'deterministic_sorted',
} as const;

export type GeneratedSeedProfile = {
  profileId: string;
  label: string;
  payload: LocalProfileBlobPayload;
};

export function buildSeedProfile(overrides: SeedProfileOverrides = {}): GeneratedSeedProfile {
  const profile = { ...TEST_PROFILE, ...overrides };
  const fallbackCompressedSharePubkey = `02${getPublicKey(Uint8Array.from(Buffer.from(FALLBACK_SHARE_SECRET, 'hex'))).toLowerCase()}`;
  const profileId =
    profile.profilePayload?.profileId ??
    profile.id ??
    profile.sharePublicKey ??
    profile.groupPublicKey ??
    profile.publicKey ??
    FALLBACK_PROFILE_ID;
  const label = profile.groupName?.trim() || DEFAULT_SEED_LABEL;
  const profilePayload =
    profile.profilePayload && typeof profile.profilePayload === 'object'
      ? profile.profilePayload
      : {
          profileId,
          version: 1 as const,
          device: {
            name: label,
            shareSecret: FALLBACK_SHARE_SECRET,
            manualPeerPolicyOverrides: [],
            relays: Array.isArray(profile.relays) ? profile.relays : [],
          },
          groupPackage: {
            groupName: label,
            groupPk: profile.groupPublicKey ?? profile.publicKey ?? FALLBACK_GROUP_PUBLIC_KEY,
            threshold: 1,
            members: [
              {
                idx: 1,
                pubkey: fallbackCompressedSharePubkey,
              },
            ],
          },
        };

  return {
    profileId,
    label,
    payload: {
      version: 1,
      profile: profilePayload,
      signerSettings: { ...DEFAULT_SEED_SIGNER_SETTINGS },
      runtimeSnapshotJson:
        typeof profile.runtimeSnapshotJson === 'string' ? profile.runtimeSnapshotJson : undefined,
      peerPubkey: profile.peerPubkey ?? undefined,
    },
  };
}
