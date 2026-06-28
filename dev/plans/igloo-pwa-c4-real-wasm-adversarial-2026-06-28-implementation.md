# igloo-pwa C4 Real-WASM Adversarial Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `igloo-pwa` real-WASM adversarial tests for wrong-password and
corrupted-package profile/share decrypt paths.

**Architecture:** Add a single Vitest file that bypasses the default mocked
profile WASM injection, loads the checked-in PWA `bifrost_profile_wasm`
artifacts, exercises PWA adapter APIs, then restores the mock profile module for
suite isolation.

**Tech Stack:** TypeScript, Vitest, Node file reads in tests, `igloo-shared`
profile package loader, PWA local adapter.

---

## Global Constraints

- MIT; no new dependencies.
- Commit inside `repos/igloo-pwa` first if the submodule changes, then commit
  the parent docs/pointer updates.
- Use TDD: write the failing real-WASM test before any production edits.
- Prefer no production changes. Patch PWA adapter code only if the real-WASM
  tests expose an actual behavior gap.
- Keep this slice off Playwright/browser automation and release packaging.

## File Structure

- Create: `repos/igloo-pwa/test/frontend/profile-real-wasm.test.ts`
  - Owns real-WASM KAT setup and PWA adapter assertions.
- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
  - Marks C4 adversarial decrypt tests complete after verification.
- Modify: `dev/BACKLOG.md`
  - Removes the completed C4 tail backlog item.
- Modify: `dev/plans/igloo-pwa-c4-real-wasm-adversarial-2026-06-28-design.md`
  - Marks the design implemented after verification.

---

## Task 1: Add Red-First PWA Real-WASM Tests

**Files:**

- Create: `repos/igloo-pwa/test/frontend/profile-real-wasm.test.ts`

- [x] **Step 1: Write the failing test file**

Create a test file that:

- imports Node `readFileSync` / `fileURLToPath`;
- imports Vitest `beforeEach`, `afterEach`, `describe`, `expect`, `it`;
- imports `configureWasmProfileLoader`, `setInjectedWasmProfileModuleForTests`,
  `createProfilePackagePair`, and `Secret` from `igloo-shared`;
- imports `* as adapter` from `@/lib/local-adapter`;
- builds a minimal valid browser profile payload;
- flips one character in a package body to create a corrupted package;
- injects real WASM in `beforeEach`;
- restores the normal profile WASM stub in `afterEach`;
- asserts wrong-password and corrupted-package failures through
  `adapter.importBfProfile()` and `adapter.unlockShareFromArtifact()`.

- [x] **Step 2: Verify red behavior**

Run:

```bash
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/profile-real-wasm.test.ts
```

Expected before the real-WASM setup is complete: FAIL because the new assertions
either still hit the mock profile module or cannot load the PWA WASM bytes.

If the tests pass immediately, make the assertions stricter so they prove real
WASM is active, for example by checking generated package strings are not the
mock literals `bfprofile1test` / `bfshare1test`.

Result: failed before executing tests because PWA's jsdom/Vite test transform
does not expose `import.meta.url` as a `file:` URL for Node file reads. After
switching to `process.cwd()`/`pathToFileURL`, the test reached real WASM and
failed on the mock-era profile id, proving the real package validator was
active.

---

## Task 2: Make Real-WASM Setup Green

**Files:**

- Modify: `repos/igloo-pwa/test/frontend/profile-real-wasm.test.ts`

- [x] **Step 1: Configure PWA real WASM**

In the test file, derive:

```ts
const wasmDir = resolve(process.cwd(), 'public/wasm');
const loaderUrl = pathToFileURL(resolve(wasmDir, 'bifrost_profile_wasm.js')).href;
const wasmBytes = readFileSync(
  fileURLToPath(pathToFileURL(resolve(wasmDir, 'bifrost_profile_wasm_bg.wasm'))),
);
```

Then call:

```ts
setInjectedWasmProfileModuleForTests(null);
configureWasmProfileLoader({
  loaderImportUrl: loaderUrl,
  wasmBinaryUrl: wasmBytes as unknown as string,
});
```

- [x] **Step 2: Restore the profile mock after each test**

Add a local helper equivalent to the default profile stub in
`repos/igloo-pwa/src/test/setup.ts`, then call it from `afterEach()` so later
mock-based tests stay isolated.

- [x] **Step 3: Re-run focused test**

Run:

```bash
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/profile-real-wasm.test.ts
```

Expected: PASS.

Result: PASS, 1 file / 4 tests.

---

## Task 3: Update C4 Tracking Docs

**Files:**

- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
- Modify: `dev/BACKLOG.md`
- Modify: `dev/plans/igloo-pwa-c4-real-wasm-adversarial-2026-06-28-design.md`

- [x] **Step 1: Update release-plan C4 wording**

Change the C4 row from partial to complete, noting shared NIP-44, Home handler,
and PWA real-WASM adversarial coverage are now in place.

- [x] **Step 2: Remove or rewrite the C4 backlog item**

Remove the C4 tail item from `dev/BACKLOG.md` once the PWA real-WASM tests pass.

- [x] **Step 3: Mark the design implemented**

Change the design status line to implemented with the completion date.

---

## Task 4: Verification and Commit

**Files:**

- Verify touched submodule and parent docs.

- [x] **Step 1: Run focused PWA real-WASM test**

```bash
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/profile-real-wasm.test.ts
```

Expected: PASS.

Result: PASS, 1 file / 4 tests.

- [x] **Step 2: Run full PWA unit suite**

```bash
npm --prefix repos/igloo-pwa run test:unit:raw
```

Expected: PASS.

Result: PASS, 14 files / 107 tests.

- [x] **Step 3: Run docs guard**

```bash
npm --prefix test run test:guards:docs
```

Expected: PASS.

Result: PASS.

- [x] **Step 4: Commit**

Commit `repos/igloo-pwa` first if changed, then commit parent pointer/docs.

Result: submodule commit `5eec09a` records the PWA real-WASM test; parent commit
records the submodule pointer and C4 tracking docs.

## Self-Review

Spec coverage: all design requirements map to Tasks 1-4.

Placeholder scan: no TBD/TODO placeholders.

Type/name consistency: paths, commands, and adapter names match the current
tree.
