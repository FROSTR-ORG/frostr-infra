# FROSTR Remediation Handoff — 2026-05-20

This document captures the live state of the remediation track derived
from the 2026-04-22 workspace audit. Use it to resume work on a different
machine without re-deriving context.

## What this work is

A multi-bucket, multi-PR remediation track that lands hard-cut security +
quality fixes across the FROSTR workspace. The driver document is
`/home/cscott/Repos/frostr/frostr-infra/dev/plans/remediation-2026-04-22/README.md`.
The audit it remediates lives in `dev/audit/`.

**Hard-cut style:** every rename / version bump / API change lands
atomically with its consumer migration. No transitional shims, no
back-compat re-export layers. Operators re-onboard once per coordinated
release.

**Subagent execution:** one subagent per PR. Each subagent works in a
feature branch inside the affected submodule; the user reviews the branch
diff before merge.

**Three coordinated releases:** R1 (security hardening, Buckets A–F),
R2 (structural refactor, Buckets G+H), R3 (tests + docs, Buckets I+J).

## Release sequencing

| Release | Buckets | PRs | Status |
|---|---|---|---|
| R1 | A + B + C + D + E + F | 28 (some +follow-ups) | **C is finishing — see PR12 below** |
| R2 | G + H | ~10 | Not started |
| R3 | I + J | 8+ | Not started |
| Backlog | K | 18 deferred items | Not scheduled |

## R1 Bucket status

### Bucket A — `bifrost-rs` crypto primitives (PRs 1–4) — ✅ Complete

All four PRs merged to `bifrost-rs/master`. Earliest commit `f6c4df7`,
latest `0983f98`. Adds `bifrost-core::secret` newtypes (`SharePrivateKey`,
`NoncePoolSecret`, `EcdhSharedSecret`, `RecoveredSigningKey`,
`FileStoreKey`), CT MAC compare via `subtle`, envelope bounds in
`bifrost-codec`, `DeviceState` split with `DeviceStatePersisted` DTO
(`VERSION` 5→6), and consolidates the three NIP-44 stacks into
`bifrost-core::nip44` with frozen KATs.

### Bucket B — KDF + AEAD + AAD (PRs 5–7) — ✅ Complete

All three PRs merged to `bifrost-rs/master`. Argon2id (256 MiB / t=4) +
XChaCha20Poly1305 envelope v2; explicit `Argon2Params` with `#[non_exhaustive]`;
domain-separated length-prefixed AAD; raw 16-byte salt; v1 readers removed.
Bumps `ENCRYPTED_PROFILE_VERSION` 1→2 and `BF_PACKAGE_VERSION` 1→2.

### Bucket C — host-local secret hygiene (PRs 8–12 + 12b) — 🟡 PR12 in flight

| PR | Submodule | Status |
|---|---|---|
| PR8 — fs_guard helpers + atomic writes | `bifrost-rs` | ✅ merged (`50d758c`) |
| PR9 — `Passphrase` + `DaemonToken` newtypes | `bifrost-rs` | ✅ merged (`1c3d059`) |
| PR10 — daemon auth + stdin passphrase | `bifrost-rs` | ✅ merged (`0f96098`) |
| PR11 — `UnlockSession` + rotation intent journal | `bifrost-rs` | ✅ merged (`55e75c4`) |
| PR12b — bifrost-profile env-fallback removal | `bifrost-rs` | ✅ merged (`1414d6b`) |
| PR12 — consumer migration | `igloo-shell` | 🟡 branch `remediation/pr12-igloo-shell-bucket-c-migration`, tests running |

#### PR12 resume point

- Branch tip: `cb29a14` (igloo-shell)
- Latest activity: `cargo test --workspace --offline` running ~19 min,
  background process PID `3805137`, output file
  `/tmp/claude-1000/-home-cscott-Repos-frostr-frostr-infra/3450a3fa-b367-40be-8582-5213dd141677/tasks/bb4xcpl4n.output`
- Agent reported: workspace compiles clean; targeted greps for the five
  env-var patterns return empty; all 28 unit / 57 integration tests passed
  individually with bumped budgets. Full-workspace run was finalising at
  handoff time and **may have completed by the time this is read** —
  check the output file first.
- Next steps if tests are green:
  1. `cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-shell && git checkout master && git merge --ff-only remediation/pr12-igloo-shell-bucket-c-migration`
  2. `git branch -d remediation/pr12-igloo-shell-bucket-c-migration`
  3. Update parent-repo submodule pointers (see "End-of-R1 coordination").
- If tests fail: the agent flagged that the Argon2id double-KDF cost
  (parent + spawned daemon) sometimes pushes daemon-ready waits over the
  original budget. First-line debug is bumping the `wait_for_runtime` and
  `run_for_a_bit_with_env` timeouts in `crates/igloo-shell-cli/tests/support/mod.rs`.

### Bucket D — browser-host secret hygiene (PRs 13–17) — ✅ Complete

Five PRs landed across `igloo-shared` (PR13), `igloo-pwa` (PR14, 16, 16b,
17), and `igloo-chrome` (PR15). Added `Secret<T>` / `SecretBytes` TS
wrappers, `EVENT_SCHEMAS` allow-list redactor, `request_id`-keyed bridge
dispatch (Map + `stale_completion`), `RuntimeReadinessTimeoutError`,
per-instance `SessionController` with monotonic `SessionEpoch`. PR16b
stripped `share_package_json` from persisted PWA state (red-team grep
confirms 0 occurrences).

### Bucket E — shell hardening (PRs 18–24) — 🟡 mostly complete

| PR | Scope | Submodule | Status |
|---|---|---|---|
| PR18 — Tauri CSP + capabilities | `igloo-home` | ✅ merged |
| PR19 — PWA CSP + COOP/COEP | `igloo-pwa` | ✅ merged (`a1b0f95`) |
| PR19 (Chrome side) — manifest CSP | `igloo-chrome` | ✅ merged (`6dfe68d`) |
| PR20 — WASM SHA-384 integrity | `bifrost-rs` + `igloo-shared` | 🔴 deferred |
| PR21 — test-mode server gating | various | ✅ merged |
| PR22 — path canon under allowed roots | `igloo-home` | ✅ merged (`33285e1`, `85ddd69`) |
| PR23 — typed Tauri IPC errors | `igloo-home` | ✅ merged + follow-up fix (`102c377`) |
| PR24 — Tauri passphrase newtype migration | `igloo-home` | 🔴 deferred (depends on PR9 — now unblocked) |

**Remaining E work:**
- **PR20:** WASM SHA-384 subresource integrity. Multi-repo (bifrost-rs
  emits hashes during build; igloo-shared and the host bundlers verify
  them). Plan: `dev/plans/remediation-2026-04-22/bucket-e-shell-hardening.md`
  section E.5.
- **PR24:** Wire the new `Passphrase` newtype (Bucket C PR9) through the
  Tauri IPC layer in `igloo-home`. Sibling to Bucket C PR12 but in a
  different host.

### Bucket F — workspace hardening (PRs 25–28) — ✅ Complete

Four PRs merged to the parent `frostr-infra` master (commits `7daf56a`,
`25b53a8`, `8f0ba93`, `44c2308` plus follow-ups for harness CI / xvfb
/ test-server feature gating). Non-root containers, `:ro` mounts,
`.env.example` cleanup, `data/` removal from VCS, GitHub Actions SHA
pinning, least-privilege workflow permissions, concurrency guards,
`npm ci` for test deps, demo entrypoint refactor.

## End-of-R1 coordination (after PR12 merges)

R1 lands as a single coordinated operator-migration event. Once Bucket C
is closed and PR20 / PR24 land:

1. From the parent `frostr-infra` master, `git add` the submodule
   pointers for every R1-touched repo (currently dirty per `git status`:
   bifrost-rs, igloo-chrome, igloo-home, igloo-pwa, igloo-shared,
   igloo-shell).
2. One commit titled along the lines of
   `Bump submodule pointers for R1 coordinated release`.
3. **Local-only.** Do not push without explicit user say-so.

The submodule pointer update is one commit, not 28; everything inside
the submodules is already merged to their respective `master` branches.

## Conventions in force

These were chosen explicitly by the user during execution and apply to
all future work in this track unless overridden.

- **One agent per repo at a time.** Parallel agents touching the same
  submodule cause branch-state races. Two earlier incidents (PR25/PR27
  in parent, PR28 in submodule) recovered via rebase; the rule is firm
  now.
- **Hard-cut.** No shims, no feature flags, no transitional re-export
  layers. Alpha allows this; fewer moving parts during review.
- **Local merges only.** Subagents do NOT push; the user reviews each
  branch's diff before the assistant merges.
- **`security-hardening` is the integration branch in every repo.** All
  remediation PRs land on `security-hardening`, not `master`. `master` in
  each repo (and in the parent) stays equal to `origin/master` until the
  work is reviewed end-to-end and explicitly cut over. Created 2026-05-20
  as a single batched move once the user decided the local divergence
  should not sit on `master`.
- **Merge style (onto `security-hardening`):**
  - **Submodules:** fast-forward only (`git merge --ff-only`). Linear
    history per repo.
  - **Parent repo:** `--no-ff` so each release boundary leaves a merge
    commit summarising the bundle.
- **No `Co-Authored-By` trailers.** Per `~/.claude/CLAUDE.md`.
- **DTOs over feature flags.** Persistence/wire shapes get explicit DTO
  types when their in-memory counterpart loses serde
  (`SharePackageWire`, `DeviceStatePersisted`, `ControlRequestWire`).
- **Secrets via newtypes.** `ZeroizeOnDrop`, redacted `Debug`, no serde,
  no `Clone` derive (explicit `clone_secret()`), constant-time
  `PartialEq` for 32-byte tokens via `subtle::ConstantTimeEq`.
- **NIP-44 byte-compat is non-negotiable.** Every cipher refactor pins
  KATs before changing code, then re-runs them after.

## Repo HEAD snapshot (2026-05-20)

Every repo now has two branches: `master` (pristine, equal to
`origin/master`) and `security-hardening` (the integration branch
holding all remediation track + pre-remediation onboarding-status work).
Active branch in each repo is `security-hardening`.

| Repo | `security-hardening` HEAD | `master` (== origin/master) | Notes |
|---|---|---|---|
| `frostr-infra` (parent) | `e70ece4` | `4c43ef3` | 26 commits on `security-hardening`; submodule pointers reference the security-hardening tips of each submodule |
| `repos/bifrost-rs` | `1414d6b` | `4a9d4f8` | 43 commits; Buckets A, B, C (through PR11 + PR12b) |
| `repos/igloo-shell` | `cb29a14` | `24248c0` | 4 commits; PR12 (Bucket C consumer migration) awaiting test result then merge → branch tip stays |
| `repos/igloo-shared` | `9b2d602` | `7f9c8ab` | 12 commits; Bucket D complete |
| `repos/igloo-pwa` | `a1b0f95` | `e12f2e5` | 12 commits; Buckets D + E (PR19) complete |
| `repos/igloo-home` | `102c377` | `eed7b7a` | 21 commits; Bucket E PR18/22/23 complete; PR24 deferred |
| `repos/igloo-chrome` | `6dfe68d` | `1d92ce0` | 2 commits; Bucket E PR19 complete |
| `repos/igloo-ui` | `87f2ac5` | `32b6188` | 1 commit (onboarding-status feature, pre-remediation); will gain Bucket H work later |
| `repos/igloo-paper` | (detached) | `8f29f71` | Reference-only; not touched |

Note: igloo-shell's `security-hardening` is the renamed
`remediation/pr12-igloo-shell-bucket-c-migration` branch — same commits,
new name. Once PR12's test run completes and merges, the next R1 PRs
(PR20, PR24) will land on top of `cb29a14`.

## R2 / R3 dispatch entry points

When R1 closes and the user is ready:

- **R2 (Buckets G + H, ~10 PRs)** — TS structural refactor + UI hardening.
  Plans at `dev/plans/remediation-2026-04-22/bucket-g-runtime-types.md` and
  `bucket-h-ui-hardening.md`. Bucket G touches `igloo-shared` and the
  three browser hosts; Bucket H touches `igloo-ui` + `igloo-pwa`. Largest
  single PR: G PR30 (split `browser-runtime-core.ts` monolith).
- **R3 (Buckets I + J, 8+ PRs)** — residual test coverage + docs +
  `igloo-chrome` re-audit. Plans at `bucket-i-test-coverage.md` and
  `bucket-j-docs-chrome.md`.
- **Bucket K (backlog)** — 18 deferred items. Not an execution track;
  scheduled when triggers fire. Register at `bucket-k-deferred-register.md`.

Operator-impact summary for R1's coordinated release lives at the bottom
of `dev/plans/remediation-2026-04-22/README.md`.

## Live caveats / known follow-ups

- **frostr-infra harness env-var references:** the `test/` directory may
  still reference retired env vars (`IGLOO_SHELL_PROFILE_PASSPHRASE`,
  `IGLOO_SHELL_ONBOARDING_PASSWORD`). Out of scope for PR12; flag for a
  sibling clean-up before R1 closes if the demo-smoke breaks.
- **bifrost-rs WASM bridge doesn't echo `request_id`** — PR14 in
  `igloo-shared` worked around this with a client-UUID map + per-kind
  FIFO tombstone. Future bifrost-rs simplification candidate.
- **Pre-existing clippy errors on `bifrost-profile` and
  `bifrost-app::runtime::health.rs`** are unrelated to this track; flagged
  so future agents don't waste time on them.
- **Argon2id double-KDF cost** in the parent + spawned daemon path made
  several `igloo-shell` integration tests flaky under the original
  timeouts. PR12 bumped them; if more flakes appear elsewhere, that's the
  first thing to check.
- **`data/` scratch dir leak.** Demo harness was writing live secrets
  (daemon tokens, onboarding passwords, sockets) to `data/test-harness/`
  in the workspace root, even though `CLAUDE.md` and PR26 mandate
  `.tmp/test-harness/`. Worked around 2026-05-20 by adding `data/` to the
  parent `.gitignore`. Root cause not yet identified — candidates:
  shell-level `FROSTR_TEST_HARNESS_DIR` export, a stale script in
  `repos/igloo-shell/scripts/`, or a docker-compose mount path. Trace
  next session via `rg 'data/test-harness' --no-ignore` or by checking
  `scripts/lib-scratch.sh::resolve_workspace_scratch_dir`.

## Where to read next

- `dev/plans/remediation-2026-04-22/README.md` — the master plan index.
- `dev/audit/workspace-audit-synthesis-2026-04-22.md` — the audit that
  drives this work.
- `dev/audit/` — per-repo audit reports.
- `dev/docs/RELEASE.md` — coordinated-release process.
- `dev/plans/remediation-2026-04-22/bucket-c-secret-hygiene.md` — the
  in-flight bucket's plan.

## Resume prompt

To pick this up on a new machine:

> Continuing the FROSTR remediation track from `dev/HANDOFF.md`. All
> repos including the parent have `security-hardening` as the active
> integration branch (`master` everywhere is pristine at `origin/master`).
> R1 Bucket C is the live bucket; PR12 (igloo-shell consumer migration)
> was awaiting full-workspace test results when the session paused. Check
> the branch state in `repos/igloo-shell` and the test output at the path
> captured in HANDOFF.md, then merge into `security-hardening` if green
> (fast-forward), fix if not. After Bucket C closes, finish R1 by
> tackling PR20 (WASM integrity) and PR24 (Tauri passphrase migration),
> then bump parent-repo submodule pointers as the coordinated R1 commit
> on the parent's `security-hardening` branch.
