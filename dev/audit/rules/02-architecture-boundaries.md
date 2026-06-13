# Architecture & boundaries

Judges where responsibilities live and how cleanly they're separated: god files,
mixed-concern modules, layering violations, and leaky package boundaries. In this
workspace the recurring failure is the **"monolith per host"** — each client
grows a 1k–4k-line control-plane file that re-expresses signer truth locally.

Reuse the drift signals in
[`../../policies/architecture-guidance.md`](../../policies/architecture-guidance.md);
this domain applies them across the whole tree rather than to one PR.

## What good looks like

- Signer logic lives in `bifrost-rs`; browser/desktop hosts stay thin.
- A file has one reason to change; responsibilities don't pile up in a root component.
- Packages export a curated surface, not everything.
- Protocol decisions live in the core, not re-derived in UI code.

## Rules

### ARC-01 — God file
- **Severity:** High
- **Look for:** source files (excluding tests/generated) over **800 LOC**; scrutinize anything over **1200**. Known hotspots: `bifrost-signer/src/lib.rs` (~4.3k), `igloo-pwa/src/lib/store.tsx` (~2k), `igloo-home/src/App.tsx` (~2k), `igloo-ui/.../CreateFlow.tsx` (~1.7k).
- **Fails when:** a file is large *and* holds multiple responsibilities (state machine + I/O + policy + view, etc.).
- **Passes when:** the file is large but cohesive (a single generated table, one exhaustive match), or it's split along its seams.
- **Prompt:** "How many distinct reasons does this file have to change? Name them."

### ARC-02 — Mixed responsibilities in one module
- **Severity:** Medium
- **Look for:** a component or module that owns layout *and* policy state *and* I/O *and* polling (e.g. a `peer-list` doing layout + ping state + nonce visualization).
- **Fails when:** unrelated concerns are interleaved such that you can't change one without reading all.
- **Passes when:** concerns are separated into focused units with clear inputs/outputs.
- **Prompt:** "Could a newcomer change the layout here without understanding the network code?"

### ARC-03 — Host re-derives signer truth
- **Severity:** High
- **Look for:** browser/desktop code inferring state from local heuristics, polling on intervals where a subscription/signer API exists, or re-modeling bifrost types locally with `as` casts.
- **Fails when:** the host computes something the signer core already owns (or should own).
- **Passes when:** the host reads signer-owned status; protocol decisions live in `bifrost-rs`.
- **Prompt:** "Is this host-side heuristic compensating for a missing signer API?"

### ARC-04 — Leaky package boundary
- **Severity:** Medium
- **Look for:** `export *` re-exporting an entire module set with no curation; host-specific names bleeding into shared packages (e.g. `igloo-pwa-*` CSS classes inside `igloo-ui`); cross-repo imports `check-cross-client-imports.sh` would flag.
- **Fails when:** a package exposes its whole interior, or a shared package encodes one consumer's specifics.
- **Passes when:** exports are deliberate; shared code is host-agnostic.
- **Prompt:** "Does a consumer of this package see a designed surface, or its whole drawer of internals?"

### ARC-05 — Duplicated logic across hosts/crates
- **Severity:** Medium
- **Look for:** near-identical helpers re-implemented per host (e.g. several `browser-profile-*` packages re-wrapping one save/finalize flow; repeated NIP-44 cipher stacks across crates).
- **Fails when:** the same behavior is maintained in N places and drifts between them.
- **Passes when:** shared behavior has one home the others import.
- **Prompt:** "If this logic has a bug, how many files do I fix — and would I remember all of them?"

### ARC-06 — Cross-repo contract drift
- **Severity:** High
- **Look for:** a host's local copy of a signer/wire shape diverging from the source; a test dispatcher that re-declares the real command surface (igloo-home's duplicate test dispatcher is the canonical example).
- **Fails when:** two sides of a contract are maintained independently and can silently disagree.
- **Passes when:** the contract has a single typed source both sides consume.
- **Prompt:** "What stops this local shape from drifting away from the real one — a type, a test, or nothing?"

## Review prompts

- Where does this responsibility *belong* — and is it there?
- What's the single source of truth for this shape, and does everyone read it?
- If I split this file along its seams, what are the seams?
