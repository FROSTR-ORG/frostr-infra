# Phase 0 Foundation (public-repo hygiene + dev/ disclosure + versioning) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Checklist (`- [ ]`) steps. This is mechanical doc/git/config work — not TDD; verification is "file present + content correct + `make verify` green + guards".

**Goal:** Make the workspace + launch-client repos safe and presentable to flip public: MIT license coverage everywhere, a SECURITY.md reporting path, a code of conduct, a beta disclaimer, the dev/ audit findings kept out of the public tree, and the frozen `igloo-ui` version corrected.

**Decisions (locked):** MIT, "2025 FROSTR Protocol" (replicate `repos/igloo-chrome/LICENSE` verbatim). Security reporting via **GitHub Private Vulnerability Reporting (PVR)**. **Contributor Covenant v2.1**. Versioning: **per-client semver + dated workspace tag**; bump `igloo-ui` `0.0.0`→`0.1.0`; `[Unreleased]` changelog accrual. dev/ audit findings/archive **untracked + gitignored**; git history **accepted** (no rewrite).

## Global Constraints

- Commit inside each submodule first, then `make bump-pointers`; never `git add -A` (keep `.superpowers/`, `.tmp/` out). No push (maintainer pushes). No formatter churn.
- LICENSE text is byte-identical to `repos/igloo-chrome/LICENSE` (MIT, `Copyright (c) 2025 FROSTR Protocol`).
- `make verify` must stay green; doc/structure guards (`npm --prefix test run test:guards`) must pass.

## File Structure

- LICENSE → add to: `./LICENSE` (parent), `repos/igloo-shared/LICENSE`, `repos/igloo-pwa/LICENSE`, `repos/igloo-home/LICENSE`. (igloo-ui, igloo-chrome already have it.)
- `./SECURITY.md`, `./CODE_OF_CONDUCT.md` — new at parent root.
- `./README.md` — add beta disclaimer banner.
- `repos/igloo-ui/package.json` — version bump.
- `./.gitignore` — add audit findings/archive ignores; plus `git rm --cached` the tracked ones.
- `dev/HISTORY.md` — correct the stale plaintext-nsec claim.

---

### Task 1: MIT license coverage

**Files:** create `./LICENSE`, `repos/igloo-shared/LICENSE`, `repos/igloo-pwa/LICENSE`, `repos/igloo-home/LICENSE`.

- [ ] **Step 1:** Copy the canonical license verbatim into all four locations:

```bash
cd /Users/cscott/Repos/frostr/frostr-infra
for dest in ./LICENSE repos/igloo-shared/LICENSE repos/igloo-pwa/LICENSE repos/igloo-home/LICENSE; do
  cp repos/igloo-chrome/LICENSE "$dest"
done
```

- [ ] **Step 2:** Verify all six repos now carry an identical MIT header:

```bash
for p in . repos/igloo-shared repos/igloo-ui repos/igloo-pwa repos/igloo-home repos/igloo-chrome; do head -3 "$p/LICENSE"; echo "--"; done
```
Expected: each shows `MIT License` / blank / `Copyright (c) 2025 FROSTR Protocol`.

- [ ] **Step 3:** Commit the submodule LICENSEs inside each submodule:

```bash
git -C repos/igloo-shared add LICENSE && git -C repos/igloo-shared commit -m "Add MIT LICENSE"
git -C repos/igloo-pwa    add LICENSE && git -C repos/igloo-pwa    commit -m "Add MIT LICENSE"
git -C repos/igloo-home   add LICENSE && git -C repos/igloo-home   commit -m "Add MIT LICENSE"
```
(The root `./LICENSE` commits with the parent in Task 7.)

---

### Task 2: Root SECURITY.md (GitHub PVR)

**Files:** create `./SECURITY.md`.

- [ ] **Step 1:** Write `./SECURITY.md`:

```markdown
# Security Policy

FROSTR is a threshold-signing system that handles private key material. We take
security seriously and welcome responsible disclosure.

## Reporting a Vulnerability

**Do not open a public issue for security problems.** Report privately via
**GitHub Private Vulnerability Reporting**: on the affected repository, go to the
**Security** tab → **Report a vulnerability**. This opens a private advisory
visible only to maintainers.

We aim to acknowledge reports within 72 hours and to keep you updated as we
investigate and remediate.

## Scope

FROSTR is in **public beta** and has been self-audited but has **not** undergone
an independent external security audit. The signing core (`bifrost-rs`), the
shared runtime (`igloo-shared`), and the launch clients (`igloo-pwa`,
`igloo-chrome`, `igloo-home`) are all in scope. Reference-only material
(`igloo-paper`) is out of scope.

## Supported Versions

During beta, only the latest released version of each client is supported.
```

- [ ] **Step 2 (maintainer, out-of-band):** Enable **Private Vulnerability Reporting** in each public repo's Settings → Security before flipping public. Note in the PR that this is required (the file alone does not enable it).

---

### Task 3: CODE_OF_CONDUCT.md (Contributor Covenant v2.1)

**Files:** create `./CODE_OF_CONDUCT.md`.

- [ ] **Step 1:** Write the **Contributor Covenant v2.1** canonical text **unmodified** (fetch from https://www.contributor-covenant.org/version/2/1/code_of_conduct/ — do not paraphrase), with the single project-specific substitution in the Enforcement section: replace the `[INSERT CONTACT METHOD]` placeholder with: *"a private report via the repository's Security tab (GitHub Private Vulnerability Reporting)."*

- [ ] **Step 2:** Verify the file contains the standard "Our Pledge / Our Standards / Enforcement / Attribution" sections and the version 2.1 attribution link, with no remaining `[INSERT ...]` placeholders.

---

### Task 4: README beta disclaimer banner

**Files:** modify `./README.md`.

- [ ] **Step 1:** Add a banner immediately under the top title (match the README's existing heading style):

```markdown
> ⚠️ **Public beta.** FROSTR handles private key material and is **self-audited**
> — it has not yet had an independent external security audit. Use at your own
> risk, prefer test funds/keys, and report security issues via the **Security**
> tab (see [SECURITY.md](SECURITY.md)).
```

- [ ] **Step 2:** Verify it renders near the top and links resolve (`SECURITY.md` exists from Task 2).

---

### Task 5: Versioning — igloo-ui off 0.0.0 + changelog accrual

**Files:** modify `repos/igloo-ui/package.json`; ensure each client `CHANGELOG.md` has an `[Unreleased]` section.

- [ ] **Step 1:** In `repos/igloo-ui/package.json`, change `"version": "0.0.0"` → `"version": "0.1.0"`.

- [ ] **Step 2:** Confirm each launch client + shared repo `CHANGELOG.md` has an `## [Unreleased]` heading for accrual; add one where missing (no content invented — just the heading + an entry noting the beta-prep work where appropriate).

- [ ] **Step 3:** Typecheck/build igloo-ui to confirm the version change breaks nothing: `npm --prefix repos/igloo-ui test`. Commit inside the submodule:

```bash
git -C repos/igloo-ui add package.json CHANGELOG.md && git -C repos/igloo-ui commit -m "Bump igloo-ui to 0.1.0; open [Unreleased] changelog"
```

---

### Task 6: dev/ disclosure handling

**Files:** modify `./.gitignore`; untrack `dev/audit/findings` + `dev/audit/archive`; correct `dev/HISTORY.md`.

- [ ] **Step 1:** Untrack the live findings + archived runs (keeps them on disk, removes from the tree going forward):

```bash
git rm -r --cached dev/audit/findings dev/audit/archive
```

- [ ] **Step 2:** Add to `./.gitignore` (preserving the framework — rules/, templates/, READMEs, RUNNER/TASKS, the existing NOTES negations):

```
# Audit run output — methodology (rules/, templates/) stays tracked; live
# findings + archived runs do not enter the public tree.
dev/audit/findings/
dev/audit/archive/
```

- [ ] **Step 3:** Confirm the framework is still tracked and the findings/archive are now ignored:

```bash
git status --porcelain dev/audit | head
git check-ignore dev/audit/archive dev/audit/findings
git ls-files dev/audit | grep -E "rules/|templates/|README|RUNNER|TASKS" | head
```
Expected: archive/findings deletions staged; both paths ignored; framework files still tracked.

- [ ] **Step 4:** Correct the stale plaintext claim at `dev/HISTORY.md:755`. The PWA recovery view now offers NIP-49 (`ncryptsec`) encrypted export and masks the nsec by default (it does **not** save plaintext). Update that checklist line to reflect the shipped state (mark done / reword) rather than leaving a misleading "currently saves the plaintext nsec" claim in a public log. Read the surrounding context first and edit minimally to match HISTORY's style.

---

### Task 7: Land it (pointer bumps + parent commit + gate)

- [ ] **Step 1:** Bump the submodule pointers (igloo-shared/pwa/home LICENSE commits + igloo-ui version commit):

```bash
make bump-pointers MSG="Bump clients: MIT LICENSE coverage + igloo-ui 0.1.0 (Phase 0 foundation)"
```

- [ ] **Step 2:** Commit the parent-root docs (stage explicitly — no `git add -A`):

```bash
git add LICENSE SECURITY.md CODE_OF_CONDUCT.md README.md .gitignore dev/HISTORY.md
# plus the staged dev/audit removals from Task 6
git commit -m "Add root LICENSE/SECURITY/CODE_OF_CONDUCT + beta banner; gitignore audit findings"
```

- [ ] **Step 3:** Gate:

```bash
npm --prefix test run test:guards   # doc/structure guards (docs changed)
make verify
```
Expected: guards pass; `make verify` green (`.tmp/agent/verify.json` `ok:true`).

---

## Self-Review

**Coverage:** license (Task 1), security policy (2), code of conduct (3), beta disclaimer (4), versioning (5), dev/ disclosure incl. the stale-HISTORY correction (6), landing+gate (7) — the full Phase 0 non-security foundation from the release plan. **Out of scope (correctly):** the broad non-security finding re-validation (C3/C6/C7 code-quality debt is normal public backlog, not a disclosure blocker) and the lingering C2/line-22 BACKLOG entry (left for a later finding-triage pass). **Placeholders:** none — LICENSE is a verbatim copy, SECURITY.md/README content is inline, CoC is the canonical v2.1 with one specified substitution, version target is exact. **Risk:** low; the only behavior-touching change is the igloo-ui version bump (guarded by its test run). The GitHub PVR *enablement* is an out-of-band maintainer settings action, flagged in Task 2.
