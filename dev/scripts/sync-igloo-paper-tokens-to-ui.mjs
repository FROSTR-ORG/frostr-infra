#!/usr/bin/env node

import { readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..', '..');
const paperTokenDir = path.join(rootDir, 'repos', 'igloo-paper', 'design', 'tokens');
const uiTokenDir = path.join(rootDir, 'repos', 'igloo-ui', 'src', 'tokens');
const tsOutputFile = path.join(uiTokenDir, 'design-tokens.ts');
const cssOutputFile = path.join(uiTokenDir, 'design-tokens.css');
const legacyOutputFiles = [
  path.join(uiTokenDir, 'paper-tokens.ts'),
  path.join(uiTokenDir, 'paper-tokens.css'),
];

const COLOR_ALIASES = {
  surface: {
    source: 'background-colors',
    labels: {
      'gray-950': 'gray950',
      'gray-900': 'gray900',
      'gray-900/40': 'gray90040',
      'slate-900/60': 'slate90060',
      'slate-900/80': 'slate90080',
    },
  },
  primary: {
    source: 'blue-scale-primary',
    labels: {
      'blue-100': 'blue100',
      'blue-200': 'blue200',
      'blue-300': 'blue300',
      'blue-400': 'blue400',
      'blue-600': 'blue600',
      'blue-700': 'blue700',
      'blue-900': 'blue900',
    },
  },
  semantic: {
    source: 'semantic-colors',
    labels: {
      'green-600': 'success',
      'red-600': 'destructive',
      'amber-400': 'warning',
      'orange-400': 'caution',
      'purple-400': 'policy',
      'red-900/30': 'errorBackground',
      'yellow-900/30': 'warningBackground',
    },
  },
  text: {
    source: 'interface-text-tones',
    labels: {
      'slate-200': 'primary',
      'slate-400': 'secondary',
      'slate-500': 'muted',
    },
  },
  border: {
    source: 'interface-borders-overlays',
    labels: {
      'blue-900/30': 'focus',
      'blue-900/20': 'panel',
      'slate-400/20': 'muted',
      'red-500/06': 'destructiveBackground',
      'red-500/30': 'destructive',
    },
  },
  status: {
    source: 'status',
    labels: {
      Default: 'default',
      Success: 'success',
      Error: 'error',
      Warning: 'warning',
      Info: 'info',
    },
  },
};

const TYPE_ALIASES = {
  'H1 Heading': 'h1',
  'H2 Section Header': 'h2',
  'H3 Card Title': 'h3',
  'Body text': 'body',
  Small: 'small',
  'Value data': 'valueData',
  'Mono labels': 'monoLabels',
};

const TYPE_CSS_ALIASES = {
  valueData: 'value',
  monoLabels: 'mono-labels',
};

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

function camelize(value) {
  return slugify(value).replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
}

function colorVariableName(sectionKey, label) {
  const prefix = sectionKey === 'status' ? 'status-' : '';
  return `--igloo-color-${prefix}${slugify(label)}`;
}

function fontVariableName(name) {
  return `--igloo-font-${slugify(name)}`;
}

function typeVariablePrefix(label) {
  const alias = TYPE_ALIASES[label] ?? label;
  return `--igloo-text-${TYPE_CSS_ALIASES[alias] ?? slugify(alias)}`;
}

function hexToRgb(value) {
  const match = /^#([0-9A-Fa-f]{6})(?:[0-9A-Fa-f]{2})?$/.exec(value);
  if (!match) {
    return null;
  }
  const hex = match[1];
  return [
    Number.parseInt(hex.slice(0, 2), 16),
    Number.parseInt(hex.slice(2, 4), 16),
    Number.parseInt(hex.slice(4, 6), 16),
  ].join(' ');
}

function readColorToken(section, label, colors) {
  const token = colors[section]?.tokens?.[label];
  if (!token?.value) {
    throw new Error(`Missing source color token ${section}.${label}`);
  }
  return token.value;
}

function buildColorTokens(colors) {
  const output = {};
  for (const [groupName, group] of Object.entries(COLOR_ALIASES)) {
    output[groupName] = {};
    for (const [label, alias] of Object.entries(group.labels)) {
      output[groupName][alias] = readColorToken(group.source, label, colors);
    }
  }
  return output;
}

function buildTypographyTokens(typography) {
  const fontFamily = {};
  for (const [name, token] of Object.entries(typography['font-families'] ?? {})) {
    fontFamily[camelize(name)] = token.stack;
  }

  const typeScale = {};
  for (const [label, alias] of Object.entries(TYPE_ALIASES)) {
    const token = typography['type-scale']?.[label];
    if (!token) {
      throw new Error(`Missing source typography token ${label}`);
    }
    const family = token['font-family'];
    typeScale[alias] = {
      fontFamily: `var(${fontVariableName(family)})`,
      fontSize: token['font-size'],
      lineHeight: token['line-height'],
      fontWeight: token['font-weight'],
    };
    if (token['letter-spacing']) {
      typeScale[alias].letterSpacing = token['letter-spacing'];
    }
  }

  return { fontFamily, typeScale };
}

function buildCssVariables() {
  return {
    color: {
      surface: {
        page: 'var(--igloo-color-gray-950)',
        panel: 'var(--igloo-color-slate-900-60)',
        panelStrong: 'var(--igloo-color-slate-900-80)',
      },
      primary: {
        blue100: 'var(--igloo-color-blue-100)',
        blue200: 'var(--igloo-color-blue-200)',
        blue300: 'var(--igloo-color-blue-300)',
        blue400: 'var(--igloo-color-blue-400)',
        blue600: 'var(--igloo-color-blue-600)',
        blue700: 'var(--igloo-color-blue-700)',
        blue900: 'var(--igloo-color-blue-900)',
      },
      text: {
        primary: 'var(--igloo-color-slate-200)',
        secondary: 'var(--igloo-color-slate-400)',
        muted: 'var(--igloo-color-slate-500)',
      },
      status: {
        default: 'var(--igloo-color-status-default)',
        success: 'var(--igloo-color-status-success)',
        error: 'var(--igloo-color-status-error)',
        warning: 'var(--igloo-color-status-warning)',
        info: 'var(--igloo-color-status-info)',
      },
    },
    font: {
      body: 'var(--igloo-font-inter)',
      display: 'var(--igloo-font-share-tech-mono)',
      value: 'var(--igloo-font-share-tech-mono)',
    },
  };
}

function formatTsObject(value, indent = 0) {
  const pad = ' '.repeat(indent);
  const nextPad = ' '.repeat(indent + 2);
  if (typeof value === 'string') {
    return `'${value}'`;
  }
  if (typeof value === 'number') {
    return String(value);
  }
  if (value && typeof value === 'object') {
    const entries = Object.entries(value)
      .map(([key, child]) => `${nextPad}${key}: ${formatTsObject(child, indent + 2)},`)
      .join('\n');
    return `{\n${entries}\n${pad}}`;
  }
  throw new Error(`Unsupported token value: ${value}`);
}

function renderTs(colors, typography) {
  return `// Generated by frostr-infra token handoff. Do not edit by hand.

export const IGLOO_COLOR_TOKENS = ${formatTsObject(buildColorTokens(colors))} as const;

export const IGLOO_TYPOGRAPHY_TOKENS = ${formatTsObject(buildTypographyTokens(typography))} as const;

export const iglooTokenCssVariables = ${formatTsObject(buildCssVariables())} as const;

export type IglooColorTokens = typeof IGLOO_COLOR_TOKENS;
export type IglooTypographyTokens = typeof IGLOO_TYPOGRAPHY_TOKENS;
`;
}

function renderCss(colors, typography) {
  const lines = [
    '/*',
    ' * Igloo design tokens.',
    ' * Generated by frostr-infra token handoff.',
    ' * Keep this file package-local.',
    ' */',
    '',
    ':root {',
  ];

  for (const [sectionKey, section] of Object.entries(colors)) {
    lines.push(`  /* ${section.title} */`);
    for (const [label, token] of Object.entries(section.tokens ?? {})) {
      const variableName = colorVariableName(sectionKey, label);
      lines.push(`  ${variableName}: ${token.value};`);
      const rgb = hexToRgb(token.value);
      if (rgb) {
        lines.push(`  ${variableName.replace('--igloo-color-', '--igloo-rgb-')}: ${rgb};`);
      }
    }
    lines.push('');
  }

  lines.push('  /* Font families */');
  for (const [name, token] of Object.entries(typography['font-families'] ?? {})) {
    lines.push(`  ${fontVariableName(name)}: ${token.stack};`);
  }
  lines.push('');

  lines.push('  /* Type scale */');
  for (const [label, token] of Object.entries(typography['type-scale'] ?? {})) {
    const prefix = typeVariablePrefix(label);
    lines.push(`  ${prefix}-font-family: var(${fontVariableName(token['font-family'])});`);
    lines.push(`  ${prefix}-size: ${token['font-size']};`);
    lines.push(`  ${prefix}-line-height: ${token['line-height']};`);
    lines.push(`  ${prefix}-weight: ${token['font-weight']};`);
    if (token['letter-spacing']) {
      lines.push(`  ${prefix}-tracking: ${token['letter-spacing']};`);
    }
    lines.push('');
  }

  while (lines[lines.length - 1] === '') {
    lines.pop();
  }
  lines.push('}');
  return `${lines.join('\n')}\n`;
}

async function readInputs() {
  const colors = JSON.parse(await readFile(path.join(paperTokenDir, 'colors.json'), 'utf8'));
  const typography = JSON.parse(await readFile(path.join(paperTokenDir, 'typography.json'), 'utf8'));
  return { colors, typography };
}

async function renderOutputs() {
  const { colors, typography } = await readInputs();
  return {
    ts: renderTs(colors, typography),
    css: renderCss(colors, typography),
  };
}

async function sync() {
  const outputs = await renderOutputs();
  await writeFile(tsOutputFile, outputs.ts);
  await writeFile(cssOutputFile, outputs.css);
  await Promise.all(legacyOutputFiles.map((file) => rm(file, { force: true })));
}

async function check() {
  const outputs = await renderOutputs();
  const currentTs = await readFile(tsOutputFile, 'utf8');
  const currentCss = await readFile(cssOutputFile, 'utf8');
  const stale = [];
  if (currentTs !== outputs.ts) {
    stale.push('repos/igloo-ui/src/tokens/design-tokens.ts');
  }
  if (currentCss !== outputs.css) {
    stale.push('repos/igloo-ui/src/tokens/design-tokens.css');
  }
  for (const file of legacyOutputFiles) {
    try {
      await readFile(file, 'utf8');
      stale.push(path.relative(rootDir, file));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }
  if (stale.length > 0) {
    console.error(`Igloo UI token handoff outputs are stale:\n${stale.map((file) => `- ${file}`).join('\n')}`);
    process.exit(1);
  }
  console.log('ok: Igloo UI token handoff outputs are current');
}

const mode = process.argv[2];
if (mode === 'sync') {
  await sync();
} else if (mode === 'check') {
  await check();
} else {
  console.error('usage: node dev/scripts/sync-igloo-paper-tokens-to-ui.mjs <sync|check>');
  process.exit(1);
}
