import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const DOC_PATHS = [
  'README.md',
  'CONTRIBUTING.md',
  'test/README.md',
  'dev/README.md',
];

for (const entry of fs.readdirSync(path.join(ROOT_DIR, 'docs'))) {
  if (entry.endsWith('.md')) {
    DOC_PATHS.push(path.join('docs', entry));
  }
}

for (const entry of fs.readdirSync(path.join(ROOT_DIR, 'dev', 'docs'))) {
  if (entry.endsWith('.md')) {
    DOC_PATHS.push(path.join('dev', 'docs', entry));
  }
}

for (const entry of fs.readdirSync(path.join(ROOT_DIR, 'dev', 'adrs'))) {
  if (entry.endsWith('.md')) {
    DOC_PATHS.push(path.join('dev', 'adrs', entry));
  }
}

for (const entry of fs.readdirSync(path.join(ROOT_DIR, 'dev', 'policies'))) {
  if (entry.endsWith('.md')) {
    DOC_PATHS.push(path.join('dev', 'policies', entry));
  }
}

const SLUG_INVALID_RE = /[^\p{Letter}\p{Number}\s-]/gu;
const LINK_RE = /!?\[([^\]]*)\]\(([^)\s]+(?:\s+"[^"]*")?)\)/g;
const CODE_FENCE_RE = /```[\s\S]*?```/g;
const INLINE_CODE_RE = /`[^`]*`/g;

function readFile(relPath) {
  return fs.readFileSync(path.join(ROOT_DIR, relPath), 'utf8');
}

function stripCode(text) {
  return text.replace(CODE_FENCE_RE, '').replace(INLINE_CODE_RE, '');
}

function slugifyHeading(text, counts) {
  const base = text
    .trim()
    .toLowerCase()
    .replace(SLUG_INVALID_RE, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  const slugBase = base || 'section';
  const seen = counts.get(slugBase) ?? 0;
  counts.set(slugBase, seen + 1);
  return seen === 0 ? slugBase : `${slugBase}-${seen}`;
}

function collectAnchors(relPath) {
  const text = readFile(relPath);
  const counts = new Map();
  const anchors = new Set();

  for (const line of text.split('\n')) {
    const match = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
    if (!match) {
      continue;
    }
    const headingText = match[2].replace(/\s+#+\s*$/, '');
    anchors.add(slugifyHeading(headingText, counts));
  }

  return anchors;
}

const anchorCache = new Map();

function getAnchors(relPath) {
  if (!anchorCache.has(relPath)) {
    anchorCache.set(relPath, collectAnchors(relPath));
  }
  return anchorCache.get(relPath);
}

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

function validateExternalUrl(file, urlString) {
  try {
    const url = new URL(urlString);
    if (!['http:', 'https:', 'mailto:'].includes(url.protocol)) {
      fail(`${file}: unsupported external link protocol '${url.protocol}' in ${urlString}`);
    }
  } catch {
    fail(`${file}: invalid external URL ${urlString}`);
  }
}

for (const relPath of DOC_PATHS) {
  const text = stripCode(readFile(relPath));

  for (const match of text.matchAll(LINK_RE)) {
    const rawTarget = match[2].trim().replace(/\s+"[^"]*"$/, '');

    if (rawTarget.startsWith('http://') || rawTarget.startsWith('https://') || rawTarget.startsWith('mailto:')) {
      validateExternalUrl(relPath, rawTarget);
      continue;
    }

    if (rawTarget.startsWith('#')) {
      const anchor = rawTarget.slice(1);
      if (!getAnchors(relPath).has(anchor)) {
        fail(`${relPath}: missing same-file anchor ${rawTarget}`);
      }
      continue;
    }

    const [targetPath, fragment] = rawTarget.split('#');
    const resolvedPath = path.normalize(path.join(path.dirname(relPath), targetPath));
    const absoluteTarget = path.join(ROOT_DIR, resolvedPath);

    if (!fs.existsSync(absoluteTarget)) {
      fail(`${relPath}: missing link target ${rawTarget}`);
      continue;
    }

    if (fragment && resolvedPath.endsWith('.md')) {
      if (!getAnchors(resolvedPath).has(fragment)) {
        fail(`${relPath}: missing anchor ${rawTarget}`);
      }
    }
  }
}

if (process.exitCode) {
  process.exit(process.exitCode);
}

console.log(`ok: validated markdown links and anchors across ${DOC_PATHS.length} files`);
