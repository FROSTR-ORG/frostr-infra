# Legacy & deprecation

Judges code that has outlived its reason to exist: compatibility shims, retired
APIs still wired in, version-suffixed forks, and dead branches. The danger isn't
that this code is wrong — it's that it's *load-bearing by accident*, and every
reader has to keep it in their head.

## What good looks like

- Shims and migrations carry a written removal trigger and disappear once met.
- One canonical path per concern — not a `_v1` next to a `_v2` next to the real one.
- Retired surfaces are deleted, not commented out or left importable.
- Version-guarded branches are reachable; dead arms are pruned.

## Rules

### LEG-01 — Compatibility shim without a removal trigger
- **Severity:** Medium
- **Look for:** identifiers / files containing `compat`, `shim`, `bridge`, `adapter`, `polyfill`, `fallback`, `legacy`; comments like "temporary", "for now", "until".
- **Fails when:** a shim exists with no documented condition for its removal (a date, a version, a migration milestone, a tracking link).
- **Passes when:** the shim is documented with a removal trigger, or there is no shim.
- **Prompt:** "Is this bridging a real, finite migration — or is it permanent debt wearing a temporary label?"

### LEG-02 — Version-suffixed parallel implementations
- **Severity:** Medium
- **Look for:** `*_v1`, `*_v2`, `*-old`, `*-new`, `*-next`, `*-legacy` in file or symbol names (e.g. `package_v2.rs`, `encryption_v2.rs`, `run_marker_v2.rs`).
- **Fails when:** an old and new variant both ship and both are reachable, with no note on which is canonical or when the old one retires.
- **Passes when:** only the canonical variant ships, or the suffix marks an intentional, documented wire/format version (not a code fork).
- **Prompt:** "If both versions exist, which one is real — and what keeps a new caller from picking the wrong one?"

### LEG-03 — Retired API still wired in
- **Severity:** High
- **Look for:** exports/commands/env names that docs, `.env.example`, or READMEs describe as removed (e.g. references to `igloo-server`, `igloo-web`, `igloo-cli`); `check-no-legacy-surfaces.sh` exists to police exactly this.
- **Fails when:** a surface documented as retired is still exported, dispatched, or referenced in config.
- **Passes when:** retired surfaces are gone from code and config, and the guard passes.
- **Prompt:** "Does anything still answer to a name we told people we removed?"

### LEG-04 — Dead or unreachable code
- **Severity:** Medium
- **Look for:** `#[allow(dead_code)]`, unused exports, functions with no callers, branches gated on a constant, `if (false)`, orphan view states that render nothing.
- **Fails when:** code cannot be reached on any real path and isn't a documented public-API surface.
- **Passes when:** unreachable code is deleted; intentionally-unused public surface is marked and explained.
- **Prompt:** "If I delete this, what breaks — and can I prove it from a real call path?"

### LEG-05 — Commented-out code kept as memory
- **Severity:** Low
- **Look for:** blocks of commented-out statements; "kept for reference"; large `/* ... */` spans of former code.
- **Fails when:** former code is parked in comments instead of git history.
- **Passes when:** dead code is deleted (git remembers it); comments explain *why*, not *what used to be*.
- **Prompt:** "Is this comment explaining the code, or hoarding a version of it git already has?"

### LEG-06 — Stale generated / vendored artifact
- **Severity:** Medium
- **Look for:** checked-in generated output (WASM JS bindings, stamps) that can drift from its source — browser WASM blobs in particular can fall behind `bifrost-rs`.
- **Fails when:** a generated/vendored artifact is older than its source and there's no regeneration command documented near it.
- **Passes when:** the artifact is regenerable by a documented command, and freshness is enforced or obvious.
- **Prompt:** "Was this built from the current source — and how would a reader rebuild it?"

## Review prompts

- What in this file is here only to support something that no longer exists?
- If two ways to do one thing are present, which is canonical and what retires the other?
- Could this be deleted today with a one-line justification?
