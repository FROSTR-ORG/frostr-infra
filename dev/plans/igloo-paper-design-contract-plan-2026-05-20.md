# Igloo Paper Hard-Cut Design Contract Upgrade

Date: 2026-05-20
Status: Draft for implementation planning

## Goal

Upgrade `repos/igloo-paper` from a static Paper export repository into the
versioned design contract between Paper Desktop and `repos/igloo-ui`.

This is a hard-cut plan. The final branch should not leave compatibility
aliases, legacy docs, stale paths, generated-file ambiguity, or Factory mission
scaffolding behind.

Target pipeline:

```text
Paper Desktop
  -> Paper MCP
    -> repos/igloo-paper design contract
      -> repos/igloo-ui semantic implementation
        -> host apps
```

`igloo-paper` remains reference-only. Runtime packages, app builds, and host
apps must not import `igloo-paper`, generated Paper JSX, screenshots, or Paper
MCP code.

## Hard-Cut Rules

- Remove `repos/igloo-paper/INSTRUCTIONS.md`; replace it with
  `repos/igloo-paper/AGENTS.md` and update all parent/root references.
- Remove `repos/igloo-paper/.factory` after salvaging still-accurate guidance
  into normal repo docs.
- Rename `repos/igloo-paper/design-system` to `repos/igloo-paper/design`; do
  not leave aliases, symlinks, compatibility paths, or duplicate exports.
- Treat generated Paper HTML and JSX as reference material only. `igloo-ui`
  must implement semantic React components and token-backed styles.
- Require coding agents to ask before any Paper canvas mutation, including
  experimental duplicate creation.
- Keep Paper MCP out of production builds and release automation.
- Track all generated files with a manifest so stale generated artifacts can be
  removed intentionally and safely.

## Final Repository Shape

```text
repos/igloo-paper/
  README.md
  AGENTS.md
  artboard-map.json
  artboard-policy.json
  export-metadata.json
  design-contract.json
  generated-manifest.json
  design/
  screens/
  assets/
  docs/
  scripts/
```

Top-level responsibilities:

- `README.md`: short human-facing overview, source-of-truth model, and command
  summary.
- `AGENTS.md`: repo-local rules for coding agents and contributors.
- `artboard-map.json`: exported Paper artboards and output paths.
- `artboard-policy.json`: classification for every live Paper artboard that is
  not exported.
- `export-metadata.json`: README/content curation only.
- `design-contract.json`: mapping between Paper references and `igloo-ui`
  implementation surfaces.
- `generated-manifest.json`: complete list of generated files.
- `docs/`: detailed runbooks and policy docs.
- `scripts/`: Paper MCP export and verification tooling.

## Design Contracts

### Artboard Policy

`artboard-policy.json` is the canonical classification file for live Paper
artboards. Do not encode workflow state in Paper artboard names.

Statuses:

- `exported`: mapped in `artboard-map.json`
- `ignored`: intentionally excluded from export
- `experimental`: exploratory work that must not feed implementation yet
- `internal`: Paper-only support board, label row, or composition board
- `deprecated`: retained temporarily for comparison or migration history

`verify.py` must fail when a live Paper artboard is neither exported nor
classified.

### Design Contract

`design-contract.json` maps design references to implementation surfaces.

Minimum entry shape:

```json
{
  "name": "AppHeader",
  "kind": "component",
  "status": "implemented",
  "paper": {
    "artboardName": "Navigation & Layout",
    "artboardId": "1HI-0",
    "referencePath": "design/components/navigation-layout"
  },
  "implementation": {
    "repo": "repos/igloo-ui",
    "paths": ["src/components/ui/app-header.tsx"]
  },
  "tokens": ["blue-400", "slate-500", "blue-900/30"],
  "notes": "Primary app navigation across public, flow, profile-context, and dashboard states."
}
```

Allowed implementation statuses:

- `reference-only`
- `planned`
- `in-progress`
- `implemented`
- `needs-review`
- `deprecated`

The contract should stay compact. It should identify the relevant design and
implementation surfaces, not duplicate exported DOM structure.

### Generated Manifest

`generated-manifest.json` tracks every generated artifact:

- `design/**`
- `screens/**`
- `assets/**`
- generated READMEs
- token outputs
- glossary outputs
- shared HTML
- screenshots

`verify.py` must check that manifest entries exist, generated files are covered,
and stale generated files can be identified without risking hand-authored docs
or metadata.

## Commands

Add:

```bash
make igloo-paper-sync
```

Default behavior:

```bash
cd repos/igloo-paper
PYTHONDONTWRITEBYTECODE=1 python3 scripts/export_from_paper.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify.py --strict-drift
```

`make igloo-paper-sync` is strict by default. Support:

```bash
make igloo-paper-sync STRICT=0
```

for exploratory syncs that run non-strict verification after export.

Keep:

```bash
make igloo-paper-verify
make igloo-paper-verify STRICT=1
```

Do not include Paper sync or Paper verification in default release/test lanes;
they require Paper Desktop and local Paper MCP.

## Documentation

Create or update:

- `README.md`: one-screen orientation and command summary.
- `AGENTS.md`: source of truth for repo-local contributor and agent rules.
- `docs/onboarding.md`: designer, developer, and coding-agent workflows.
- `docs/sync-runbook.md`: full Paper MCP sync, verification, strict drift,
  artifact cleanup, and troubleshooting procedure.
- `docs/generated-files.md`: generated versus hand-maintained files.
- `docs/token-policy.md`: Foundations, usage coverage, token promotion, and
  strict drift.
- `docs/design-contract.md`: how `design-contract.json` is structured and
  maintained.

Fold useful `.factory` content into these docs before deleting `.factory`:

- keep still-accurate static-repo framing, Paper MCP prerequisites,
  verification-mode notes, and file-based validation framing.
- discard stale artboard counts, old Paper file names, old node IDs,
  `design-system/` paths, deprecated screen slugs, Factory worker procedures,
  and `.factory/init.sh`.

Update parent/root docs to point at `repos/igloo-paper/README.md`,
`repos/igloo-paper/AGENTS.md`, or a specific `repos/igloo-paper/docs/*` page.
No parent doc should reference `repos/igloo-paper/INSTRUCTIONS.md`.

## Script Hygiene

Refactor scripts only as far as needed to make ownership and artifacts clean.
Avoid creating a framework.

Requirements:

- Public Python commands must not write bytecode: use
  `PYTHONDONTWRITEBYTECODE=1` or `python3 -B`.
- Temporary and staging work must live under `repos/igloo-paper/tmp/` or parent
  `./.tmp/`, not beside generated artifacts.
- Export should write through staging, then replace final generated files only
  after successful export.
- Cleanup may delete only manifest-classified generated files.
- Export should print a concise summary: exported artboards, classified
  non-exported artboards, generated files, localized assets, token counts, and
  drift status.
- Public commands must leave no `__pycache__`, `.pyc`, temp, or partial-export
  artifacts behind.

Suggested module split:

```text
scripts/
  paper_mcp.py
  export_from_paper.py
  verify.py
  igloo_paper/
    artboards.py
    assets.py
    generated.py
    readmes.py
    tokens.py
    screenshots.py
```

## Upgrade Workstreams

### 1. Root Command Surface

- Add `make igloo-paper-sync [STRICT=0|1]`.
- Keep `make igloo-paper-verify [STRICT=1]`.
- Update root command-surface tests and help text.
- Ensure public commands disable Python bytecode.

### 2. Repo Docs Hard Cut

- Rewrite `repos/igloo-paper/README.md`.
- Add `repos/igloo-paper/AGENTS.md`.
- Remove `repos/igloo-paper/INSTRUCTIONS.md`.
- Add the `docs/` pages listed above.
- Update parent `README.md`, `docs/INDEX.md`, `dev/docs/RELEASE.md`, and any
  command-surface docs that mention `INSTRUCTIONS.md`.
- Delete `.factory` after salvaging useful content.

### 3. Design Contract Metadata

- Add `artboard-policy.json` and classify every live non-exported Paper
  artboard.
- Add initial `design-contract.json` for high-value surfaces:
  `AppHeader`, `Button`, `Card`, `Input`, `Modal`, `Badge`, dashboard state
  cards, and profile/recovery/rotation flow panels.
- Extend verification so unknown live artboards fail.
- Verify contract paths and implementation paths where status requires them.

### 4. Generated Artifact Contract

- Add `generated-manifest.json`.
- Add generated-file banners where practical.
- Teach export to write/update the manifest.
- Teach verify to check manifest coverage and stale generated files.
- Ensure cleanup never removes hand-authored docs or metadata.

### 5. Path Hard Cut

- Rename `design-system/` to `design/`.
- Update `artboard-map.json` output paths.
- Update exporter, verifier, generated references, docs, token paths, glossary
  paths, and root docs.
- Remove all `design-system/` assumptions from active code and docs except
  historical reports/plans where preserving history is useful.
- Do not leave compatibility paths or aliases.

### 6. Token And UI Integration

- Keep Foundations-derived tokens canonical.
- Keep usage coverage as an explicit allowance for non-Foundation prototype
  values.
- Document promotion rules: repeated canonical values move to Foundations;
  values without semantic purpose are removed or redesigned.
- Later, add a script-driven token sync into `igloo-ui` as committed artifacts.
  `igloo-ui` must not read `igloo-paper` at runtime.

## Verification

The implementation is acceptable when:

- `make igloo-paper-sync` passes with strict drift by default.
- `make igloo-paper-sync STRICT=0` runs export plus non-strict verification.
- `make igloo-paper-verify STRICT=1` still passes.
- `npm --prefix test run test:guards` passes once unrelated missing submodule
  link targets are resolved or initialized.
- No tracked or untracked Python bytecode/cache artifacts remain after public
  commands.
- `repos/igloo-paper/INSTRUCTIONS.md` and `repos/igloo-paper/.factory` are gone.
- No active docs reference `repos/igloo-paper/INSTRUCTIONS.md`.
- No active export path uses `design-system/`.
- Every live Paper artboard is exported or classified.
- Every generated file is manifest-tracked.
- `design-contract.json` validates and points to existing implementation paths
  for implemented/in-progress entries.

## Non-Goals

- Do not generate production `igloo-ui` React components from Paper.
- Do not make app builds depend on Paper Desktop, Paper MCP, or `igloo-paper`.
- Do not add screenshot-diff automation until the design contract is stable.
- Do not preserve legacy path aliases, compatibility stubs, or Factory-specific
  worker procedures.
