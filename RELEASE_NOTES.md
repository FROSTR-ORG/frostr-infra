# Release Notes

## 2026-03-28 Workspace Beta

This checkpoint prepares the FROSTR workspace for a coordinated beta release across the changed repos.

Released repo versions:
- `bifrost-rs` `v0.5.0`
- `igloo-shared` `v0.1.0`
- `igloo-pwa` `v0.2.0`
- `igloo-chrome` `v0.3.0`
- `igloo-shell` `v0.2.0`
- `igloo-home` `v0.2.0`

Highlights:
- Shared profile and backup payloads now preserve structured `group_package` data end to end.
- `group_name` replaces the old top-level keyset metadata and is carried inside `group_package`.
- Remote peer policy observations are runtime-only state and no longer part of durable profile or backup state.
- `igloo-shell` ships as a CLI-only operator host with `rotate-key` and `rotate-keyset` workflows and expanded shell coverage.
- Browser and desktop hosts now align on the current onboarding, recovery, rotation, and embedded group-metadata model.
- Shared docs were tightened into a release-ready beta manual for protocol, interfaces, cryptography, profiles, backups, onboarding, rotation, and wire behavior.

Verification completed for this checkpoint:
- `bifrost-rs`: `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --offline --no-deps -- -D warnings`, `cargo check --workspace --offline`, `cargo test --workspace --offline`
- `igloo-shell`: `cargo test -p igloo-shell-cli --offline`, `bash scripts/devnet.sh smoke`, `bash scripts/test-node-e2e.sh`
- `igloo-home`: `bunx tsc --noEmit`, `npm run test:unit`, `cargo check --manifest-path src-tauri/Cargo.toml --offline`, `npm --prefix test run test:e2e:igloo-home`
- `igloo-shared`: `npm run test:typecheck`
- Cross-host E2E: `npm --prefix test run test:e2e:igloo-pwa`, `npm --prefix test run test:e2e:igloo-chrome`, `npm --prefix test run test:e2e:fast`, `npm --prefix test run test:e2e:live`
- Packaging dry run: `igloo-chrome` `npm run package`
