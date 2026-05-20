# Igloo Paper MCP Design-System Sync Investigation

Date: 2026-05-20

## Summary

`repos/igloo-paper` is in good shape as a static reference export of the live Paper Desktop file. The Paper MCP connection is healthy, the checked-in export reconciles with the live `igloo-ui-shared` file on the `core` page, and both normal and strict drift verification pass.

The current process is usable for maintainers, but it is not yet a strong onboarding path for new developers. The main gaps are:

- the export workflow is documented, but experimenting in Paper before export is not described as a safe, reviewable loop
- `make igloo-paper-verify` exists, but there is no root `make` target for the export step
- 20 live Paper artboards are not mapped for export, including several screen states that may be product-relevant
- one hand-authored design-system note, `design-system/components/navigation-layout/app-header.md`, references stale Paper node IDs
- generated docs and hand-maintained docs are not clearly labeled, which makes it easy for contributors to edit generated output directly

No Paper canvas mutations were made during this investigation.

## Evidence

Local repository state:

- Parent repo: `/Users/cscott/Repos/frostr/frostr-infra`
- Paper submodule: `repos/igloo-paper` at `be9efbc4ed3cb905a34926f990437be8266330e9`
- `repos/igloo-paper` working tree: clean
- Existing report path was untracked before this rewrite: `dev/reports/igloo-ui-paper-design-system-investigation-2026-05-20.md`

Paper MCP state:

- Paper file: `igloo-ui-shared`
- Page: `core`
- Node count: 14,968
- Live artboards: 90
- Current selection: none
- Export map entries: 71 total entries, of which 70 are exported artboards and 1 is a divider
- Export categories verified by `scripts/verify.py`: 24 design-system entries, 46 screen entries, 1 divider entry

Verification commands run:

```bash
python3 scripts/verify.py
python3 scripts/verify.py --strict-drift
make igloo-paper-verify STRICT=1
```

All three passed after allowing localhost access to Paper MCP. The sandboxed first attempts failed with `PermissionError: [Errno 1] Operation not permitted` because local socket access to `127.0.0.1:29979` was blocked, not because Paper MCP was unhealthy.

Passing verifier output:

```text
Drift summary: colors=0 fonts=0 typography=0 unused_coverage_colors=0 unused_coverage_typography=0
PASS: structural export checks passed, metadata curation checks passed, and Paper reconciliation succeeded.
```

## Current Design Source Model

The source of truth is the live Paper Desktop canvas:

- file: `igloo-ui-shared`
- page: `core`
- MCP endpoint expected by scripts: `http://127.0.0.1:29979/mcp`

`repos/igloo-paper` is the static snapshot and review artifact, not a runtime dependency. This matches the root workspace rule: Paper references must stay in `repos/igloo-paper` and must not be imported into runtime code, package code, or app builds.

The export pipeline is:

1. `artboard-map.json` declares which Paper artboards are exported and where they land.
2. `export-metadata.json` curates generated README labels, descriptions, and related-screen groupings.
3. `scripts/export_from_paper.py` calls Paper MCP, extracts JSX/screenshots/tokens, localizes Paper assets, and writes generated artifacts.
4. `scripts/verify.py` checks output structure, README curation, stale path absence, localized assets, PNG signatures, canonical screen roots, footer contract, live Paper reconciliation, and token drift.
5. `scripts/verify.py --strict-drift` upgrades color and typography drift to failure.

Generated artifacts include:

- `design-system/tokens/colors.json`
- `design-system/tokens/typography.json`
- `design-system/tokens/tokens.css`
- `design-system/tokens/usage-coverage.json`
- `design-system/**/README.md`
- `design-system/**/reference.html`
- `design-system/**/screenshot.png`
- `screens/**/README.md`
- `screens/**/screen.html`
- `screens/**/screenshot.png`
- `screens/_shared/app-header.html`
- `screens/_shared/app-footer.html`
- `assets/paper/*`

## What Works Well

The sync scripts have a clear, deterministic contract. `export_from_paper.py` centralizes token extraction, JSX export, screenshot export, README generation, glossary handling, shared header/footer export, asset localization, font canonicalization, and footer canonicalization.

The verifier is stronger than a simple file-presence check. It reconciles mapped artboard IDs against the live Paper file, blocks stale screen directories, verifies curated README metadata, catches remote Paper asset URLs, enforces the canonical app footer contract, and detects design-token drift.

The repository-level ownership model is clear. Root docs and `CONTRIBUTING.md` consistently say that `igloo-paper` is reference-only, while `igloo-ui` owns reusable presentation and product repos own runtime/app wiring.

The Foundations token model is intentionally bounded. Tokens are generated from the Foundations artboard only, while `usage-coverage.json` records allowed non-Foundation prototype values. This gives maintainers a path to distinguish canonical tokens from transitional usage.

## Findings

### 1. MCP Connection Is Healthy

The live Paper file is reachable through MCP. `get_basic_info` reported the expected `igloo-ui-shared` file and `core` page, and the verifier successfully initialized the MCP session, queried live artboards, and reconciled the export map.

Impact: design-system syncing can proceed. Local automation that talks to Paper MCP needs localhost/network permission in sandboxed agent environments.

### 2. Exported Scope Does Not Cover Every Live Artboard

The live Paper page has 90 artboards. `artboard-map.json` maps 70 exported artboards plus one divider, leaving 20 live artboards unmapped:

- `3QR-0` — Igloo Web App Screens —
- `4PE-0` Web — Dashboard — 1d. Recover
- `4SG-0` Web — Dashboard — 1e. Recover Success
- `5O7-0` Web — Dashboard — 3c. Unsaved Changes (Modal)
- `7Q9-0` Web — Dashboard — 1b Error. Profile Load Failed
- `8V1-0` Web — Onboard Sponsor — 1. Configure Device
- `8XC-0` Web — Onboard Sponsor — 2. Package Handoff
- `8YU-0` Web — Onboard Sponsor — 2b. Device Onboarded
- `90C-0` Web — Onboard Sponsor — 2c. Onboarding Failed
- `91U-0` Web — Onboard Sponsor — 2d. Cancel Confirm (Modal)
- `AIH-0` Onboard Sponsor Flow Sections
- `AO3-0` Welcome Flow Sections
- `AT6-0` Create Keyset Flow Sections
- `AYG-0` Onboard Flow Sections
- `B3Y-0` Import Flow Sections
- `B8N-0` Replace Share Flow Sections
- `BCO-0` Row Label — Onboard Sponsor
- `BCR-0` Row Label — Onboard Recipient
- `BI4-0` Recover Flow Sections
- `BR8-0` Row Label — Import

Some unmapped boards are clearly organizational, but several are screen states. New developers need to know whether these are intentionally excluded, newly added but not synced, or deprecated.

Recommendation: add an explicit ignored-artboards list to `export-metadata.json` or a separate `artboard-policy.json`, then make `verify.py` fail when a live artboard is neither exported nor intentionally ignored.

### 3. `app-header.md` Has Stale Paper IDs

`repos/igloo-paper/design-system/components/navigation-layout/app-header.md` references old node IDs such as `34C-0`, `6MP-0`, `H4X-0`, `QI3-0`, `3QW-0`, `DCI-0`, and `518-0`. These do not appear in the current `artboard-map.json` or live Paper page.

Impact: this is the most concrete onboarding hazard found. A new developer following this document would not be able to map those references to the current Paper canvas.

Recommendation: either regenerate this document from current map metadata, update it manually to current IDs, or move durable component guidance out of node-ID-specific prose.

### 4. Generated And Hand-Maintained Files Need Clearer Boundaries

`INSTRUCTIONS.md` says README curation belongs in `export-metadata.json`, which is good. Generated `README.md` files do not all carry an obvious generated-file warning, and hand-authored supporting docs sit alongside generated artifacts.

Impact: contributors may hand-edit generated files and lose work on the next export.

Recommendation: add a short generated header to generated `README.md`, `reference.html`, `screen.html`, token files, and glossary markdown where practical. Also document which files are safe to edit directly:

- safe: `artboard-map.json`, `export-metadata.json`, `README.md`, `INSTRUCTIONS.md`, scripts
- generated: exported screen/design-system HTML, screenshots, token outputs, generated READMEs/glossary files
- hand-maintained exception: `design-system/components/navigation-layout/app-header.md`, if kept

### 5. Root Command Surface Is Verify-Only

The root `Makefile` exposes `make igloo-paper-verify [STRICT=1]`, and that wrapper works. The export command remains submodule-local:

```bash
cd repos/igloo-paper
python3 scripts/export_from_paper.py
```

Impact: this is acceptable for maintainers, but weaker for onboarding because root docs say `make` is the public interface and root scripts are private implementation detail.

Recommendation: add a root `make igloo-paper-sync` target that runs the exporter from `repos/igloo-paper`, then a strict verifier. Keep it out of default test/release lanes because it requires Paper Desktop.

### 6. Experimentation Workflow Is Under-Documented

The current runbook explains how to resync, but not how to safely experiment in Paper Desktop through MCP and turn an experiment into a repo change.

Recommended documented loop:

1. Open Paper Desktop to `igloo-ui-shared` / `core`.
2. Confirm the current selection and target artboard.
3. Duplicate or create an experimental artboard instead of editing canonical boards immediately.
4. Make Paper edits through MCP or directly in Paper.
5. Review visually in Paper Desktop.
6. Decide whether the experiment graduates to canonical design-system or screen coverage.
7. Update `artboard-map.json` for new exported boards, or the ignored-artboards policy for intentionally unexported boards.
8. Run export.
9. Review generated diff.
10. Run strict verification.
11. Commit the `repos/igloo-paper` submodule change, then update the parent submodule pointer when appropriate.

### 7. Token Governance Is Good But Needs A Promotion Rule

The current token split is sensible:

- Foundations tokens are canonical.
- Non-Foundation values are tracked in `usage-coverage.json`.
- Strict drift catches undocumented values.

The missing piece is a promotion rule. When a non-Foundation value repeats across real components or screens, contributors need guidance on whether to:

- add it to Foundations as a canonical token,
- keep it as usage coverage because it is a one-off prototype treatment,
- or remove it from the design.

Recommendation: add a small "Token Promotion Policy" section to `INSTRUCTIONS.md`.

## Recommended Onboarding Documentation

Add a contributor-facing `repos/igloo-paper/docs/onboarding.md` or expand `INSTRUCTIONS.md` with these sections:

- Mental model: live Paper canvas is source of truth; repo is generated static reference
- Prerequisites: Paper Desktop open, `igloo-ui-shared` file, `core` page, MCP endpoint, Python 3.9+
- Safe experimentation: duplicate first, avoid mutating canonical artboards until reviewed
- Export map: when to update `artboard-map.json`
- Curation metadata: when to update `export-metadata.json`
- Generated files: what not to hand-edit
- Token policy: Foundations vs usage coverage vs strict drift
- Validation: `make igloo-paper-verify STRICT=1`
- Review checklist: inspect generated screenshots, HTML/reference changes, token diffs, and README changes
- Parent/submodule workflow: commit inside `repos/igloo-paper`, then update the parent submodule pointer

## Suggested Process Improvements

1. Add `make igloo-paper-sync`.

   Suggested behavior:

   ```bash
   cd repos/igloo-paper
   python3 scripts/export_from_paper.py
   python3 scripts/verify.py --strict-drift
   ```

2. Add live-artboard policy enforcement.

   `verify.py` should report unmapped live artboards and require each one to be either exported or intentionally ignored with a reason.

3. Fix or regenerate `app-header.md`.

   This should happen before using the current docs to onboard someone new.

4. Add generated-file banners.

   This reduces accidental edits to generated artifacts.

5. Add a "design experiment" runbook.

   Make the MCP workflow explicit: inspect selection, duplicate/edit, review, export, verify, commit.

6. Add a report-friendly export summary.

   After `export_from_paper.py`, print counts for exported artboards, generated screenshots, localized assets, token counts, and skipped/ignored live artboards.

7. Consider a dry-run mode.

   A `scripts/export_from_paper.py --dry-run` mode could validate Paper connectivity and planned outputs without writing generated artifacts.

## Proposed Next Steps

1. Update `app-header.md` or replace it with generated/current references.
2. Add an ignored-artboards policy and wire it into `verify.py`.
3. Add `make igloo-paper-sync` as the public root sync command.
4. Expand `repos/igloo-paper/INSTRUCTIONS.md` into a full onboarding runbook.
5. After those docs/process changes, run a small Paper MCP experiment on a duplicated artboard and sync it through the repo to validate the complete loop.

## Open Questions

- Should the dashboard recover, recover-success, unsaved-changes, profile-load-failed, and onboard-sponsor screens be exported as canonical screen references?
- Should section-composition artboards such as `Welcome Flow Sections` and `Create Keyset Flow Sections` become design-system pattern references, or remain internal Paper working boards?
- Should Paper MCP experiments be committed only after human visual review in Paper Desktop, or is screenshot review from `repos/igloo-paper` sufficient for small changes?
- Should `usage-coverage.json` be edited manually, generated from a baseline command, or curated through a dedicated token-promotion review?
