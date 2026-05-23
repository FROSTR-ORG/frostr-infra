import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const MANIFEST_PATH = process.env.FROSTR_PWA_VISUAL_MANIFEST_PATH
  ? path.resolve(process.env.FROSTR_PWA_VISUAL_MANIFEST_PATH)
  : path.join(ROOT_DIR, 'test', 'igloo-pwa', 'visual-manifest.json');
const PAPER_DIR = path.join(ROOT_DIR, 'repos', 'igloo-paper');
const ALLOWED_STATUSES = new Set(['aligned', 'needs-work']);

function pathExists(filePath) {
  return fs.existsSync(filePath);
}

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

function isRecord(value) {
  return value && typeof value === 'object' && !Array.isArray(value);
}

const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));

if (!isRecord(manifest)) {
  fail('visual manifest must be a JSON object');
} else if (manifest.suite !== 'igloo-pwa-paper-visuals') {
  fail('visual manifest suite must be igloo-pwa-paper-visuals');
}

const screens = isRecord(manifest) && Array.isArray(manifest.screens) ? manifest.screens : [];
if (screens.length === 0) {
  fail('visual manifest must contain screens');
}

const names = new Set();
const outputs = new Set();
const paperPopulated = pathExists(path.join(PAPER_DIR, 'design')) || pathExists(path.join(PAPER_DIR, 'screens'));
const requirePaperReferences = process.env.FROSTR_PWA_VISUAL_REQUIRE_PAPER === '1';
const checkPaperReferences = paperPopulated || requirePaperReferences;

for (const [index, screen] of screens.entries()) {
  const label = `screen[${index}]`;
  if (!isRecord(screen)) {
    fail(`${label} must be an object`);
    continue;
  }

  const { name, viewport, output, paperReference, status } = screen;
  if (typeof name !== 'string' || !/^[a-z0-9][a-z0-9-]*$/.test(name)) {
    fail(`${label}.name must be lower-kebab-case`);
  } else if (names.has(name)) {
    fail(`${label}.name duplicates ${name}`);
  } else {
    names.add(name);
  }

  if (typeof viewport !== 'string' || !/^[1-9][0-9]*x[1-9][0-9]*$/.test(viewport)) {
    fail(`${label}.viewport must use WIDTHxHEIGHT`);
  }

  if (
    typeof output !== 'string'
    || !output.startsWith('.tmp/visual/igloo-pwa/')
    || !output.endsWith('.png')
  ) {
    fail(`${label}.output must be a .tmp/visual/igloo-pwa/*.png path`);
  } else if (outputs.has(output)) {
    fail(`${label}.output duplicates ${output}`);
  } else {
    outputs.add(output);
  }

  if (
    typeof paperReference !== 'string'
    || !paperReference.startsWith('repos/igloo-paper/')
    || !paperReference.endsWith('/screenshot.png')
  ) {
    fail(`${label}.paperReference must point to a repos/igloo-paper/*/screenshot.png path`);
  } else if (checkPaperReferences && !pathExists(path.join(ROOT_DIR, paperReference))) {
    fail(`${label}.paperReference does not exist: ${paperReference}`);
  }

  if (typeof status !== 'string' || !ALLOWED_STATUSES.has(status)) {
    fail(`${label}.status must be one of: ${Array.from(ALLOWED_STATUSES).join(', ')}`);
  }
}

if (process.exitCode) {
  process.exit(process.exitCode);
}

console.log(`ok: validated ${screens.length} PWA visual manifest entries`);
if (!checkPaperReferences) {
  console.log('ok: skipped Paper reference existence checks because repos/igloo-paper is not populated');
}
