# Landing Follow-ups (Tiers 1–3) Hard-Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the post-landing-unification follow-ups: stop the shared `AppHeader` from leaking dead web-nav links into every host (Tier 2), hard-cut the residual dead code/orphans the migration left behind (Tier 3), and add landing-convergence verification so this whole class of "shared screen quietly diverges in one client" bug can't hide again (Tier 1).

**Architecture:** Five focused tasks, each scoped to one submodule (+ parent pointer bump), built in dependency order: drop the AppHeader nav, sweep the igloo-ui orphans, clean chrome, clean home, then add the verification (capture + static guard) last so the guard validates the final converged state.

**Tech Stack:** React 18 + TypeScript, Tailwind (igloo-ui preset, all-source consumption), Vite, Playwright (`@fast` e2e + agent screenshots), Vitest, bash guard scripts under `test/scripts/`.

## Global Constraints

- **Hard cut, zero tech debt:** delete the old path in the same change — no deprecation aliases, compat shims, dual paths, dead exports, or dead test ids/helpers left behind.
- **Submodule workflow:** commit **inside each submodule first**, then bump the parent pointer with **explicit staging** (`git add repos/<name>`). **NEVER `git add -A`/`git add .`** — the parent tree carries an unrelated `dev/audit/` stream and `.superpowers/` scratch that must stay out.
- **Stay on `dev`; do not push or open PRs.** End every commit body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **igloo-ui tests** live in `repos/igloo-ui/test/**/*.test.tsx` (script: `npm --prefix repos/igloo-ui run test`). **igloo-ui is consumed all-source** (symlink + vite alias), so edits are live in every client with no rebuild.
- **`make verify` is the authoritative gate** (`.tmp/agent/verify.json` → `{"ok":true,"exitCode":0}`). The final task must end green.

---

### Task 1: Tier 2 — drop the AppHeader web-nav (hard-cut)

The shared `AppHeader` defaults `links` to `[Website, Docs, GitHub]` with dead `href: '#'`, rendered in `mode === 'welcome'`. No client passes `links`, so all three render dead links on their landing. Decision: **drop the nav entirely** — the welcome header keeps only the logo/title block.

**Files:**
- Modify: `repos/igloo-ui/src/components/ui/app-header.tsx` (props ~4-12, `defaultLinks` ~15-19, `AppHeader` signature ~21-31, `renderShellRightContent` ~58-115)
- Test: `repos/igloo-ui/test/` (grep for an existing app-header test; update if one asserts the links)

**Interfaces:**
- Produces: `AppHeaderProps` no longer has a `links` field; `mode === 'welcome'` renders no right-content.

- [ ] **Step 1: Find any test/consumer touching the nav links**

Run: `grep -rn "links" repos/igloo-ui/src/components/ui/app-header.tsx repos/igloo-ui/test && grep -rn "Website\|Docs\|GitHub\|links=" repos/*/src repos/igloo-ui/test 2>/dev/null`
Note any test asserting the Website/Docs/GitHub links so Step 3 updates it. (Expected: no client passes `links=`.)

- [ ] **Step 2: Remove the `links` prop, default, and welcome rendering**

In `app-header.tsx`: delete the `links?: Array<{ label: string; href: string }>;` prop from `AppHeaderProps`; delete the `defaultLinks` const; remove `links` from the `AppHeader` destructure and from the `renderShellRightContent({...})` call; remove the `links` param from `renderShellRightContent`'s signature; change the `if (mode === 'welcome')` branch to `return null;` (or drop the branch so welcome falls through to the final `return null`). Leave the `task`/`profile`/`dashboard` branches untouched.

- [ ] **Step 3: Update/remove any affected test**

If Step 1 found a test asserting the links, delete those assertions (the nav no longer exists). Do not weaken unrelated header assertions.

- [ ] **Step 4: Typecheck + igloo-ui tests**

Run: `npm --prefix repos/igloo-ui run test`
Expected: PASS. (If a consumer passed `links=`, TS would now error — Step 1 confirmed none do.)

- [ ] **Step 5: Visually confirm the header on all three landings**

Run: `make screenshot CLIENT=pwa STATE=welcome-returning && make screenshot CLIENT=home STATE=landing && make screenshot CLIENT=chrome STATE=onboarding`
Look at the three PNGs in `.tmp/agent/`: the header shows only the logo + "Igloo / Threshold Signing for Nostr" — **no Website/Docs/GitHub links**.

- [ ] **Step 6: Commit igloo-ui + bump pointer**

```bash
git -C repos/igloo-ui add src/components/ui/app-header.tsx test/
git -C repos/igloo-ui commit -m "AppHeader: drop dead-link web nav (no host defaults)"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-ui
git commit -m "Bump pointer: drop AppHeader web nav"
```

---

### Task 2: Tier 3 — sweep igloo-ui orphans + dead pwa test-support chain (hard-cut)

After the landing migration, `StoredProfileCardModel` and the `storedProfileEntry`/`storedProfileLoad`/`storedProfileUnlockSubmit` e2e test ids are orphaned in igloo-ui — **but** the test ids are still referenced by now-dead helpers in `test/igloo-pwa/support/ui.ts:38,46,47`. The chain must be traced and removed before deleting the ids. Also fixes the Task-2 meta-row test nit.

**Files:**
- Modify: `repos/igloo-ui/src/models/view-models.ts` (delete `StoredProfileCardModel` ~3), `repos/igloo-ui/src/index.ts` (remove the re-export ~29), `repos/igloo-ui/src/lib/e2e-test-ids.ts` (remove ~124-126), `repos/igloo-ui/test/host-shell-welcome.test.tsx` (tighten the `document.querySelector` meta-row assertion)
- Modify (parent test harness, not a submodule): `test/igloo-pwa/support/ui.ts` (remove the dead helpers referencing `storedProfileEntry`/`storedProfileLoad` ~38,46-47)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `StoredProfileCardModel` and the three `storedProfile*` test ids no longer exist.

- [ ] **Step 1: Trace the storedProfile* helper chain in pwa test support**

Run: `grep -rn "storedProfileEntry\|storedProfileLoad\|storedProfileUnlockSubmit" test/ repos/*/src` then, for each helper function in `test/igloo-pwa/support/ui.ts` that uses those ids, grep the pwa specs for calls to that helper: `grep -rn "<helperName>" test/igloo-pwa`.
Expected: the helpers are uncalled (the welcome migration replaced them with `welcomeProfileRow`/`welcomeProfileUnlock`-based helpers). If any spec still calls them, STOP — that spec is asserting deleted markup and must be reconciled first; report it.

- [ ] **Step 2: Remove the dead pwa support helpers**

Delete the now-confirmed-uncalled helper functions in `test/igloo-pwa/support/ui.ts` that reference `storedProfileEntry`/`storedProfileLoad`/`storedProfileUnlockSubmit`. Remove any import line left unused.

- [ ] **Step 3: Confirm zero remaining consumers, then delete the igloo-ui orphans**

Run: `grep -rn "StoredProfileCardModel\|storedProfileEntry\|storedProfileLoad\|storedProfileUnlockSubmit" repos test | grep -v "view-models.ts\|e2e-test-ids.ts"`
Expected: **no output**. Then delete `StoredProfileCardModel` from `view-models.ts`, its re-export from `index.ts`, and the three test-id lines from `e2e-test-ids.ts`.

- [ ] **Step 4: Fix the meta-row test nit**

In `repos/igloo-ui/test/host-shell-welcome.test.tsx`, change the meta-row assertion from `document.querySelector('.igloo-welcome-profile-meta')` to a scoped query off the render result (`const { container } = render(...)` → `container.querySelector('.igloo-welcome-profile-meta')`). Keep the existing assertions (no leading/doubled dots; exact text). This is a hygiene fix, not a behavior change.

- [ ] **Step 5: igloo-ui tests + pwa fast e2e (the chain's regression guard)**

Run: `npm --prefix repos/igloo-ui run test`
Then: `npm --prefix test run test:e2e:igloo-pwa:fast`
Expected: both PASS (the pwa welcome e2e proves the removed helpers were genuinely dead).

- [ ] **Step 6: Commit igloo-ui + the harness file, bump pointer**

```bash
git -C repos/igloo-ui add src/models/view-models.ts src/index.ts src/lib/e2e-test-ids.ts test/host-shell-welcome.test.tsx
git -C repos/igloo-ui commit -m "Remove orphaned StoredProfileCardModel + storedProfile* test ids; tighten meta-row test"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-ui test/igloo-pwa/support/ui.ts
git commit -m "Bump pointer: sweep landing orphans + dead pwa test helpers"
```
Note: `test/igloo-pwa/support/ui.ts` is a parent-repo harness file, so it commits in the parent alongside the pointer bump (still explicit staging, no `-A`).

---

### Task 3: Tier 3 — chrome cleanups (delete dead state + add form collapse)

**Files:**
- Modify: `repos/igloo-chrome/src/pages/Onboarding.tsx` (`activatingProfileId`/`deletingProfileId` state ~88-89 and their setter call sites; the `showOnboard`/`showImport` one-way booleans)

**Interfaces:**
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Delete the write-only profile-busy state**

Grep `Onboarding.tsx` for `activatingProfileId` / `setActivatingProfileId` / `deletingProfileId` / `setDeletingProfileId`. They are written but never read after the `StoredProfilesLandingCard` removal. Remove the two `useState` declarations (~88-89) and every `setActivatingProfileId(...)` / `setDeletingProfileId(...)` call. Confirm with a final grep that none remain.

- [ ] **Step 2: Add a collapse/cancel affordance to the Onboard/Import forms**

The forms are revealed by one-way `setShowOnboard(true)` / `setShowImport(true)` when a returning user clicks the hero's secondary actions, with no way back. Add a "Cancel" / "Back" control on each revealed form (when `profiles.length > 0`) that calls `setShowOnboard(false)` / `setShowImport(false)` and clears that form's draft state. Do not show Cancel in the no-profiles entry state (there the form is the only surface). Match the existing chrome form button styling (reuse the shared `Button` with `variant="secondary"`).

- [ ] **Step 3: Typecheck + render + fast e2e**

Run: `make igloo-chrome-typecheck`
Then: `make screenshot CLIENT=chrome STATE=onboarding` (confirm the hero still renders; trigger a form in your head — the Cancel appears only with stored profiles)
Then: `npm --prefix test run test:e2e:igloo-chrome:fast`
Expected: typecheck clean, e2e PASS.

- [ ] **Step 4: Commit chrome + bump pointer**

```bash
git -C repos/igloo-chrome add src/
git -C repos/igloo-chrome commit -m "Onboarding: drop dead profile-busy state; add Cancel to Onboard/Import forms"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-chrome
git commit -m "Bump pointer: chrome landing cleanups"
```

---

### Task 4: Tier 3 — home cleanups (Rotate seeding + unlock nit)

**Files:**
- Modify: `repos/igloo-home/src/App.tsx` (`onRotate` ~1528; `submitWelcomeUnlock`'s `finally`)

**Interfaces:**
- Consumes: home's `createForm` state (`{ mode: 'new'|'rotate'; sourceProfileId; ... }`, ~554-562) and `setCreateForm`.

- [ ] **Step 1: Seed rotate mode from the per-profile ⋮ Rotate**

Currently `onRotate={(profileId) => { setSelectedProfileId(profileId); setActiveView('create'); }}` lands on the create view with `createForm.mode` still `'new'` and `sourceProfileId` empty, so the rotate path (`App.tsx:942` requires `mode==='rotate' && sourceProfileId`) isn't honored. Change it to seed the form:

```tsx
onRotate={(profileId) => {
  setSelectedProfileId(profileId);
  setCreateForm((prev) => ({ ...prev, mode: 'rotate', sourceProfileId: profileId }));
  setActiveView('create');
}}
```

Verify `setCreateForm` is the actual setter name and that `mode`/`sourceProfileId` are the actual field names (they are, per `App.tsx:554-562`) while editing.

- [ ] **Step 2: Drop the redundant `setWelcomeUnlockSubmitting(false)` in `finally`**

In `submitWelcomeUnlock`, `closeWelcomeUnlock()` already resets `welcomeUnlockSubmitting` on the success path and the error path sets its own state; the trailing `setWelcomeUnlockSubmitting(false)` in the `finally` is a redundant double-set. Remove the `finally` block's submitting reset only if `closeWelcomeUnlock` + the error path already cover both outcomes — read the handler and confirm before removing; if removing it would leave an error path with `submitting` stuck true, keep it and instead remove the duplicate from the success path. (Pick whichever leaves exactly one reset per outcome.)

- [ ] **Step 3: Typecheck + render + unit tests**

Run: `make igloo-home-typecheck && make igloo-home-test-unit`
Then: `make screenshot CLIENT=home STATE=landing-seeded` (returning hero still renders; the ⋮ Rotate now seeds rotate mode — optionally verify by reading the create view state, no visual change on the landing itself).
Expected: typecheck clean, unit PASS.

- [ ] **Step 4: Commit home + bump pointer**

```bash
git -C repos/igloo-home add src/App.tsx
git -C repos/igloo-home commit -m "Landing: seed rotate mode from per-profile Rotate; drop redundant unlock-submitting reset"
cd /Users/cscott/Repos/frostr/frostr-infra
git add repos/igloo-home
git commit -m "Bump pointer: home landing cleanups"
```

---

### Task 5: Tier 1 — landing-convergence verification (capture + automated guard)

Add the landing/welcome state to routine capture for all three clients, and a static `test:guards` check that fails if any client stops consuming the shared Welcome heroes or reintroduces a bespoke landing component. This is the recurrence-preventer for the original "home shows old UI for 5 sessions" failure.

**Files:**
- Create: `test/scripts/check-landing-convergence.sh`
- Modify: `test/package.json` (wire the new guard into `test:guards`)
- Modify: the three agent-screenshot specs' default/allowed states if needed so `landing`/`welcome-returning`/`onboarding` are first-class capture states (they already accept these via `FROSTR_SCREENSHOT_STATE`/`STATE`; confirm and document)

**Interfaces:**
- Consumes: the converged state from Tasks 1–4 (all three apps import the shared heroes; the deleted components are gone).

- [ ] **Step 1: Write the static convergence guard**

Create `test/scripts/check-landing-convergence.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`, derive `ROOT_DIR` from the script location). For each client landing file — `repos/igloo-pwa/src/App.tsx`, `repos/igloo-home/src/App.tsx`, `repos/igloo-chrome/src/pages/Onboarding.tsx` — assert BOTH:
  1. it imports `WelcomeReturningHero` (proves it renders the shared landing): `grep -q "WelcomeReturningHero" "$file"` — fail with a clear message naming the client if absent;
  2. it does NOT reference the deleted bespoke components: `! grep -qE "StoredProfilesLandingCard|HostEntryTile" "$file"` — fail if present.
Print a one-line PASS per client and exit non-zero with a descriptive message on the first failure. Model the structure on an existing guard like `test/scripts/check-cross-client-imports.sh`.

- [ ] **Step 2: Run the guard against the current (converged) tree**

Run: `bash test/scripts/check-landing-convergence.sh`
Expected: PASS for all three clients.

- [ ] **Step 3: Negative-check the guard (prove it catches regression)**

Temporarily edit one client file to add a fake `StoredProfilesLandingCard` reference (or remove the hero import), run the guard, confirm it FAILS with the right message, then revert the edit. (Do not commit the temporary edit.)

- [ ] **Step 4: Wire the guard into `test:guards`**

In `test/package.json`, add `test:guards:landing` → `bash ./scripts/check-landing-convergence.sh` and append it to the `test:guards` chain (line ~7, alongside `:selectors`/`:tags`). Keep it in `test:guards:full` too.

- [ ] **Step 5: Document the landing capture states**

Confirm `make screenshot CLIENT=pwa STATE=welcome-returning`, `CLIENT=home STATE=landing-seeded`, and `CLIENT=chrome STATE=onboarding` all render the shared hero (re-run them). Add a one-line note to the screenshot-state docs (the `## See a screen` surface in `AGENTS.md`, or `test/docs/WORKFLOWS.md`) listing the landing states as the standard cross-client convergence capture so future agents render them.

- [ ] **Step 6: Full gate**

Run: `npm --prefix test run test:guards` (must include the new landing guard, all PASS)
Then: `make verify`
Expected: guards PASS; `make verify` → `{"ok":true,"exitCode":0}`.

- [ ] **Step 7: Commit the harness/docs + bump pointer if needed**

The guard script, `test/package.json`, and docs live in the parent repo (not a submodule). Stage explicitly:

```bash
cd /Users/cscott/Repos/frostr/frostr-infra
git add test/scripts/check-landing-convergence.sh test/package.json AGENTS.md test/docs/WORKFLOWS.md
git commit -m "Guard: cross-client landing convergence (capture states + static check)"
```
(No pointer bump unless a submodule changed in this task — it shouldn't have.)

---

## Self-Review notes

- **Tier coverage:** Tier 2 = Task 1 (drop AppHeader nav). Tier 3 = Tasks 2 (igloo-ui orphans + dead pwa helpers + meta-row nit), 3 (chrome dead state + form collapse), 4 (home Rotate seeding + unlock nit). Tier 1 = Task 5 (capture + static guard + gate). All recommended follow-ups covered.
- **Ordering rationale:** code changes (Tasks 1–4) precede the verification (Task 5) so the convergence guard validates the final state; the guard would pass today but is authored last to also cover the just-made changes.
- **Flagged judgment points (implementer must verify against the real file, not assume):** Task 2 Step 1 (whether any pwa spec still calls the storedProfile* helpers — STOP if so); Task 4 Step 2 (which `submitting` reset to drop so exactly one remains per outcome). These are marked inline.
- **Type/name consistency:** `createForm`/`setCreateForm` fields (`mode`, `sourceProfileId`) used in Task 4 match `App.tsx:554-562`. The guard checks `WelcomeReturningHero` (the import all three now share).
- **No placeholders:** every deletion names its grep-confirm step; the guard script's assertions are spelled out; the Rotate seeding shows the exact code.
