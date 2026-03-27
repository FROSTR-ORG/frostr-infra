# ADR-009: Split Manual and Remote Peer Permissions

## Status

Accepted

## Current Source of Truth

Current peer-permission runtime and serialization details live in `docs/PROTOCOL.md` and `docs/BACKUP.md`.

## Context

Peer permissions were previously modeled as a single local `send` / `receive` policy per peer.

That collapsed two different concerns into one value:
- local operator intent
- remote peer willingness reported through `ping`

This caused two problems:
- the runtime could not distinguish a local manual deny from a remote reported deny
- hosts could store or display peer permissions without showing whether they were local policy, remote observation, or effective runtime gating

Browser and mobile runtimes are also frequently torn down, so remote peer policy observations must survive restarts.

## Decision

The canonical peer permission model is split into two persisted layers:

- `manual_peer_policy_overrides`
  - local operator policy
  - per peer
  - per direction (`request`, `respond`)
  - per method (`ping`, `onboard`, `sign`, `ecdh`)
  - tri-state values: `unset | allow | deny`

- `remote_peer_policy_observations`
  - last peer-reported policy learned through `ping`
  - persisted with revision and update timestamp

Effective policy is derived, not stored as operator input:

- inbound effective policy depends only on local manual policy
- outbound effective policy depends on local manual policy plus remote observed policy
- remote observed policy only gates outbound `sign` and `ecdh`
- remote observed policy does not gate `ping`
- remote observed policy does not gate `onboard`
- deny wins over allow

Remote observations remain advisory until refreshed:
- they are persisted across restarts
- they continue to apply until replaced by a newer ping result
- hosts should surface observation age, but the runtime does not auto-expire them to allow or deny

The serialization and runtime-status boundary follows the same split:

- `bfprofile` packages and encrypted profile backups persist:
  - `manual_peer_policy_overrides`
  - `remote_peer_policy_observations`
- effective peer policy is runtime-derived only and is never serialized
- peer permission is part of canonical runtime status
- separate `Policies` control/status commands are removed
- operator hosts read permission state from runtime status, not from a parallel policy RPC or coarse manifest view

This is a hard cut for the beta stack:

- legacy coarse `send` / `receive` policy is removed
- compatibility readers and dual-shape loaders are removed
- raw manifest/config inspection may remain for admin/debug, but it is not an operator-facing policy contract

The host rollout is repo-wide:

- runtime and native control planes expose detailed local, remote, and effective policy state
- browser hosts render and edit the detailed model
- shell/native/browser status surfaces stop treating peer permission as one boolean per direction

## Consequences

- Hosts must stop treating peer permission as one boolean per direction.
- Package, backup, and manifest serializers must stop treating peer permission as one boolean per direction.
- Runtime APIs and UI must distinguish:
  - local manual override
  - remote observed policy
  - effective policy
- Outbound `sign` and `ecdh` peer selection must exclude peers that are effectively denied.
- Inbound request handling must enforce local inbound policy.
- Legacy coarse `send` / `receive` policy, separate policy RPCs, and compatibility readers are removed.
