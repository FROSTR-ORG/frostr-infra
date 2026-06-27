# igloo-home Unsigned Release Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a root-owned primitive that stages unsigned `igloo-home` macOS DMG or Linux AppImage artifacts under `./.tmp/release/igloo-home/<version>/` with checksums and a machine-readable manifest.

**Architecture:** `repos/igloo-home` remains the Tauri app/package owner; the parent workspace owns coordinated release staging. A root Bash script validates Home metadata, optionally runs the normal Tauri build, selects the one supported host artifact, copies it into parent scratch, and writes checksum/manifest files. Fixture-driven shell tests exercise selection and failure modes without running Tauri.

**Tech Stack:** Bash, Makefile, `jq`, Tauri CLI via `npm --prefix repos/igloo-home run tauri -- build`, `sha256sum`/`shasum -a 256`, existing `test/scripts` guard conventions.

---

## Source Design

Approved design: [`dev/plans/igloo-home-unsigned-release-artifacts-2026-06-27-design.md`](./igloo-home-unsigned-release-artifacts-2026-06-27-design.md)

## Global Constraints

- Generated artifacts must stay under `./.tmp/release/igloo-home/<version>/`.
- Do not add signing, notarization, Windows packaging, Linux deb/rpm packaging, auto-update, or GitHub Actions upload behavior in this unit.
- Preserve `Makefile` as the public root command surface; scripts remain private implementation detail behind `make`.
- Use non-recursive submodule workflow. If `repos/igloo-home/CHANGELOG.md` changes, commit inside `repos/igloo-home` first, then commit the parent pointer and parent docs/scripts.
- Do not use `git add -A`.
- Browser/Desktop lanes that launch GUI apps may need unsandboxed execution on macOS; the shell fixture tests should stay sandbox-safe.

## File Structure

Create:

- `scripts/igloo-home-package-release.sh` — root-owned release primitive.
- `test/scripts/test-igloo-home-package-release.sh` — fixture tests for the primitive.

Modify:

- `Makefile` — add `igloo-home-package-release` to `.PHONY`, help, and target list.
- `test/package.json` — add `test:guards:home-package`; include it in `test:guards:home` and `test:guards:full`.
- `test/scripts/test-run-sh.sh` — assert the new root target delegates to the new script and appears in help.
- `test/scripts/check-doc-command-surfaces.sh` — include the new root command in the guarded root command surface.
- `README.md` — list the new root command in the common command surface.
- `dev/docs/RELEASE.md` — document Home unsigned artifact/checksum primitive.
- `dev/docs/2026-06-26-public-beta-release-plan.md` — adjust Phase 3 gate from signed/notarized beta gate to unsigned artifact/checksum beta primitive, with signing deferred.
- `dev/docs/GOTCHAS.md` — add a release packaging gotcha for Home unsigned beta artifacts versus signed/notarized post-beta artifacts.
- `dev/BACKLOG.md` — record deferred signed macOS DMG, Linux deb/rpm, and GitHub Actions release workflow follow-ups.
- `repos/igloo-home/CHANGELOG.md` — add an `[Unreleased]` entry for the unsigned artifact/checksum release primitive.

## Target Script Contract

`scripts/igloo-home-package-release.sh` should support these environment overrides for tests:

- `IGLOO_HOME_PACKAGE_HOME_DIR` — alternate Home repo root; default `repos/igloo-home`.
- `IGLOO_HOME_PACKAGE_BUNDLE_DIR` — alternate Tauri bundle output root; default `${HOME_DIR}/src-tauri/target/release/bundle`.
- `IGLOO_HOME_PACKAGE_STAGE_ROOT` — alternate staging root; default `${ROOT_DIR}/.tmp/release/igloo-home`.
- `IGLOO_HOME_PACKAGE_OS` — alternate OS name; default `uname -s`.
- `IGLOO_HOME_PACKAGE_SKIP_BUILD=1` — skip real Tauri build for fixture tests.
- `IGLOO_HOME_PACKAGE_TIMESTAMP` — deterministic manifest timestamp for tests.
- `IGLOO_HOME_PACKAGE_PARENT_COMMIT` — deterministic parent commit for tests.
- `IGLOO_HOME_PACKAGE_HOME_COMMIT` — deterministic Home commit for tests.

Default artifact selection:

- macOS (`Darwin`): exactly one `*.dmg` under `${BUNDLE_DIR}/dmg/`.
- Linux (`Linux`): exactly one `*.AppImage` under `${BUNDLE_DIR}/appimage/`.
- Other OS values fail clearly.

Manifest shape:

```json
{
  "client": "igloo-home",
  "version": "0.2.0",
  "platform": "linux",
  "targetFamily": "appimage",
  "parentCommit": "abc123",
  "homeCommit": "def456",
  "generatedAt": "2026-06-27T00:00:00Z",
  "artifacts": [
    {
      "file": "Igloo Home_0.2.0_amd64.AppImage",
      "sha256": "..."
    }
  ]
}
```

## Task 1: Add Red Fixture Tests For The Packaging Primitive

**Files:**
- Create: `test/scripts/test-igloo-home-package-release.sh`
- Modify: `test/package.json`

- [ ] **Step 1: Create the failing shell test**

Create `test/scripts/test-igloo-home-package-release.sh` with fixture helpers that invoke the not-yet-created `scripts/igloo-home-package-release.sh`.

Use this exact test structure:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/igloo-home-package-release.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

fail() {
  echo "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}', got: ${haystack}"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

write_home_fixture() {
  local root="$1"
  local package_version="$2"
  local tauri_version="$3"
  mkdir -p "${root}/src-tauri"
  jq -n --arg version "${package_version}" '{name:"igloo-home",version:$version}' >"${root}/package.json"
  jq -n --arg version "${tauri_version}" '{productName:"Igloo Home",version:$version}' >"${root}/src-tauri/tauri.conf.json"
}

run_package_script() {
  local home_dir="$1"
  local bundle_dir="$2"
  local stage_root="$3"
  local os_name="$4"
  shift 4
  IGLOO_HOME_PACKAGE_HOME_DIR="${home_dir}" \
    IGLOO_HOME_PACKAGE_BUNDLE_DIR="${bundle_dir}" \
    IGLOO_HOME_PACKAGE_STAGE_ROOT="${stage_root}" \
    IGLOO_HOME_PACKAGE_OS="${os_name}" \
    IGLOO_HOME_PACKAGE_SKIP_BUILD=1 \
    IGLOO_HOME_PACKAGE_TIMESTAMP="2026-06-27T00:00:00Z" \
    IGLOO_HOME_PACKAGE_PARENT_COMMIT="parent-fixture" \
    IGLOO_HOME_PACKAGE_HOME_COMMIT="home-fixture" \
    "${SCRIPT}" "$@"
}

expect_fail_contains() {
  local expected="$1"
  shift
  set +e
  local output
  output="$("$@" 2>&1)"
  local status=$?
  set -e
  if [[ ${status} -eq 0 ]]; then
    fail "expected command to fail: $*"
  fi
  assert_contains "${output}" "${expected}"
}

portable_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  else
    shasum -a 256 "${path}" | awk '{print $1}'
  fi
}

test_version_mismatch_fails() {
  local home="${TMP_DIR}/version-mismatch/home"
  local bundle="${TMP_DIR}/version-mismatch/bundle"
  local stage="${TMP_DIR}/version-mismatch/stage"
  write_home_fixture "${home}" "0.2.0" "0.3.0"
  mkdir -p "${bundle}/appimage"
  printf 'appimage' >"${bundle}/appimage/Igloo Home_0.2.0_amd64.AppImage"
  expect_fail_contains "version mismatch: package.json=0.2.0 tauri.conf.json=0.3.0" \
    run_package_script "${home}" "${bundle}" "${stage}" "Linux"
}

test_unsupported_os_fails() {
  local home="${TMP_DIR}/unsupported/home"
  local bundle="${TMP_DIR}/unsupported/bundle"
  local stage="${TMP_DIR}/unsupported/stage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  printf 'appimage' >"${bundle}/appimage/Igloo Home_0.2.0_amd64.AppImage"
  expect_fail_contains "unsupported igloo-home release OS: Plan9" \
    run_package_script "${home}" "${bundle}" "${stage}" "Plan9"
}

test_missing_appimage_fails() {
  local home="${TMP_DIR}/missing/home"
  local bundle="${TMP_DIR}/missing/bundle"
  local stage="${TMP_DIR}/missing/stage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  expect_fail_contains "expected exactly one AppImage artifact" \
    run_package_script "${home}" "${bundle}" "${stage}" "Linux"
}

test_ambiguous_appimage_fails() {
  local home="${TMP_DIR}/ambiguous/home"
  local bundle="${TMP_DIR}/ambiguous/bundle"
  local stage="${TMP_DIR}/ambiguous/stage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  printf 'one' >"${bundle}/appimage/one.AppImage"
  printf 'two' >"${bundle}/appimage/two.AppImage"
  expect_fail_contains "expected exactly one AppImage artifact" \
    run_package_script "${home}" "${bundle}" "${stage}" "Linux"
}

test_linux_appimage_stages_manifest_and_checksum() {
  local home="${TMP_DIR}/linux/home"
  local bundle="${TMP_DIR}/linux/bundle"
  local stage="${TMP_DIR}/linux/stage"
  local artifact="Igloo Home_0.2.0_amd64.AppImage"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/appimage"
  printf 'linux-appimage-fixture' >"${bundle}/appimage/${artifact}"

  local output
  output="$(run_package_script "${home}" "${bundle}" "${stage}" "Linux")"
  local staged_dir="${stage}/0.2.0"
  assert_contains "${output}" "${staged_dir}"
  assert_file_exists "${staged_dir}/${artifact}"
  assert_file_exists "${staged_dir}/SHA256SUMS"
  assert_file_exists "${staged_dir}/manifest.json"

  local digest
  digest="$(portable_sha256 "${staged_dir}/${artifact}")"
  assert_contains "$(cat "${staged_dir}/SHA256SUMS")" "${digest}  ${artifact}"
  [[ "$(jq -r '.client' "${staged_dir}/manifest.json")" == "igloo-home" ]] || fail "manifest client mismatch"
  [[ "$(jq -r '.version' "${staged_dir}/manifest.json")" == "0.2.0" ]] || fail "manifest version mismatch"
  [[ "$(jq -r '.platform' "${staged_dir}/manifest.json")" == "linux" ]] || fail "manifest platform mismatch"
  [[ "$(jq -r '.targetFamily' "${staged_dir}/manifest.json")" == "appimage" ]] || fail "manifest targetFamily mismatch"
  [[ "$(jq -r '.artifacts[0].file' "${staged_dir}/manifest.json")" == "${artifact}" ]] || fail "manifest artifact mismatch"
  [[ "$(jq -r '.artifacts[0].sha256' "${staged_dir}/manifest.json")" == "${digest}" ]] || fail "manifest digest mismatch"
}

test_darwin_dmg_stages_manifest_and_checksum() {
  local home="${TMP_DIR}/darwin/home"
  local bundle="${TMP_DIR}/darwin/bundle"
  local stage="${TMP_DIR}/darwin/stage"
  local artifact="Igloo Home_0.2.0_aarch64.dmg"
  write_home_fixture "${home}" "0.2.0" "0.2.0"
  mkdir -p "${bundle}/dmg"
  printf 'darwin-dmg-fixture' >"${bundle}/dmg/${artifact}"

  run_package_script "${home}" "${bundle}" "${stage}" "Darwin" >/dev/null
  local staged_dir="${stage}/0.2.0"
  assert_file_exists "${staged_dir}/${artifact}"
  [[ "$(jq -r '.platform' "${staged_dir}/manifest.json")" == "macos" ]] || fail "manifest platform mismatch"
  [[ "$(jq -r '.targetFamily' "${staged_dir}/manifest.json")" == "dmg" ]] || fail "manifest targetFamily mismatch"
}

test_version_mismatch_fails
test_unsupported_os_fails
test_missing_appimage_fails
test_ambiguous_appimage_fails
test_linux_appimage_stages_manifest_and_checksum
test_darwin_dmg_stages_manifest_and_checksum

echo "ok: igloo-home package release primitive"
```

- [ ] **Step 2: Wire a test script name**

Modify `test/package.json`:

- add `"test:guards:home-package": "bash ./scripts/test-igloo-home-package-release.sh"`;
- prepend `npm run test:guards:home-package &&` to `test:guards:home`;
- add `npm run test:guards:home-package &&` in `test:guards:full` before `bash ./scripts/test-igloo-home-run-e2e.sh`.

- [ ] **Step 3: Run the new test and confirm it fails for the right reason**

Run:

```bash
npm --prefix test run test:guards:home-package
```

Expected: FAIL because `scripts/igloo-home-package-release.sh` does not exist or is not executable.

## Task 2: Implement The Release Packaging Script

**Files:**
- Create: `scripts/igloo-home-package-release.sh`
- Test: `test/scripts/test-igloo-home-package-release.sh`

- [ ] **Step 1: Create the root script**

Create `scripts/igloo-home-package-release.sh` with strict Bash settings and the helper boundaries below:

```bash
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${IGLOO_HOME_PACKAGE_HOME_DIR:-${ROOT_DIR}/repos/igloo-home}"
BUNDLE_DIR="${IGLOO_HOME_PACKAGE_BUNDLE_DIR:-${HOME_DIR}/src-tauri/target/release/bundle}"
STAGE_ROOT="${IGLOO_HOME_PACKAGE_STAGE_ROOT:-${ROOT_DIR}/.tmp/release/igloo-home}"
OS_NAME="${IGLOO_HOME_PACKAGE_OS:-$(uname -s)}"
SKIP_BUILD="${IGLOO_HOME_PACKAGE_SKIP_BUILD:-0}"
GENERATED_AT="${IGLOO_HOME_PACKAGE_TIMESTAMP:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing required file: ${path}"
}

read_json_string() {
  local file="$1"
  local filter="$2"
  jq -er "${filter}" "${file}"
}

home_version() {
  local package_json="${HOME_DIR}/package.json"
  local tauri_conf="${HOME_DIR}/src-tauri/tauri.conf.json"
  require_file "${package_json}"
  require_file "${tauri_conf}"

  local package_version
  local tauri_version
  package_version="$(read_json_string "${package_json}" '.version')"
  tauri_version="$(read_json_string "${tauri_conf}" '.version')"

  if [[ "${package_version}" != "${tauri_version}" ]]; then
    fail "version mismatch: package.json=${package_version} tauri.conf.json=${tauri_version}"
  fi

  printf '%s\n' "${package_version}"
}

git_commit_or_override() {
  local override="$1"
  local dir="$2"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
  else
    git -C "${dir}" rev-parse --short=12 HEAD
  fi
}

platform_info() {
  case "${OS_NAME}" in
    Darwin)
      printf '%s\t%s\t%s\n' "macos" "dmg" "${BUNDLE_DIR}/dmg/*.dmg"
      ;;
    Linux)
      printf '%s\t%s\t%s\n' "linux" "appimage" "${BUNDLE_DIR}/appimage/*.AppImage"
      ;;
    *)
      fail "unsupported igloo-home release OS: ${OS_NAME}"
      ;;
  esac
}

select_one_artifact() {
  local glob_pattern="$1"
  local label="$2"
  local matches=()
  shopt -s nullglob
  matches=(${glob_pattern})
  shopt -u nullglob

  if [[ ${#matches[@]} -ne 1 ]]; then
    fail "expected exactly one ${label} artifact matching ${glob_pattern}, found ${#matches[@]}"
  fi

  printf '%s\n' "${matches[0]}"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    fail "neither sha256sum nor shasum is available"
  fi
}

run_build() {
  if [[ "${SKIP_BUILD}" == "1" ]]; then
    return 0
  fi
  npm --prefix "${HOME_DIR}" run tauri -- build
}

write_outputs() {
  local version="$1"
  local platform="$2"
  local target_family="$3"
  local artifact_path="$4"
  local stage_dir="$5"

  rm -rf "${stage_dir}"
  mkdir -p "${stage_dir}"

  local artifact_name
  artifact_name="$(basename "${artifact_path}")"
  cp "${artifact_path}" "${stage_dir}/${artifact_name}"

  local digest
  digest="$(sha256_file "${stage_dir}/${artifact_name}")"
  printf '%s  %s\n' "${digest}" "${artifact_name}" >"${stage_dir}/SHA256SUMS"

  local parent_commit
  local home_commit
  parent_commit="$(git_commit_or_override "${IGLOO_HOME_PACKAGE_PARENT_COMMIT:-}" "${ROOT_DIR}")"
  home_commit="$(git_commit_or_override "${IGLOO_HOME_PACKAGE_HOME_COMMIT:-}" "${HOME_DIR}")"

  jq -n \
    --arg client "igloo-home" \
    --arg version "${version}" \
    --arg platform "${platform}" \
    --arg targetFamily "${target_family}" \
    --arg parentCommit "${parent_commit}" \
    --arg homeCommit "${home_commit}" \
    --arg generatedAt "${GENERATED_AT}" \
    --arg file "${artifact_name}" \
    --arg sha256 "${digest}" \
    '{
      client: $client,
      version: $version,
      platform: $platform,
      targetFamily: $targetFamily,
      parentCommit: $parentCommit,
      homeCommit: $homeCommit,
      generatedAt: $generatedAt,
      artifacts: [{file: $file, sha256: $sha256}]
    }' >"${stage_dir}/manifest.json"

  printf '%s\n' "${stage_dir}"
}

main() {
  local version
  version="$(home_version)"

  run_build

  local platform
  local target_family
  local glob_pattern
  IFS=$'\t' read -r platform target_family glob_pattern < <(platform_info)

  local label
  case "${target_family}" in
    dmg) label="DMG" ;;
    appimage) label="AppImage" ;;
    *) label="${target_family}" ;;
  esac

  local artifact_path
  artifact_path="$(select_one_artifact "${glob_pattern}" "${label}")"
  write_outputs "${version}" "${platform}" "${target_family}" "${artifact_path}" "${STAGE_ROOT}/${version}"
}

main "$@"
```

- [ ] **Step 2: Make it executable**

Run:

```bash
chmod +x scripts/igloo-home-package-release.sh
```

- [ ] **Step 3: Run the fixture tests**

Run:

```bash
npm --prefix test run test:guards:home-package
```

Expected: PASS with `ok: igloo-home package release primitive`.

## Task 3: Wire The Root Make Target And Command-Surface Guards

**Files:**
- Modify: `Makefile`
- Modify: `test/scripts/test-run-sh.sh`
- Modify: `test/scripts/check-doc-command-surfaces.sh`

- [ ] **Step 1: Add the Makefile target**

Modify `Makefile`:

- add `igloo-home-package-release` to `.PHONY` after `igloo-home-build`;
- add a help line:

```make
		'  make igloo-home-package-release' \
```

near the Home command block;

- add the target:

```make
igloo-home-package-release:
	@"$(ROOT_DIR)/scripts/igloo-home-package-release.sh"
```

near the other `igloo-home-*` targets.

- [ ] **Step 2: Update the Makefile trace test**

Modify `test/scripts/test-run-sh.sh`:

- add `assert_contains "${HELP_OUTPUT}" "make igloo-home-package-release"` near the other Home help assertions;
- add this fixture-backed target block near the Home target assertions:

```bash
HOME_PACKAGE_FIXTURE="${TRACE_DIR}/home-package"
mkdir -p \
  "${HOME_PACKAGE_FIXTURE}/home/src-tauri" \
  "${HOME_PACKAGE_FIXTURE}/bundle/appimage" \
  "${HOME_PACKAGE_FIXTURE}/stage"
printf '{"name":"igloo-home","version":"0.2.0"}\n' >"${HOME_PACKAGE_FIXTURE}/home/package.json"
printf '{"productName":"Igloo Home","version":"0.2.0"}\n' >"${HOME_PACKAGE_FIXTURE}/home/src-tauri/tauri.conf.json"
printf 'fixture-appimage' >"${HOME_PACKAGE_FIXTURE}/bundle/appimage/Igloo Home_0.2.0_amd64.AppImage"

TRACE_FILE="${TRACE_FILE}" \
  TRACE_DIR="${TRACE_DIR}" \
  ROOT_DIR="${ROOT_DIR}" \
  PATH="${TRACE_BIN_DIR}:${PATH}" \
  IGLOO_HOME_PACKAGE_HOME_DIR="${HOME_PACKAGE_FIXTURE}/home" \
  IGLOO_HOME_PACKAGE_BUNDLE_DIR="${HOME_PACKAGE_FIXTURE}/bundle" \
  IGLOO_HOME_PACKAGE_STAGE_ROOT="${HOME_PACKAGE_FIXTURE}/stage" \
  IGLOO_HOME_PACKAGE_OS="Linux" \
  IGLOO_HOME_PACKAGE_SKIP_BUILD=1 \
  IGLOO_HOME_PACKAGE_TIMESTAMP="2026-06-27T00:00:00Z" \
  IGLOO_HOME_PACKAGE_PARENT_COMMIT="parent-fixture" \
  IGLOO_HOME_PACKAGE_HOME_COMMIT="home-fixture" \
  make -s -C "${ROOT_DIR}" -f "${MAKEFILE}" igloo-home-package-release >/dev/null

assert_contains "$(cat "${HOME_PACKAGE_FIXTURE}/stage/0.2.0/SHA256SUMS")" "Igloo Home_0.2.0_amd64.AppImage"
```

- [ ] **Step 3: Update command-surface docs guard**

Modify `test/scripts/check-doc-command-surfaces.sh`:

- add `"make igloo-home-package-release"` to `root_commands`;
- add `"make igloo-home-package-release"` to the `README_FILE` command loop.

- [ ] **Step 4: Run guard tests for the root surface**

Run:

```bash
npm --prefix test run test:run-sh
npm --prefix test run test:guards:docs
```

Expected:

- `test:run-sh` passes;
- `test:guards:docs` passes or fails only because README/release docs are not updated yet. If it fails for README/release docs, keep that failure as the red signal for Task 4.

## Task 4: Update Release Docs, Backlog, And Home Changelog

**Files:**
- Modify: `README.md`
- Modify: `dev/docs/RELEASE.md`
- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
- Modify: `dev/docs/GOTCHAS.md`
- Modify: `dev/BACKLOG.md`
- Modify: `repos/igloo-home/CHANGELOG.md`

- [ ] **Step 1: Update `README.md` common commands**

Add this line in the Common commands block near the Home commands:

```bash
make igloo-home-package-release
```

- [ ] **Step 2: Update `dev/docs/RELEASE.md`**

In "Prepare the Changed Submodules", extend the `repos/igloo-home` bullet with:

```markdown
- `repos/igloo-home`
  - run the checks documented in its root docs
  - for unsigned beta desktop artifacts, run
    `make igloo-home-package-release`; it stages the current host artifact under
    `./.tmp/release/igloo-home/<version>/` with `SHA256SUMS` and
    `manifest.json`
```

If this split duplicates the existing combined bullet for Home/PWA/shared/UI,
separate Home into its own bullet and leave the others in the combined bullet.

- [ ] **Step 3: Update the public beta Phase 3 map**

In `dev/docs/2026-06-26-public-beta-release-plan.md`, change Phase 3 language so:

- signed macOS notarization is no longer the beta gate;
- beta gate requires unsigned macOS artifact or Linux AppImage staging plus checksums;
- Developer ID signing/notarization is named as deferred backlog after beta;
- Linux deb/rpm and GitHub Actions release workflow are deferred.

Concrete replacement for Phase 3 items 4-6:

```markdown
4. **Unsigned artifact primitive (beta gate).** `make igloo-home-package-release`
   stages the current host's unsigned desktop artifact under
   `./.tmp/release/igloo-home/<version>/` with `SHA256SUMS` and
   `manifest.json`. macOS stages the unsigned DMG; Linux stages AppImage only.
5. **Code signing + notarization — deferred.** Developer ID signing,
   notarization, staple validation, and certificate handling move to the
   post-beta backlog.
6. **Installer distribution — manual for beta.** Maintainers may upload the
   staged artifact/checksum directory manually. A GitHub Actions release
   workflow is deferred until after the primitive is proven.
```

Update the Phase 3 gate to:

```markdown
Home Rust + frontend tests green, unsigned artifact/checksum primitive verified
on the current host, and manual release artifacts staged under `./.tmp/release/`.
```

- [ ] **Step 4: Update `dev/docs/GOTCHAS.md`**

Add a Release Packaging bullet after the Chrome gotcha:

```markdown
- **Home beta artifacts are unsigned by design.** `make
  igloo-home-package-release` stages the current host's unsigned Tauri artifact
  plus `SHA256SUMS` and `manifest.json` under `./.tmp/release/igloo-home/`.
  macOS Developer ID signing/notarization, Linux deb/rpm packages, and GitHub
  Actions release upload are post-beta follow-ups, not prerequisites for this
  primitive.
```

- [ ] **Step 5: Add deferred backlog items**

Add these items under `## Test Harness And CI` or a more appropriate release
section if one has been added by the time this plan is executed:

```markdown
- (effort: M) Add signed macOS DMG release flow for `igloo-home` — Developer ID
  signing, notarization, staple validation, and credential documentation are
  deferred until after the unsigned beta artifact primitive ships.
- (effort: M) Add Linux deb/rpm packages for `igloo-home` — beta release only
  requires AppImage; distro-specific packages are post-beta packaging polish.
- (effort: M) Add GitHub Actions release workflow for `igloo-home` artifacts —
  run the root package primitive and upload the staged directory to a draft
  release once local artifact/checksum staging is proven.
```

Keep each backlog item on one physical line if preserving the file's existing
format is practical; otherwise keep the summary readable and do not introduce
new sections solely for these items.

- [ ] **Step 6: Update Home changelog**

In `repos/igloo-home/CHANGELOG.md`, under `[Unreleased]`, add:

```markdown
### Added
- Unsigned beta artifact staging is now coordinated by the parent workspace
  release primitive, including checksums and manifest metadata for macOS and
  Linux AppImage candidates.
```

If an `### Added` heading already exists by execution time, append the bullet
there instead of creating a duplicate heading.

- [ ] **Step 7: Run docs guard**

Run:

```bash
npm --prefix test run test:guards:docs
```

Expected: PASS.

## Task 5: Run Focused Release-Primitive Verification

**Files:**
- No new files unless a previous task failed and needs a narrow fix.

- [ ] **Step 1: Run the fixture guard**

Run:

```bash
npm --prefix test run test:guards:home-package
```

Expected: PASS.

- [ ] **Step 2: Run the Home unit gate**

Run:

```bash
make igloo-home-test-unit
```

Expected: PASS.

- [ ] **Step 3: Run the Home build gate**

Run:

```bash
make igloo-home-build
```

Expected: PASS.

- [ ] **Step 4: Run the real release primitive on the current host**

Run:

```bash
make igloo-home-package-release
```

Expected on macOS:

- exits 0 if Tauri can build an unsigned DMG locally;
- prints a staging path like `.../.tmp/release/igloo-home/0.2.0`;
- staged directory contains one `.dmg`, `SHA256SUMS`, and `manifest.json`.

Expected on Linux:

- exits 0 if Tauri can build an AppImage locally;
- prints a staging path like `.../.tmp/release/igloo-home/0.2.0`;
- staged directory contains one `.AppImage`, `SHA256SUMS`, and `manifest.json`.

If local platform dependencies prevent a real Tauri package build, record the
exact missing dependency/error in this plan and keep the fixture test as the
portable proof. Do not weaken the script's failure behavior to make a broken
local package toolchain look green.

- [ ] **Step 5: Inspect the staged manifest**

Run:

```bash
jq . .tmp/release/igloo-home/0.2.0/manifest.json
cat .tmp/release/igloo-home/0.2.0/SHA256SUMS
```

Expected:

- `client` is `igloo-home`;
- `version` matches `repos/igloo-home/package.json`;
- `platform` is `macos` on macOS or `linux` on Linux;
- `targetFamily` is `dmg` on macOS or `appimage` on Linux;
- the checksum file names the staged artifact.

## Task 6: Commit In The Correct Order

**Files:**
- `repos/igloo-home/CHANGELOG.md`
- Parent files from Tasks 1-4.

- [ ] **Step 1: Commit the Home changelog inside the submodule**

Run:

```bash
git -C repos/igloo-home status --short
git -C repos/igloo-home add CHANGELOG.md
git -C repos/igloo-home commit -m "Document unsigned beta artifact staging"
```

Expected: one `repos/igloo-home` commit. If `repos/igloo-home/CHANGELOG.md` did
not change because the final implementation kept all docs parent-owned, skip
this step and note why in this plan.

- [ ] **Step 2: Stage parent files explicitly**

Run:

```bash
git add Makefile README.md dev/BACKLOG.md dev/docs/RELEASE.md dev/docs/GOTCHAS.md dev/docs/2026-06-26-public-beta-release-plan.md scripts/igloo-home-package-release.sh test/package.json test/scripts/check-doc-command-surfaces.sh test/scripts/test-igloo-home-package-release.sh test/scripts/test-run-sh.sh repos/igloo-home
```

Do not use `git add -A`.

- [ ] **Step 3: Review staged diff**

Run:

```bash
git diff --cached --stat
git diff --cached --check
```

Expected:

- no whitespace errors;
- parent diff includes the Home submodule pointer only if Step 1 committed a
  Home changelog update.

- [ ] **Step 4: Commit parent changes**

Run:

```bash
git commit -m "Add igloo-home unsigned artifact primitive"
```

- [ ] **Step 5: Final status**

Run:

```bash
git status --short --branch
git -C repos/igloo-home status --short --branch
```

Expected:

- parent branch clean and ahead by one implementation commit;
- Home branch clean and ahead by one changelog commit if Step 1 ran.

## Plan Self-Review

Spec coverage:

- Root command and script: Tasks 2-3.
- Parent-owned staging under `./.tmp/release/igloo-home/<version>/`: Task 2 and Task 5.
- macOS unsigned DMG and Linux AppImage selection: Task 2 tests and script contract.
- Checksums and manifest: Task 1 fixture tests, Task 2 script, Task 5 inspection.
- Version mismatch, missing artifact, unsupported OS, ambiguous output failures: Task 1 fixture tests.
- Release docs and Home changelog: Task 4.
- Deferred signed macOS, deb/rpm, GitHub Actions workflow: Task 4 backlog/docs.
- Correct commit order: Task 6.

Placeholder scan:

- No placeholder markers are intentional.
- The only conditional branch is the real Tauri package build in Task 5; it has an explicit failure-recording instruction because local package dependencies may differ by host.

Type/name consistency:

- Environment variables use the `IGLOO_HOME_PACKAGE_*` prefix throughout.
- The root target name is consistently `igloo-home-package-release`.
- Manifest fields match the design: `client`, `version`, `platform`, `targetFamily`, `parentCommit`, `homeCommit`, `generatedAt`, `artifacts`.
