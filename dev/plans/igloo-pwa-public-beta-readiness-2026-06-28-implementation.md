# igloo-pwa Public Beta Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the five agent-doable Phase 1 PWA public-beta readiness
tasks.

**Architecture:** Keep code changes minimal. Use existing PWA tests to verify
C1, refine existing PWA docs, and classify/fix npm audit findings according to
beta shipping risk.

**Tech Stack:** Markdown docs, TypeScript/Vitest for existing masking tests,
npm audit, PWA Vite app.

---

## Global Constraints

- MIT; no new dependencies unless audit remediation requires a non-breaking
  update.
- Commit inside `repos/igloo-pwa` first if the submodule changes, then commit
  the parent pointer/docs.
- Do not perform live GitHub Pages, Cloudflare, DNS, or custom-domain actions.
- Do not force a breaking Vite major upgrade for a dev-server-only advisory
  already deferred to backlog.

## File Structure

- Maybe modify: `repos/igloo-pwa/README.md`
  - Soften deployment header wording and link user/deployment docs.
- Maybe modify: `repos/igloo-pwa/DEPLOYMENT.md`
  - Fill small gaps in the GitHub Pages plus Cloudflare deployment guide.
- Maybe modify: `repos/igloo-pwa/docs/USER_GUIDE.md`
  - Fill small gaps in install, first-run, troubleshooting, or lost-share
    recovery guidance.
- Maybe modify: `repos/igloo-pwa/package.json` / `package-lock.json`
  - Only if audit reveals a beta-relevant non-breaking fix.
- Modify: `dev/plans/igloo-pwa-public-beta-readiness-2026-06-28-design.md`
  - Mark implemented after verification.
- Modify: this implementation plan with verification results.

---

## Task 1: Verify PWA C1 Masking

**Files:**

- Verify: `repos/igloo-pwa/test/frontend/App.test.tsx`
- Verify: `repos/igloo-pwa/src/views/recover.tsx`

- [x] **Step 1: Run the focused masking test**

```bash
npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "reveals, masks, and clears the recovered private key"
```

Expected: PASS. This proves the PWA recovery surface masks the full `nsec` by
default and only reveals it after explicit user action.

Result: PASS, 1 test passed / 27 skipped in `App.test.tsx`.

- [x] **Step 2: Record whether code changes are needed**

Expected: no code changes if the test passes.

Result: no code changes needed for C1 masking.

---

## Task 2: Confirm License and Refine Docs

**Files:**

- Verify: `repos/igloo-pwa/LICENSE`
- Modify: `repos/igloo-pwa/README.md`
- Maybe modify: `repos/igloo-pwa/DEPLOYMENT.md`
- Maybe modify: `repos/igloo-pwa/docs/USER_GUIDE.md`

- [x] **Step 1: Confirm MIT license exists**

```bash
test -f repos/igloo-pwa/LICENSE
```

Expected: PASS.

Result: PASS; `repos/igloo-pwa/LICENSE` exists and is MIT.

- [x] **Step 2: Update README links and deployment wording**

Make README point to:

- `DEPLOYMENT.md`;
- `docs/USER_GUIDE.md`;
- `TESTING.md`;
- `CONTRIBUTING.md`.

Change the deployment wording from static hosts "must" provide headers to the
beta-specific statement: GitHub Pages is the origin; Cloudflare injects
COOP/COEP/CORP. The headers are hardening and future-threading readiness, not a
current functional dependency.

Result: README links `DEPLOYMENT.md` and `docs/USER_GUIDE.md` and now describes
Cloudflare as the beta header-injection layer.

- [x] **Step 3: Patch small doc gaps only**

If needed, make small additions to `DEPLOYMENT.md` and `docs/USER_GUIDE.md` so
they explicitly cover:

- GitHub Pages origin;
- Cloudflare response header Transform Rule;
- HTTPS enforcement;
- no service worker;
- install / first run / troubleshooting / lost-share recovery.

Result: deployment guide now calls out public-beta support pages. Existing user
guide already covers install, first run, troubleshooting, and lost-share
recovery.

---

## Task 3: Run and Classify npm Audit

**Files:**

- Maybe modify: `repos/igloo-pwa/package.json`
- Maybe modify: `repos/igloo-pwa/package-lock.json`
- Maybe modify: `dev/BACKLOG.md`

- [x] **Step 1: Run production audit**

```bash
npm --prefix repos/igloo-pwa audit --omit=dev
```

Expected: zero production vulnerabilities.

Result: PASS; `found 0 vulnerabilities`.

- [x] **Step 2: Run full audit**

```bash
npm --prefix repos/igloo-pwa audit
```

Expected: either zero vulnerabilities or only dev-server-only findings already
captured in backlog.

Result: full audit reports Vite/esbuild dev-server-only advisories; npm's fix is
`vite@8.1.0` via a semver-major upgrade.

- [x] **Step 3: Fix beta-relevant findings only**

If production dependencies are vulnerable, apply the smallest non-breaking
package update and rerun audit/tests. If only the known dev-server esbuild/Vite
finding remains, keep the existing backlog deferral and do not force a breaking
major upgrade.

Result: no package changes; backlog and release plan classify the Vite/esbuild
dev-server advisories as deferred because production dependencies are clean and
the shipped static bundle does not expose the dev server.

---

## Task 4: Verification

**Files:**

- Verify touched PWA docs/package files and parent docs.

- [x] **Step 1: Run PWA unit suite**

```bash
npm --prefix repos/igloo-pwa run test:unit:raw
```

Expected: PASS.

Result: PASS, 14 files / 107 tests.

- [x] **Step 2: Run docs guard**

```bash
npm --prefix test run test:guards:docs
```

Expected: PASS.

Result: PASS.

---

## Task 5: Commit and Push

**Files:**

- Commit submodule first if changed, then parent pointer/docs.

- [x] **Step 1: Commit PWA changes**

If `repos/igloo-pwa` changed:

```bash
git -C repos/igloo-pwa add README.md DEPLOYMENT.md docs/USER_GUIDE.md package.json package-lock.json
git -C repos/igloo-pwa commit -m "Prepare PWA public beta docs"
```

Result: submodule commit `7835ddf` updates PWA README/deployment docs.

- [ ] **Step 2: Commit parent plan/pointer changes**

```bash
git add repos/igloo-pwa dev/plans/igloo-pwa-public-beta-readiness-2026-06-28-design.md dev/plans/igloo-pwa-public-beta-readiness-2026-06-28-implementation.md
git commit -m "Record PWA public beta readiness pass"
```

- [ ] **Step 3: Push**

Push the submodule first, then parent `dev`.

## Self-Review

Spec coverage: all five user-approved tasks map to Tasks 1-5.

Placeholder scan: no TBD/TODO placeholders.

Type/name consistency: commands and paths match the current tree.
