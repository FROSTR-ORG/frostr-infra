# Changelog

All notable changes to the FROSTR workspace are documented in this file.

The format is based on Keep a Changelog and uses dated workspace checkpoints instead of a single parent-repo version number.

## [2026-03-28]

### Added
- Root-level shared manuals for interfaces, glossary, and cryptography to support the beta release checkpoint.
- Root-level `CHANGELOG.md` to track coordinated workspace release checkpoints.
- Standalone root project docs for `igloo-home`, `igloo-pwa`, `igloo-shared`, and `igloo-ui`.
- Root changelog and release-prep notes for the coordinated beta checkpoint.

### Changed
- Prepared the following repo releases for the beta checkpoint:
  - `bifrost-rs` `v0.5.0`
  - `igloo-shared` `v0.1.0`
  - `igloo-pwa` `v0.2.0`
  - `igloo-chrome` `v0.3.0`
  - `igloo-shell` `v0.2.0`
  - `igloo-home` `v0.2.0`
- Shared profile and backup payloads now preserve structured `group_package` data end to end.
- `group_name` replaces the old top-level keyset metadata and is carried inside `group_package`.
- Remote peer policy observations are runtime-only state and no longer part of durable profile or backup state.
- `igloo-shell` is now a CLI-only operator host with `rotate-key` and `rotate-keyset` workflows and expanded command coverage.
- Browser and desktop hosts now align on the current onboarding, recovery, rotation, and embedded group-metadata model.
- Shared docs were tightened into a release-ready beta manual for protocol, interfaces, cryptography, profiles, backups, onboarding, rotation, and wire behavior.

### Fixed
- `igloo-home` create flows now require a group name and pass it through the full UI, API, and Tauri path.
- Release validation now runs cleanly across the final beta candidate matrix, including shell smoke, shell node E2E, desktop E2E, browser E2E, and Chrome packaging.
