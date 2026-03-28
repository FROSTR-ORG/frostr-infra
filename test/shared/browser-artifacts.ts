import { getPublicKey } from 'nostr-tools';

import { loadBridgeWasmModule } from './bridge-wasm';
import {
  setInjectedWasmBridgeModuleForTests,
} from '../../repos/igloo-shared/src/bridge-wasm-runtime';
import {
  createEncryptedProfileBackup,
  createProfilePackagePair,
  deriveProfileIdFromShareSecret,
  encodeBfOnboardPackage,
  type BrowserOnboardPackagePayload,
  groupPublicKeyFromPackage,
  type BrowserGroupPackageMember,
  type BrowserProfilePackagePayload,
} from '../../repos/igloo-shared/src/profile-package';
import { publishEncryptedProfileBackup } from '../../repos/igloo-shared/src/profile-backup-host';

export const DEFAULT_BROWSER_PASSWORD = 'playwright-passphrase';

export type GeneratedBrowserShareArtifact = {
  memberIdx: number;
  shareSecret: string;
  sharePublicKey: string;
  sharePackageJson: string;
  profileId: string;
  profilePayload: BrowserProfilePackagePayload;
  bfprofile: string;
  bfshare: string;
};

export type GeneratedBrowserArtifacts = {
  groupName: string;
  threshold: number;
  count: number;
  groupPackageJson: string;
  groupPublicKey: string;
  shares: GeneratedBrowserShareArtifact[];
};

export type PwaStoredProfileSeed = {
  id: string;
  label: string;
  share_public_key: string;
  group_public_key: string;
  relays: string[];
  group_package_json: string;
  share_package_json: string;
  source: 'generated' | 'bfprofile' | 'bfshare' | 'bfonboard';
  relay_profile: string;
  group_ref: string;
  share_ref: string;
  state_path: string;
  created_at: number;
  stored_password: string;
  profile_string: string;
  share_string: string;
  signer_settings: {
    sign_timeout_secs: number;
    ping_timeout_secs: number;
    request_ttl_secs: number;
    state_save_interval_secs: number;
    peer_selection_strategy: 'deterministic_sorted';
  };
  manual_peer_policy_overrides: [];
  peer_pubkey: null;
  runtime_snapshot_json: null;
  onboarding_package: null;
};

let wasmInjected = false;

function hexToBytes(hex: string) {
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

function publicKeyFromSecret(secretHex: string) {
  return getPublicKey(hexToBytes(secretHex)).toLowerCase();
}

async function ensureInjectedWasmModule() {
  if (wasmInjected) return await loadBridgeWasmModule();
  const module = await loadBridgeWasmModule();
  setInjectedWasmBridgeModuleForTests(module as never);
  wasmInjected = true;
  return module;
}

function buildMembers(members: Array<{ idx: number; pubkey: string }>): BrowserGroupPackageMember[] {
  return members.map((member) => ({
    idx: member.idx,
    pubkey: member.pubkey.toLowerCase(),
  }));
}

function buildProfilePayload(input: {
  groupName: string;
  label: string;
  relays: string[];
  groupPublicKey: string;
  threshold: number;
  members: BrowserGroupPackageMember[];
  shareSecret: string;
  profileId: string;
}): BrowserProfilePackagePayload {
  return {
    profileId: input.profileId,
    version: 1,
    device: {
      name: input.label,
      shareSecret: input.shareSecret,
      manualPeerPolicyOverrides: [],
      relays: input.relays,
    },
    groupPackage: {
      groupName: input.groupName,
      groupPk: input.groupPublicKey,
      threshold: input.threshold,
      members: input.members,
    },
  };
}

function buildGroupPackageJson(
  groupName: string,
  groupPublicKey: string,
  threshold: number,
  members: BrowserGroupPackageMember[],
) {
  return JSON.stringify(
    {
      group_name: groupName,
      group_pk: groupPublicKey,
      threshold,
      members,
    },
    null,
    2,
  );
}

function buildSharePackageJson(memberIdx: number, shareSecret: string) {
  return JSON.stringify(
    {
      idx: memberIdx,
      seckey: shareSecret,
    },
    null,
    2,
  );
}

export async function createGeneratedBrowserArtifacts(input?: {
  groupName?: string;
  labelPrefix?: string;
  threshold?: number;
  count?: number;
  password?: string;
  relays?: string[];
}) {
  const groupName = input?.groupName?.trim() || 'Playwright Keyset';
  const labelPrefix = input?.labelPrefix?.trim() || 'Playwright Device';
  const threshold = input?.threshold ?? 2;
  const count = input?.count ?? 3;
  const password = input?.password ?? DEFAULT_BROWSER_PASSWORD;
  const relays = input?.relays?.length ? [...input.relays] : ['ws://127.0.0.1:4848'];

  const wasm = (await ensureInjectedWasmModule()) as unknown as {
    create_keyset_bundle: (inputJson: string) => string;
  };
  const bundle = JSON.parse(
    wasm.create_keyset_bundle(
      JSON.stringify({
        group_name: groupName,
        threshold,
        count,
      }),
    ),
  ) as {
    group: {
      group_pk: string;
      threshold: number;
      members: Array<{ idx: number; pubkey: string }>;
    };
    shares: Array<{ idx: number; seckey: string }>;
  };

  const members = buildMembers(bundle.group.members);
  const groupPublicKey = bundle.group.group_pk.toLowerCase();
  const groupPackageJson = buildGroupPackageJson(groupName, groupPublicKey, bundle.group.threshold, members);

  const shares = await Promise.all(
    bundle.shares.map(async (share) => {
      const shareSecret = share.seckey.toLowerCase();
      const sharePublicKey = publicKeyFromSecret(shareSecret);
      const profileId = await deriveProfileIdFromShareSecret(shareSecret);
      const profilePayload = buildProfilePayload({
        groupName,
        label: `${labelPrefix} ${share.idx}`,
        relays,
        groupPublicKey,
        threshold: bundle.group.threshold,
        members,
        shareSecret,
        profileId,
      });
      const { profileString, shareString } = await createProfilePackagePair(profilePayload, password);
      return {
        memberIdx: share.idx,
        shareSecret,
        sharePublicKey,
        sharePackageJson: buildSharePackageJson(share.idx, shareSecret),
        profileId,
        profilePayload,
        bfprofile: profileString,
        bfshare: shareString,
      } satisfies GeneratedBrowserShareArtifact;
    }),
  );

  return {
    groupName,
    threshold: bundle.group.threshold,
    count: bundle.group.members.length,
    groupPackageJson,
    groupPublicKey,
    shares,
  } satisfies GeneratedBrowserArtifacts;
}

export async function createRotatedBrowserArtifacts(input: {
  current: GeneratedBrowserArtifacts;
  sourceMemberIndices: number[];
  groupName?: string;
  labelPrefix?: string;
  threshold?: number;
  count?: number;
  password?: string;
  relays?: string[];
}) {
  const wasm = (await ensureInjectedWasmModule()) as unknown as {
    rotate_keyset_bundle: (inputJson: string) => string;
  };
  const groupName = input.groupName?.trim() || input.current.groupName;
  const labelPrefix = input.labelPrefix?.trim() || 'Rotated Device';
  const threshold = input.threshold ?? input.current.threshold;
  const count = input.count ?? input.current.count;
  const password = input.password ?? DEFAULT_BROWSER_PASSWORD;
  const relays = input.relays?.length ? [...input.relays] : input.current.shares[0]?.profilePayload.device.relays ?? [];
  const sourceShares = input.sourceMemberIndices.map((memberIdx) => {
    const match = input.current.shares.find((share) => share.memberIdx === memberIdx);
    if (!match) {
      throw new Error(`Missing source share ${memberIdx} for rotation.`);
    }
    return JSON.parse(match.sharePackageJson);
  });
  const group = JSON.parse(input.current.groupPackageJson);
  const rotated = JSON.parse(
    wasm.rotate_keyset_bundle(
      JSON.stringify({
        group,
        shares: sourceShares,
        threshold,
        count,
      }),
    ),
  ) as {
    previous_group_id: string;
    next_group_id: string;
    next: {
      group: {
        group_pk: string;
        threshold: number;
        members: Array<{ idx: number; pubkey: string }>;
      };
      shares: Array<{ idx: number; seckey: string }>;
    };
  };

  const members = buildMembers(rotated.next.group.members);
  const groupPublicKey = rotated.next.group.group_pk.toLowerCase();
  const groupPackageJson = buildGroupPackageJson(groupName, groupPublicKey, rotated.next.group.threshold, members);
  const shares = await Promise.all(
    rotated.next.shares.map(async (share) => {
      const shareSecret = share.seckey.toLowerCase();
      const sharePublicKey = publicKeyFromSecret(shareSecret);
      const profileId = await deriveProfileIdFromShareSecret(shareSecret);
      const profilePayload = buildProfilePayload({
        groupName,
        label: `${labelPrefix} ${share.idx}`,
        relays,
        groupPublicKey,
        threshold: rotated.next.group.threshold,
        members,
        shareSecret,
        profileId,
      });
      const { profileString, shareString } = await createProfilePackagePair(profilePayload, password);
      return {
        memberIdx: share.idx,
        shareSecret,
        sharePublicKey,
        sharePackageJson: buildSharePackageJson(share.idx, shareSecret),
        profileId,
        profilePayload,
        bfprofile: profileString,
        bfshare: shareString,
      } satisfies GeneratedBrowserShareArtifact;
    }),
  );

  return {
    groupName,
    threshold: rotated.next.group.threshold,
    count: rotated.next.group.members.length,
    groupPackageJson,
    groupPublicKey,
    shares,
  } satisfies GeneratedBrowserArtifacts;
}

export async function createOnboardingPackage(input: {
  shareSecret: string;
  relays: string[];
  peerPubkey: string;
  password?: string;
}) {
  await ensureInjectedWasmModule();
  return await encodeBfOnboardPackage(
    {
      shareSecret: input.shareSecret,
      relays: input.relays,
      peerPubkey: input.peerPubkey,
    } satisfies BrowserOnboardPackagePayload,
    input.password ?? DEFAULT_BROWSER_PASSWORD,
  );
}

export async function publishBackupForProfile(profile: BrowserProfilePackagePayload) {
  await ensureInjectedWasmModule();
  const backup = await createEncryptedProfileBackup(profile);
  await publishEncryptedProfileBackup({
    relays: profile.device.relays,
    shareSecret: profile.device.shareSecret,
    backup,
  });
  return backup;
}

export function createPwaStoredProfileSeed(input: {
  artifact: GeneratedBrowserShareArtifact;
  groupPackageJson: string;
  label?: string;
  password?: string;
  source?: 'generated' | 'bfprofile' | 'bfshare' | 'bfonboard';
}): PwaStoredProfileSeed {
  const label = input.label?.trim() || input.artifact.profilePayload.device.name;
  const password = input.password ?? DEFAULT_BROWSER_PASSWORD;
  const createdAt = Date.now();
  return {
    id: input.artifact.profileId,
    label,
    share_public_key: input.artifact.sharePublicKey,
    group_public_key: groupPublicKeyFromPackage(input.artifact.profilePayload.groupPackage),
    relays: [...input.artifact.profilePayload.device.relays],
    group_package_json: input.groupPackageJson,
    share_package_json: input.artifact.sharePackageJson,
    source: input.source ?? 'generated',
    relay_profile: input.artifact.profilePayload.device.relays[0] ?? 'local',
    group_ref: `browser-profile:${input.artifact.profileId}:group`,
    share_ref: `browser-profile:${input.artifact.profileId}:share`,
    state_path: `/tmp/igloo-pwa/${input.artifact.profileId}`,
    created_at: createdAt,
    stored_password: password,
    profile_string: input.artifact.bfprofile,
    share_string: input.artifact.bfshare,
    signer_settings: {
      sign_timeout_secs: 30,
      ping_timeout_secs: 15,
      request_ttl_secs: 300,
      state_save_interval_secs: 30,
      peer_selection_strategy: 'deterministic_sorted',
    },
    manual_peer_policy_overrides: [],
    peer_pubkey: null,
    runtime_snapshot_json: null,
    onboarding_package: null,
  };
}
