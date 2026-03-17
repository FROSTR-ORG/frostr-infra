import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const TEST_ROOT_DIR = path.resolve(__dirname, '..');
export const REPO_ROOT_DIR = path.resolve(TEST_ROOT_DIR, '..');
export const IGLOO_PWA_DIR = path.join(REPO_ROOT_DIR, 'repos', 'igloo-pwa');
export const IGLOO_CHROME_DIR = path.join(REPO_ROOT_DIR, 'repos', 'igloo-chrome');
export const IGLOO_HOME_DIR = path.join(REPO_ROOT_DIR, 'repos', 'igloo-home');
export const IGLOO_SHELL_DIR =
  process.env.IGLOO_SHELL_DIR ?? path.join(REPO_ROOT_DIR, 'repos', 'igloo-shell');
export const IGLOO_CHROME_DIST_DIR = path.join(IGLOO_CHROME_DIR, 'dist');
export const BIFROST_RS_DIR =
  process.env.BIFROST_RS_DIR ?? path.join(REPO_ROOT_DIR, 'repos', 'bifrost-rs');
