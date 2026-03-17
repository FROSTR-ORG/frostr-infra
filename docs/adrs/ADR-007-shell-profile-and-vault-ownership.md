# ADR-007: Shell Profile and Vault Ownership

## Status

Accepted

## Context

The hard-cut V2 shell model introduces shell-managed profiles, per-profile daemons, and encrypted local secret storage. Existing architecture decisions already establish:

- the shell daemon sits over `bifrost-app`
- live runtime execution goes through bridge, router, and signer
- daemon transport belongs above the bridge, not inside it

What remains to make explicit is the storage and ownership boundary between `igloo-shell` and `bifrost-rs`.

Without that boundary, secret-material handling, profile resolution, import/export behavior, and runtime bootstrap may drift into multiple crates with conflicting assumptions.

## Decision

`igloo-shell` owns profile manifests, vault records, unlock behavior, and shell-managed XDG storage layout.

`bifrost-rs` owns runtime execution from resolved material, not shell-managed local identity storage.

The boundary is:

- `igloo-shell` stores and resolves:
  profile manifests
  relay profiles
  encrypted vault records
  daemon metadata
- `igloo-shell` unlocks and decrypts secret material in memory when preparing daemon bootstrap
- `bifrost-app` accepts resolved in-memory bootstrap material and starts the runtime
- `bifrost-rs` must not depend on shell vault layout, keyring behavior, or shell-specific profile file conventions

Managed share material under shell control must be encrypted at rest. Runtime state persistence is distinct from vaulted import material and must not be treated as the source of truth for imported share/onboarding artifacts.

## Consequences

- shell storage can evolve without forcing runtime storage changes in `bifrost-rs`
- shell import/export and unlock policy remain a shell-domain concern
- browser, WASM, and mobile hosts do not inherit shell vault assumptions
- runtime state persistence remains reusable across hosts, while shell profile/vault behavior stays local to `igloo-shell`
- PRs that introduce shell-storage awareness into `bifrost-rs` should be treated as architectural drift
