import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

import { REPO_ROOT_DIR } from './repo-paths';

export const TEST_BROWSER_WASM_DIR_ENV = 'FROSTR_TEST_BROWSER_WASM_DIR';

export function defaultTestBrowserWasmDir() {
  const prebuildDir = process.env.FROSTR_TEST_PREBUILD_DIR?.trim()
    || path.join(REPO_ROOT_DIR, '.tmp', 'test-prebuild');
  return path.join(prebuildDir, 'browser-wasm', 'igloo-shared', 'public', 'wasm');
}

export function resolveTestBrowserWasmDir() {
  return process.env[TEST_BROWSER_WASM_DIR_ENV]?.trim() || defaultTestBrowserWasmDir();
}

export function setDefaultTestBrowserWasmDir() {
  process.env[TEST_BROWSER_WASM_DIR_ENV] ??= defaultTestBrowserWasmDir();
}

export function testBrowserWasmLoaderUrl(fileName: string) {
  return pathToFileURL(path.join(resolveTestBrowserWasmDir(), fileName)).href;
}

export async function readTestBrowserWasmFile(fileName: string) {
  const filePath = path.join(resolveTestBrowserWasmDir(), fileName);
  try {
    return await readFile(filePath);
  } catch (error) {
    if (
      error
      && typeof error === 'object'
      && 'code' in error
      && error.code === 'ENOENT'
    ) {
      throw new Error(
        `Missing browser WASM test artifact at ${filePath}. Run the relevant Playwright lane or make test-prep before this spec.`,
      );
    }
    throw error;
  }
}
