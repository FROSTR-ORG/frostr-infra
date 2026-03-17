# Host Transport Guidance

Use this document when deciding where host/runtime transport logic should live.

## Required Layering

- keep signer and protocol logic in `bifrost-rs`
- keep `bifrost-bridge-tokio` and `bifrost-bridge-wasm` embeddable and in-process
- put daemon RPC, event streaming, and process-oriented host transport in `bifrost-app`
- keep `igloo-shell` focused on profile storage, vault handling, and operator UX

## Healthy Changes

- adding typed daemon request/response/event types to `bifrost-app`
- reusing `bifrost-bridge-tokio` under a native daemon host
- aligning Tokio and WASM host APIs around shared runtime concepts
- keeping shell-specific persistence and profile logic out of the bridge crates

## Drift Signals

- a bridge crate becoming daemon-required
- shell code calling `bifrost-signer` directly for live operations
- host transport logic being duplicated separately in `igloo-shell` and `bifrost-app`
- browser or mobile hosts being forced to adopt Unix-socket daemon assumptions

## Review Prompts

- is this change transport-layer or runtime-layer?
- would this make the Tokio bridge less embeddable for native apps?
- is a daemon concern being pushed down into a bridge crate?
- does the shell depend on signer internals instead of the host/bridge boundary?
