# C1 Residue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix the one stale, misleading notice in igloo-home that claims the recovered group key is "shown in plaintext" when it is in fact masked by default.

**Background:** C1 (recovered-nsec masking) is already remediated across all hosts, and masking regression tests already exist and pass — igloo-home `test/frontend/RecoverKey.test.tsx:147-171`, igloo-pwa `test/frontend/App.test.tsx:644-668`, igloo-ui `test/ui/sensitive.test.tsx`. The only residue is incorrect copy. This is a single-task plan.

## Global Constraints

- MIT; no new deps. Commit inside the submodule on `dev`; stage only changed files (never `git add -A`); no push. No formatter churn.

---

### Task 1: Correct the igloo-home recovery notice copy

**Files:**
- Modify: `repos/igloo-home/src/App.tsx:1065`
- Test (verify, possibly update): `repos/igloo-home/test/frontend/RecoverKey.test.tsx`

- [ ] **Step 1: Check whether any test asserts the old string**

Run: `grep -rn "shown in plaintext" repos/igloo-home`
Expected: only the `App.tsx:1065` `setNotice(...)` call. If a test also asserts this exact substring, it must be updated in Step 3.

- [ ] **Step 2: Replace the misleading copy**

In `repos/igloo-home/src/App.tsx:1065`, change:

```ts
setNotice('Group secret key recovered locally and shown in plaintext. Move it to an encrypted store, then leave this screen to clear it.');
```

to:

```ts
setNotice('Group secret key recovered locally and masked until you reveal it. Move it to an encrypted store, then leave this screen to clear it.');
```

- [ ] **Step 3: Update any test asserting the old substring**

If Step 1 found a test asserting `"shown in plaintext"`, update that assertion to match the new wording (e.g. `"masked until you reveal it"`). If no test asserts it, skip.

- [ ] **Step 4: Run the recovery test**

Run (from `repos/igloo-home`): `npm run test:unit:raw -- test/frontend/RecoverKey.test.tsx`
Expected: PASS (masking assertions at :147-171 unaffected; notice change green).

- [ ] **Step 5: Commit (inside the submodule)**

```bash
git -C repos/igloo-home add src/App.tsx
# include the test file too if Step 3 changed it
git -C repos/igloo-home commit -m "Correct recovery notice: key is masked, not plaintext (C1 residue)"
```

- [ ] **Step 6: Bump the pointer**

```bash
make bump-pointers MSG="Bump igloo-home: correct recovery notice copy (C1 residue)"
make verify
```

## Self-Review

Single mechanical copy fix. The only risk is a test asserting the old substring (handled by Steps 1/3). Masking behavior and its existing tests are untouched.
