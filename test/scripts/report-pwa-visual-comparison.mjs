import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '../..');
const manifestPath = path.join(rootDir, 'test/igloo-pwa/visual-manifest.json');
const outputPath = path.resolve(
  rootDir,
  process.env.FROSTR_PWA_VISUAL_REPORT_PATH || '.tmp/visual/igloo-pwa/comparison-report.md',
);

function readManifest() {
  return JSON.parse(readFileSync(manifestPath, 'utf8'));
}

function fromReport(relativeOrAbsolutePath) {
  const absolutePath = path.isAbsolute(relativeOrAbsolutePath)
    ? relativeOrAbsolutePath
    : path.join(rootDir, relativeOrAbsolutePath);
  return {
    absolutePath,
    relativePath: path.relative(path.dirname(outputPath), absolutePath).split(path.sep).join('/'),
    exists: existsSync(absolutePath),
  };
}

function statusLabel(status) {
  if (status === 'aligned') return 'aligned';
  if (status === 'needs-work') return 'needs work';
  return status || 'unknown';
}

function renderScreen(screen) {
  const paper = fromReport(screen.paperReference);
  const pwa = fromReport(screen.output);
  const lines = [
    `## ${screen.name}`,
    '',
    `- Status: ${statusLabel(screen.status)}`,
    `- Viewport: ${screen.viewport || 'unknown'}`,
    `- Paper reference: \`${screen.paperReference}\` (${paper.exists ? 'exists' : 'missing'})`,
    `- PWA capture: \`${screen.output}\` (${pwa.exists ? 'exists' : 'missing'})`,
    '',
  ];

  if (paper.exists) {
    lines.push('### Paper', '', `![${screen.name} Paper reference](${paper.relativePath})`, '');
  }
  if (pwa.exists) {
    lines.push('### PWA', '', `![${screen.name} PWA capture](${pwa.relativePath})`, '');
  }
  if (!paper.exists || !pwa.exists) {
    lines.push('Run `npm --prefix test run test:e2e:igloo-pwa:visual` before using this report for visual review.', '');
  }

  return lines.join('\n');
}

function renderReport(manifest) {
  const rows = manifest.screens.map((screen) => {
    const paper = fromReport(screen.paperReference);
    const pwa = fromReport(screen.output);
    return [
      screen.name,
      statusLabel(screen.status),
      screen.viewport || '',
      paper.exists ? 'exists' : 'missing',
      pwa.exists ? 'exists' : 'missing',
    ];
  });

  const lines = [
    '# igloo-pwa Paper Visual Comparison',
    '',
    `Generated: ${new Date().toISOString()}`,
    `Manifest: \`${path.relative(rootDir, manifestPath)}\``,
    '',
    '| Screen | Status | Viewport | Paper | PWA |',
    '| --- | --- | --- | --- | --- |',
    ...rows.map((row) => `| ${row.join(' | ')} |`),
    '',
    ...manifest.screens.flatMap((screen) => [renderScreen(screen)]),
  ];

  return `${lines.join('\n')}\n`;
}

const manifest = readManifest();
mkdirSync(path.dirname(outputPath), { recursive: true });
writeFileSync(outputPath, renderReport(manifest));
console.log(`ok: wrote ${path.relative(rootDir, outputPath)}`);
