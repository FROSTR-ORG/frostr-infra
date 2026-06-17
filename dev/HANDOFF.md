# Hand-off: lean dev/test-loop optimization — Threads 1, 2, 4, 5a, 5b DONE; Thread 3 next

_Last updated: 2026-06-17_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. The active program is **making the FROSTR dev/test/deploy loop fast
> and lean for the alpha**. The approved plan lives at
> `~/.claude/plans/twinkling-tinkering-phoenix.md` (read it — it has the full
> thread breakdown + verification steps). The prior L-task / MED+ / NIP-44 /
> crypto-port program is **complete and pushed** (recorded in `dev/BACKLOG.md` +
> git history); this handoff supersedes that one.

## TL;DR

The FROSTR infra was built for a multi-team, gated-release future that doesn't
exist yet; for a one-dev alpha that future-proofing is paid daily as overhead. We
approved a 5-thread plan and have **shipped Threads 1, 2, 4, 5a, 5b** (native
`make dev`, lean CI + `make verify`, CSS hot-reload, non-interactive scripts, and
the `make screenshot` render-and-verify tool with a runtime-injection seam). **One
thread remains: Thread 3** (root workspace + `make bump-pointers` + JSON/`READY`
output + `AGENTS.md` verification recipes + the doc reconciliation the CI cut
left). All work is committed on the `dev` branch (parent + the `igloo-pwa` /
`igloo-ui` submodules); **not yet pushed**.

## The user

`cmdruid` (git), the FROSTR maintainer — senior, terse, wants signal over
ceremony. Decisive on scope. This session he gave broad authority: "This is an
alpha: we have the authority to build the project however we want… make our
development cycle fast and lean." He picks options decisively when asked and
prefers commits to follow the **submodule-first → bump-pointer** flow. He asks for
a follow-up harvest before each new thread (the `follow-up` skill → `dev/BACKLOG.md`).

## The project

`frostr-infra` is the coordinating workspace for FROSTR: a Rust signing core
(`repos/bifrost-rs`, native + browser WASM) wrapped by TypeScript `igloo-*`
clients (`repos/igloo-{shared,ui,pwa,chrome,home,shell,paper}`), all git
submodules under `repos/`. The **Makefile is the public command surface**;
`scripts/`, `dev/scripts/`, `test/scripts/` are private impl behind it.

**Known facts for the lean-dev program:**
- Target dev loop is minimal: one relay + one `igloo-shell` co-signer + a webserver
  serving `igloo-pwa`. Optimize for *edit → see it → test-what-matters in seconds*.
- **Decisions (confirmed by the user):** **hybrid repo structure** (keep submodules,
  add a root workspace + a pointer-bump helper — NOT a full monorepo);
  **aggressive** test/CI cuts; **agent-first ergonomics** (fast, deterministic,
  non-interactive, machine-readable, scriptable-state, lightweight-render).

## What's been done (this program — all on `dev`)

Commits, newest first (parent unless noted):

- `1e07818` backlog harvest (dev-scenario follow-ups)
- `9789ae9` **`make screenshot`** (agent render-and-verify tool) + bumps `igloo-pwa`
  to `2a869f4` **(igloo-pwa: `src/lib/dev-scenario.ts` seam + `store.tsx` wiring)**
- `7b98600` harden the `make dev` daemon socket path
- `d4a7022` backlog harvest (native `make dev`)
- `db2b0fb` **native `make dev`** + `dev/fixtures/` + retire Docker `demo-pwa`
- `4b4461f` backlog harvest (lean CI)
- `447cc03` **`make igloo-ui-watch`** (CSS hot-reload)
- `c1a8bff` **lean test/CI gate + `make verify`**
- `cdd85ad` **non-interactive `igloo-pwa-dev`** (`FROSTR_NONINTERACTIVE=1`)
- (earlier, same session, separate sub-efforts also on `dev`: the global
  profile-store storage refactor `828870e`, the Paper signer-dashboard redesign
  `e3cce71`, and the Docker demo fixes `4167f73`/`bf17e52` — all done + committed.)

**New tools the next agent (and the user) now have:**
- `make dev [PORT=]` — native relay + `igloo-shell` co-signer (from `dev/fixtures/`)
  + vite, in a few seconds. Ctrl-C tears everything down. First run only: in the
  PWA, *Import Existing Device* with `dev/fixtures/dev-device.bfprofile`, password
  `devpass`, then Unlock + Start Signer. Verified up to vite (HTTP 200); the
  in-browser import + signing is still a manual check.
- `make screenshot STATE=<dashboard-running|dashboard-stopped|welcome-returning>` —
  renders a PWA screen headlessly via the `?__frostr_dev=<scenario>` seam and
  writes a PNG **and a visible-text dump** to `.tmp/agent/`. **This renders the
  running dashboard** (peers/event log) that storage-only seeding couldn't reach.
- `make verify` — lean guards + typecheck + `@fast` e2e (the canonical "did I break
  anything" gate; also the PR CI gate).
- `make igloo-ui-watch` — tailwind `--watch` so igloo-ui CSS edits hot-reload.
- `FROSTR_NONINTERACTIVE=1` — auto-resolves a busy port in `igloo-pwa-dev` (no hang).

**Key infra changes:** `test:guards` cut to `targets`+`wasm` (~60s → ~1.3s; old
chain preserved as `test:guards:full`). `.github/workflows/release-validation.yml`
moved off every PR to **nightly + `workflow_dispatch`**. PR pwa lane runs `@fast`
not `@visual`.

## What's pending (priority order)

1. **Thread 3** (the remaining thread): root `package.json` npm workspace over
   `repos/igloo-{shared,ui,pwa,chrome,home}`; `scripts/bump-pointers.sh` +
   `make bump-pointers` (stage every dirty submodule pointer + commit in one step);
   JSON/`READY` output modes for `make dev`/`make screenshot`/`make verify`; and an
   **`AGENTS.md` "Verification recipes"** section. **Fold in the doc reconciliation**
   here — see #2.
2. **Reconcile docs + nightly `test:guards:full`** (BACKLOG, Test harness/CI):
   the lean-CI cut left `test/README.md` + `dev/docs/WORKFLOWS.md` stale and the
   command-surface guard out of sync, so the nightly `test:guards:full` is likely
   **red**. Update docs/guard or formally demote nightly-full to advisory.
3. **Tracked BACKLOG follow-ups** (not blocking): gate `dev-scenario` behind
   `import.meta.env.DEV` (prod safety, S); `agent-screenshot.spec.ts` bypasses the
   page-object selector contract (nightly-only, S); finish deleting the de-gated
   visual + low-value guard files (M); zero-import auto-seed for `make dev` (M);
   `make verify` affected-aware (S); WASM watch + drop committed-WASM
   double-maintenance (M); signer-core ~18s onboard-ready + ~12s/export perf (L);
   `dev.sh` socket path uses an ad-hoc shortener vs the established helper (S).

## Critical considerations (the WHY)

- **Hybrid, not monorepo.** The user explicitly chose to keep the 8 submodules and
  add a workspace + pointer-bump helper, because a full monorepo would couple
  unrelated platforms; revisit the monorepo only if the hybrid friction persists.
- **Commit flow:** commit *inside the submodule first*, then bump the pointer in the
  parent (the whole point of `make bump-pointers` in Thread 3). Use **non-recursive**
  submodule commands.
- **igloo-ui source-vs-dist gotcha:** the pwa resolves igloo-ui **JS from source**
  (vite alias) but **CSS from `igloo-ui/dist/styles.css`** — so after any igloo-ui
  CSS change you must rebuild igloo-ui's dist (or run `make igloo-ui-watch`), or the
  pwa shows stale styles. (This bit us repeatedly.)
- **`dev/fixtures/` are throwaway devnet keys** for a local relay, committed on
  purpose (alpha) so `make dev` never keygens/onboards. Password `devpass`. Never
  reuse for anything real. Regenerate with `dev/fixtures/regen.sh`.
- **The `dev-scenario` seam is dev/test-only** (reads `?__frostr_dev=`), renders a
  *fake* in-memory runtime (no real keys/signing) — it is for screenshots, NOT for
  `make dev`'s real signing. It currently runs in any build; gating it behind
  `import.meta.env.DEV` is a tracked S follow-up.
- **Native binaries** (`repos/bifrost-rs/target/debug/bifrost-devtools`,
  `build/igloo-shell-target/debug/igloo-shell`) are already built; `make dev`/regen
  rebuild via `scripts/test-prebuild.sh sync shared` if missing. `keygen` is local
  (no relay needed). Daemon control socket must fit the macOS `sun_path` limit (104)
  — keep `XDG_RUNTIME_DIR` short.
- **Nothing is pushed yet.** All commits are local on `dev` (parent + igloo-pwa +
  igloo-ui). Push when the user asks. `make test-fast` is the pre-push gate.

## Suggested first action

Start **Thread 3**: create the root `package.json` with `"workspaces":
["repos/igloo-shared","repos/igloo-ui","repos/igloo-pwa","repos/igloo-chrome",
"repos/igloo-home"]` (private, no version), run `npm install` at the root, and
verify each client still builds + its vite dev server resolves igloo-ui/igloo-shared
from source (the per-repo `vite.resolve.ts` aliases stay authoritative). Then add
`scripts/bump-pointers.sh` + `make bump-pointers`. Read
`~/.claude/plans/twinkling-tinkering-phoenix.md` (Thread 3 section) first.
