# igloo-home Unsigned Release Artifacts Design

_Status: Approach approved 2026-06-27 - pending implementation plan._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` Phase 3._

> **For agentic workers:** this is a small feature design. The implementation
> plan should keep generated artifacts under `./.tmp/`, avoid signing or
> notarization work, and preserve the root `make` command surface as the public
> entrypoint.

## Problem

`igloo-home` is the desktop beta vertical. The original Phase 3 map treated a
signed and notarized macOS installer as the beta gate, but the current beta plan
now intentionally stops earlier: prove that Home can produce reviewable unsigned
release artifacts with reproducible checksums, then defer signing and fuller
Linux packaging until after beta.

Current `HEAD` narrows the Home risk profile:

- C1 recovered-secret masking is closed in the Home recovery view:
  `repos/igloo-home/src/pages/RecoverKeyPage.tsx` renders recovered `nsec` and
  signing key material through `SensitiveTextarea`, and frontend tests cover
  masked/reveal/scrub behavior.
- C9 lock-panic hardening is substantially closed: production Tauri paths use
  `lock_safe` / `lock_recover`; remaining `lock().unwrap()` hits are confined
  to tests or environment-test helpers.
- `repos/igloo-home/src-tauri/Cargo.toml` already uses `edition = "2024"`,
  which should be verified against the pinned toolchain rather than downgraded.

The remaining agent-doable Phase 3 work is therefore release-shape plumbing:
build a local primitive that stages unsigned macOS and Linux AppImage artifacts
with checksums and metadata, so a future GitHub Actions workflow can upload the
same staged directory.

## Goal

Add a parent-owned unsigned packaging primitive for `igloo-home` that:

- builds or consumes the normal Tauri release output instead of inventing a
  bespoke package path;
- stages generated artifacts under
  `./.tmp/release/igloo-home/<version>/`;
- supports the current host platform only:
  - macOS stages the unsigned macOS Tauri artifact produced on macOS;
  - Linux stages the unsigned `.AppImage` only;
- writes checksums and a small manifest describing the staged candidate;
- fails clearly for version mismatches, missing artifacts, unsupported
  platforms, or ambiguous output;
- is exposed through a root `make` target so future CI can call one supported
  command.

## Chosen Approach

Add a root release primitive: a parent script, called by a `Makefile` target,
that owns staging and checksum generation for Home artifacts.

The parent repo already owns coordinated release process and public command
surfaces. Keeping this primitive in the parent preserves that boundary:
`repos/igloo-home` remains the Tauri app/package owner, while the parent owns
release staging, checksums, and future upload automation.

The primitive should create a clean staging directory under
`./.tmp/release/igloo-home/<version>/`, copy only supported artifacts for the
current OS, write `SHA256SUMS`, and write `manifest.json` with at least:

- client name (`igloo-home`);
- package version;
- platform and target family;
- parent commit;
- `repos/igloo-home` commit;
- artifact filenames;
- SHA-256 digest for each artifact;
- generated timestamp.

The future GitHub Actions release workflow should be able to run the same root
target and upload the staged directory without reimplementing selection or
checksum logic.

## Alternatives Rejected

**Repo-local `npm run package:release`.** This keeps logic near the Tauri app,
but it puts coordinated release staging inside a client submodule and still
requires a parent wrapper later. The parent repo is the release coordinator, so
the primitive should live at the layer that will upload and record artifacts.

**CI-first release workflow.** A workflow would be closer to the final release
shape, but it mixes local artifact discipline with tag semantics, permissions,
draft-release behavior, and upload policy. The primitive should be proven
locally first, then the workflow can call it.

**Signed macOS installer as the first target.** Better for a mature release, but
too much for this beta unit. Developer ID enrollment, certificate management,
notarization credentials, and staple checks are deferred backlog work.

## Scope

In scope:

1. Root command, likely `make igloo-home-package-release`.
2. Root script, likely `scripts/igloo-home-package-release.sh`.
3. Version consistency check between `repos/igloo-home/package.json` and
   `repos/igloo-home/src-tauri/tauri.conf.json`.
4. Build/stage flow using the existing Tauri release output.
5. Platform-specific artifact selection:
   - macOS: unsigned Tauri macOS artifact;
   - Linux: AppImage only.
6. Checksum generation and manifest generation.
7. Focused tests for version checks, artifact selection, missing artifacts, and
   checksum/manifest output.
8. Workspace release docs and Home changelog updates explaining the unsigned
   beta artifact primitive.

Out of scope:

- Developer ID signing and notarization.
- Staple validation.
- Windows packaging.
- Linux `.deb` / `.rpm` packaging.
- Auto-update.
- GitHub Actions release workflow.
- Uploading or publishing a GitHub Release.

## Deferred Follow-Ups

Record these as backlog items when the implementation plan lands or the first
implementation task executes:

- **Signed macOS DMG after beta:** Developer ID signing, notarization, staple
  validation, and credential documentation.
- **Linux deb/rpm after beta:** package formats beyond AppImage.
- **GitHub Actions release workflow:** run the root primitive and upload the
  staged directory to a draft release.

## Mechanism

The root script should:

1. Derive `ROOT_DIR` from its own path and set strict Bash options.
2. Read the Home version from both:
   - `repos/igloo-home/package.json`;
   - `repos/igloo-home/src-tauri/tauri.conf.json`.
3. Fail if the versions disagree.
4. Build through the existing Tauri release path or accept a test-only fixture
   mode for script tests.
5. Create a clean staging directory:
   `./.tmp/release/igloo-home/<version>/`.
6. Detect the host OS:
   - `Darwin` -> select the supported unsigned macOS artifact;
   - `Linux` -> select one `.AppImage`;
   - anything else -> fail as unsupported for this unit.
7. Fail if no supported artifact exists or if artifact selection is ambiguous.
8. Copy selected artifacts into the staging directory.
9. Generate checksums with the platform-available SHA-256 tool
   (`shasum -a 256` or `sha256sum`).
10. Write `SHA256SUMS` and `manifest.json`.
11. Print the staging directory path on success.

The implementation should keep testability in mind. The artifact-selection and
manifest logic can be factored into shell helpers, or the script can expose
environment overrides for fixture roots and OS names so tests do not need to run
real Tauri builds.

## Validation

Focused primitive tests:

- version mismatch fails before staging;
- unsupported OS fails clearly;
- missing artifact fails clearly;
- Linux fixture with one AppImage stages exactly that AppImage;
- Linux fixture with multiple AppImages fails as ambiguous;
- manifest and `SHA256SUMS` include the staged artifact and correct digest.

Real checks for the implementation unit:

- `make igloo-home-build`;
- `make igloo-home-test-unit`;
- `make igloo-home-package-release` on the current host when local toolchain
  support permits;
- `npm --prefix test run test:guards:docs` after release-doc updates.

The beta primitive does not require notarization, `stapler`, release upload, or
GitHub Actions validation.

## Done When

- The approved root command can stage Home release artifacts for the current
  host under `./.tmp/release/igloo-home/<version>/`.
- The staged directory contains the supported artifact(s), `SHA256SUMS`, and
  `manifest.json`.
- Focused tests cover the failure modes above.
- Workspace release docs identify this as the unsigned beta primitive and keep
  signed macOS DMG, deb/rpm, and GitHub Actions upload work deferred.
- The Home submodule and parent workspace are committed in the correct order if
  both layers change.
