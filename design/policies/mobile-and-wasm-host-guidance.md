# Mobile and WASM Host Guidance

Use this document to evaluate whether native-mobile and browser hosts remain healthy while the shell daemon architecture evolves.

## Required Defaults

- `bifrost-bridge-wasm` stays browser-native and in-process
- native mobile hosts may embed `bifrost-bridge-tokio` directly
- daemon transport introduced for `igloo-shell` must remain optional for non-shell hosts

## Expected Alignment

- shared runtime concepts such as readiness, runtime status, runtime metadata, and config patching should stay semantically aligned across Tokio and WASM
- type and payload normalization is preferred over transport unification
- platform-specific storage, lifecycle, and FFI concerns should live above the bridge layer

## Healthy Changes

- widening shared runtime status types used by both Tokio and WASM
- adding mobile host wrappers above the Tokio bridge for Swift/Kotlin integration
- keeping browser runtime orchestration inside browser-appropriate host boundaries

## Drift Signals

- browser hosts depending on shell daemon protocols
- mobile hosts requiring a background daemon only because the shell does
- host lifecycle behavior being encoded into signer or router logic when it belongs in platform-specific host layers

## Review Prompts

- does this change preserve direct in-process use of the Tokio bridge?
- does this change keep WASM free of Unix-socket and daemon-process assumptions?
- is the proposal solving a real mobile/browser host problem, or importing shell constraints into the wrong layer?
