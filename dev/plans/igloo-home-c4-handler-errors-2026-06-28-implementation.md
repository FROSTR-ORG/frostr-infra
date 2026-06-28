# igloo-home C4 Handler Error Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Add `igloo-home` C4 TS-side handler tests for unlock, rotate, and
recover decrypt/package failures.

**Architecture:** Reuse existing Vitest/Testing Library app tests with mocked
`@/lib/api` calls. Keep Rust/Tauri crypto behavior out of scope; test that
mapped frontend errors reach the correct workflow surfaces.

**Tech Stack:** React, TypeScript, Vitest, Testing Library, Tauri API mocks,
parent release-plan docs.

---

## Global Constraints

- MIT; no new dependencies.
- Commit inside `repos/igloo-home` first if the submodule changes, then commit
  parent docs/pointer updates.
- Use TDD: write failing UI tests before production edits.
- Keep production changes limited to `repos/igloo-home/src/App.tsx` if the red
  tests prove a handler gap.
- Do not add Rust, real-WASM, Playwright, visual, or desktop harness coverage in
  this slice.

## File Structure

- Modify: `repos/igloo-home/test/frontend/App.test.tsx`
  - Adds landing unlock and rotate failure handler tests.
- Modify: `repos/igloo-home/test/frontend/RecoverKey.test.tsx`
  - Adds recover failure handler test.
- Maybe modify: `repos/igloo-home/src/App.tsx`
  - Only if the red-first tests expose swallowed/misrouted handler failures.
- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
  - Notes that the `igloo-home` handler slice is covered.
- Modify: `dev/BACKLOG.md`
  - Narrows remaining C4 backlog to the `igloo-pwa` real-WASM tail.
- Modify: `dev/plans/igloo-home-c4-handler-errors-2026-06-28-design.md`
  - Marks the design implemented after verification.

---

## Task 1: Add Red-First Home Handler Tests

**Files:**

- Modify: `repos/igloo-home/test/frontend/App.test.tsx`
- Modify: `repos/igloo-home/test/frontend/RecoverKey.test.tsx`

- [x] **Step 1: Write failing tests**

Add tests for:

- landing unlock: click `Unlock`, enter a wrong password in
  `welcome-unlock-password`, submit `welcome-unlock-submit`, mock
  `startProfileSession` to reject `Incorrect passphrase.`, and assert the modal
  shows `Incorrect password. Please try again.`;
- rotate generate: render create/rotate mode with a selected source profile and
  one `bfshare` source, mock `createRotatedKeyset` to reject
  `Invalid package: corrupted`, submit `rotate-submit`, and assert the error
  banner shows that message;
- recover: mock `recoverGroupKey` to reject `Incorrect passphrase.`, click
  `Recover Key`, assert the banner shows the message, and assert recovered key
  output is absent.

- [x] **Step 2: Verify red behavior**

Run:

```bash
npm --prefix repos/igloo-home run test:unit:raw -- test/frontend/App.test.tsx test/frontend/RecoverKey.test.tsx
```

Expected: any failure should identify an actual handler gap or an over-specific
test assertion. Fix assertions only when they contradict existing component
contracts.

Result: failed on the unlock modal path; rotate/recover also produced unhandled
rejections after setting banner state. These were real handler gaps.

---

## Task 2: Patch Minimal Handler Behavior If Needed

**Files:**

- Maybe modify: `repos/igloo-home/src/App.tsx`

- [x] **Step 1: Fix only proven handler gaps**

If the unlock modal failure is confirmed, update `handleStartProfileSession()`
so call sites can request localized start-failure handling. Preserve the
dashboard start button's existing load-failed panel behavior.

Likely shape:

```ts
async function handleStartProfileSession(
  profileId = selectedProfileId,
  sessionPassphrase = passphrase,
  nextView: ViewKey = 'dashboard',
  options: { rethrowStartFailure?: boolean } = {},
) {
  // ...
  } catch (err) {
    if (options.rethrowStartFailure) {
      throw err;
    }
    setDashboardLoadError({ message: formatError(err), at: Math.floor(Date.now() / 1000) });
    setActiveView('dashboard');
    setActiveDashboardTab('signer');
    return;
  }
}
```

Then call it from `handleLoadLandingProfile()` with
`{ rethrowStartFailure: Boolean(providedPassphrase) }`.

Result: `handleStartProfileSession()` now supports localized start-failure
handling for the unlock modal, and rotate/recover handlers return after
banner-surfaced failures instead of leaking rejected promises.

- [x] **Step 2: Re-run focused tests**

Run:

```bash
npm --prefix repos/igloo-home run test:unit:raw -- test/frontend/App.test.tsx test/frontend/RecoverKey.test.tsx
```

Expected: PASS.

Result: PASS, 2 files / 15 tests.

---

## Task 3: Update C4 Tracking Docs

**Files:**

- Modify: `dev/docs/2026-06-26-public-beta-release-plan.md`
- Modify: `dev/BACKLOG.md`
- Modify: `dev/plans/igloo-home-c4-handler-errors-2026-06-28-design.md`

- [x] **Step 1: Update release-plan C4 wording**

Mark the `igloo-home` TS-side handler tests as covered, leaving only the
`igloo-pwa` real-WASM adversarial path as the remaining C4 tail.

- [x] **Step 2: Narrow the backlog C4 item**

Remove `igloo-home` from the C4 backlog item and keep the `igloo-pwa`
real-WASM wrong-password/corrupted-package test explicit.

- [x] **Step 3: Mark the design implemented**

Change the design status line to implemented with the completion date.

---

## Task 4: Verification and Commit

**Files:**

- Verify touched submodule and parent docs.

- [x] **Step 1: Run focused App tests**

```bash
npm --prefix repos/igloo-home run test:unit:raw -- test/frontend/App.test.tsx
```

Result: PASS, 1 file / 11 tests.

- [x] **Step 2: Run focused RecoverKey tests**

```bash
npm --prefix repos/igloo-home run test:unit:raw -- test/frontend/RecoverKey.test.tsx
```

Result: PASS, 1 file / 4 tests.

- [x] **Step 3: Run full home unit suite**

```bash
npm --prefix repos/igloo-home run test:unit:raw
```

Result: PASS, 7 files / 44 tests.

- [x] **Step 3a: Run home typecheck**

```bash
npm --prefix repos/igloo-home run typecheck:raw
```

Result: PASS.

- [x] **Step 4: Run docs guard**

```bash
npm --prefix test run test:guards:docs
```

Result: PASS.

- [x] **Step 5: Commit**

Commit `repos/igloo-home` first if changed, then commit parent pointer/docs.

## Self-Review

Spec coverage: all design requirements map to Tasks 1-4.

Placeholder scan: no TBD/TODO placeholders.

Type/name consistency: paths, commands, and mocked API names match the current
tree.
