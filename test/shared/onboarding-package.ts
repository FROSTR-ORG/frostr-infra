import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

import { BIFROST_RS_DIR } from './repo-paths';

const BIFROST_TARGET_DIR = path.join(os.tmpdir(), 'frostr-infra-bifrost-target');
const DEVTOOLS_BINARY_PATH = path.join(BIFROST_TARGET_DIR, 'debug', 'bifrost-devtools');

let devtoolsPrepared = false;

type AssembleParams = {
  shareIdx: number;
  shareSecretHex32: string;
  peerPubkey32: string;
  relays: string[];
  password?: string;
  inviteToken?: string;
  challengeHex32?: string;
  createdAt?: number;
  expiresAt?: number;
  label?: string;
};

export type AssembledOnboardingPackage = {
  onboardingPackage: string;
  onboardingPassword: string;
  inviteToken: string;
  challengeHex32: string;
};

type InviteTokenJson = {
  version: number;
  callback_peer_pk: string;
  relays: string[];
  challenge: string;
  created_at: number;
  expires_at: number;
  label: string | null;
};

function ensureDevtoolsBinary() {
  if (devtoolsPrepared) return DEVTOOLS_BINARY_PATH;
  execFileSync(
    'cargo',
    ['build', '--offline', '-p', 'bifrost-dev', '--bin', 'bifrost-devtools'],
    {
      cwd: BIFROST_RS_DIR,
      stdio: 'inherit',
      env: {
        ...process.env,
        CARGO_TARGET_DIR: BIFROST_TARGET_DIR
      }
    }
  );
  devtoolsPrepared = true;
  return DEVTOOLS_BINARY_PATH;
}

export function assembleOnboardingPackage(params: AssembleParams): AssembledOnboardingPackage {
  const binaryPath = ensureDevtoolsBinary();
  const password = params.password ?? randomBytes(16).toString('hex');
  const createdAt = params.createdAt ?? Math.floor(Date.now() / 1000);
  const expiresAt = params.expiresAt ?? createdAt + 600;
  const generatedChallengeHex32 = params.challengeHex32 ?? randomBytes(32).toString('hex');

  const inviteToken =
    params.inviteToken ??
    JSON.stringify({
      version: 1,
      callback_peer_pk: params.peerPubkey32.toLowerCase(),
      relays: params.relays,
      challenge: generatedChallengeHex32,
      created_at: createdAt,
      expires_at: expiresAt,
      label: params.label ?? null
    });
  const parsedInviteToken = JSON.parse(inviteToken) as InviteTokenJson;
  const challengeHex32 = parsedInviteToken.challenge.toLowerCase();

  const tempDir = mkdtempSync(path.join(os.tmpdir(), 'frostr-onboard-'));
  const sharePath = path.join(tempDir, 'share.json');
  try {
    writeFileSync(
      sharePath,
      JSON.stringify(
        {
          idx: params.shareIdx,
          seckey: params.shareSecretHex32.toLowerCase()
        },
        null,
        2
      )
    );

    const onboardingPackage = execFileSync(
      binaryPath,
      ['invite', 'assemble', '--token', inviteToken, '--share', sharePath, '--password-env', 'INVITE_PASSWORD'],
      {
        cwd: BIFROST_RS_DIR,
        env: {
          ...process.env,
          INVITE_PASSWORD: password
        },
        encoding: 'utf8'
      }
    ).trim();

    return {
      onboardingPackage,
      onboardingPassword: password,
      inviteToken,
      challengeHex32
    };
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}
