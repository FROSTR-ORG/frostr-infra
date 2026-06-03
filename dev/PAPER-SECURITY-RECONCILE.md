# Paper ↔ security-hardening reconciliation — resume notes (2026-06-03)

R1+R2+R3 are complete and pushed to `origin/security-hardening` (all repos).
While we worked, a parallel **Paper UI** track advanced on `origin/master` +
`origin/paper-create-flow-update`. This note tracks reconciling the two before
the L2 cutover. **Nothing here is pushed; `master` and the Paper branch are
untouched.**

## Topology (forked ~2026-04-13 from a common base)

- `origin/master` = old base + **Paper foundation** (parent +33).
- `origin/paper-create-flow-update` = master **+41** (more Paper: Settings/
  Permissions/dashboard alignment, password modals, chrome MV3 wasm fix, docker
  follow-ups). `ahead=41, behind=0` of master — a clean superset.
- `origin/security-hardening` = old base + our R1/R2/R3 (a66c2a1 parent).
- Both tracks restructure the **UI** (Paper design system vs our Bucket H) AND
  the **backend** (Paper landed "onboard-served completion + signer/runtime WIP"
  in bifrost-rs/shell/shared, overlapping our crypto/secret hardening).

## Decisions (locked with the operator)

- **Strategy A:** per repo, branch at the **Paper tip**, `git merge
  security-hardening`, resolve, then ff `master` to the result. Submodules first
  (so the parent's pointer conflicts resolve against reconciled submodules), then
  the parent. Local only until reviewed; re-validate (`make test-release`) before
  cutover/push.
- **UI conflicts (igloo-ui, igloo-pwa): Paper wins, re-layer security.** Paper's
  design system / `styles.css` / primitives are canonical; re-apply only the
  security *behavior* on top where Paper doesn't cover it: `SensitiveField`
  mask-by-default, `Dialog` focus-trap/scroll-lock/Escape-stack, `LogEntry`
  bounds.
- **Backend conflicts: both-keep.** Preserve our hardening AND Paper's feature,
  reconciled per hunk.

## Per-submodule Paper tips (merge target = `git ls-tree origin/paper-create-flow-update repos/<x>`)

| repo | paper tip | sec tip | paper Δ vs sec | notes |
|---|---|---|---|---|
| bifrost-rs | 7a41c3b | d0bf343 | +1 / -48 | **DONE** |
| igloo-shell | a6eece3 | 7bf3ff4 | +2 / -6 | **DONE** |
| igloo-shared | e617db1 | 303514d | +4 | wasm/loader, index.ts, rotation.ts |
| igloo-chrome | ee45a64 | 5410f1d | +7 | wasm binaries (regen); needs igloo-ui reconciled for full e2e |
| igloo-pwa | 007754e | 1044edc | +30 | HARD: Paper flows vs App/store/types; Paper-wins |
| igloo-ui | 66f144a | 24e3b81 | +33 | HARDEST: Paper design hard-cut; Paper-wins re-layer |
| igloo-home | eed7b7a | d99c987 | 0 | already current |
| igloo-paper | 38d734f | (none) | — | reference submodule; take Paper tip |

## Progress

- **bifrost-rs** — reconciled on local branch `reconcile/paper+security`
  (`dab2b94`). 3 git conflicts (both-keep): bridge-wasm imports (security
  superset), signer onboard handler (kept BOTH `OnboardServed` completion AND
  `note_onboarding_status`), verify/keyset tests. Plus semantic ripples: Paper's
  WIP used pre-hardening raw bytes where our newtypes now exist —
  `recovered.signing_key32.expose_bytes()`, and `CreateKeysetConfig::new()` +
  the new `signing_key32` field (converted our struct-literal test sites).
  **`cargo test --workspace` all pass** (R3 FROST/nonce/codec/router + Paper's
  onboard-served + bridge round-trips).
- **igloo-shell** — reconciled on local branch `reconcile/paper+security`
  (`479bfbd`). **0 git conflicts**; clean `cargo check --workspace`; lib tests
  pass. (Full managed_integration deferred to final validation.)

## The pattern that works

1. `git checkout -b reconcile/paper+security <paper-tip>` in the submodule.
2. `git merge --no-edit security-hardening`.
3. Resolve git conflicts (UI: Paper-wins; backend: both-keep).
4. `cargo check`/`tsc --noEmit` — fix the **semantic** ripples git didn't flag
   (Paper code using raw bytes vs our secret newtypes → `expose_bytes()`; old
   `CreateKeysetConfig` struct literals → `::new`).
5. Build + test; `cargo fmt`/lint; commit the merge.

## Remaining order

igloo-shared → igloo-chrome (regen wasm; full e2e after igloo-ui) → **igloo-ui**
(Paper-wins re-layer — the real work) → **igloo-pwa** → parent (reconcile
submodule pointers to the reconciled tips + `test/igloo-pwa/specs/app-shell.spec.ts`
our v2-seed fix vs Paper's PWA test wiring + CI/scripts/`AGENTS.md`). Then ff each
`master` to its reconciled tip, re-run `make test-release` on infra, then push.

## State to restore on resume

The reconcile branches persist in each submodule. bifrost-rs + igloo-shell are
left checked out on `security-hardening` (clean parent tree); their reconcile
branches hold the work (`git -C repos/bifrost-rs branch` → `reconcile/paper+security`).
Pre-existing env notes: `rg` is a shell-function shim (real binary at
`/usr/share/codium/.../@vscode/ripgrep/bin/rg`); background subagents are
read-only here (do mutations in the main thread).
