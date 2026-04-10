import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

import { IGLOO_SHELL_DIR, REPO_ROOT_DIR } from './repo-paths';

export const IGLOO_SHELL_TARGET_DIR = path.join(REPO_ROOT_DIR, 'build', 'igloo-shell-target');
export const IGLOO_SHELL_BINARY_PATH = path.join(IGLOO_SHELL_TARGET_DIR, 'debug', 'igloo-shell');

let shellPrepared = false;

function buildBinary(args: string[]) {
  execFileSync('cargo', args, {
    cwd: IGLOO_SHELL_DIR,
    stdio: 'inherit',
    env: {
      ...process.env,
      CARGO_TARGET_DIR: IGLOO_SHELL_TARGET_DIR
    }
  });
}

function supportsCurrentImportContract(binaryPath: string) {
  try {
    const help = execFileSync(binaryPath, ['import', '--help'], {
      cwd: IGLOO_SHELL_DIR,
      env: process.env,
      encoding: 'utf8'
    });
    return help.includes('--passphrase');
  } catch {
    return false;
  }
}

export function ensureIglooShellBinary() {
  if (shellPrepared) return IGLOO_SHELL_BINARY_PATH;
  if (
    process.env.FROSTR_TEST_PREPARED === '1' &&
    existsSync(IGLOO_SHELL_BINARY_PATH) &&
    supportsCurrentImportContract(IGLOO_SHELL_BINARY_PATH)
  ) {
    shellPrepared = true;
    return IGLOO_SHELL_BINARY_PATH;
  }
  buildBinary(['build', '--offline', '-p', 'igloo-shell-cli', '--bin', 'igloo-shell']);
  shellPrepared = true;
  return IGLOO_SHELL_BINARY_PATH;
}
