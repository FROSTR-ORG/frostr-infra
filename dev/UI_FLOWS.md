# FROSTR UI Flows

## Summary

This document describes the current user-facing onboarding flows for FROSTR hosts.

The top-level entry points are:

- `Create / Rotate Keyset`
- `Load Profile`
- `Onboard Device`

These are the three ways a user goes from no local device state to a configured signer.

This is a product-flow document, not a wire-format spec. Package and backup details live in:

- [`docs/BROWSER-PACKAGES-AND-BACKUPS.md`](../docs/BROWSER-PACKAGES-AND-BACKUPS.md)
- [`docs/PROTOCOL.md`](../docs/PROTOCOL.md)

## Shared UX Rules

- The UI should present the three top-level flows clearly and separately.
- Package types must remain type-visible:
  - `bfprofile` for full profile import
  - `bfshare` for relay recovery
  - `bfonboard` for device onboarding
- The user should not need to understand protocol internals to choose the correct flow.
- Hosts may differ in visual design, but the flow structure and terminology should remain aligned.
- Review and save should be separate from the initial package connection step whenever a live handshake or decrypt step happens first.

## Flow Map

```text
No Local Device
|
+-- Create / Rotate Keyset
|   |
|   +-- Generate New Keyset
|   \-- Rotate Existing Keyset
|
+-- Load Profile
|   |
|   +-- Load From File (`bfprofile`)
|   \-- Recover From Relay (`bfshare` + optional relay input)
|
\-- Onboard Device
    |
    \-- Connect with `bfonboard`, then save local device
```

## 1. Create / Rotate Keyset

`Create / Rotate Keyset` is used when the user is establishing or rotating a keyset and creating the first local device profile from that keyset.

This flow has two starting modes:

- `Generate New Keyset`
- `Rotate Existing Keyset`

### Entry Criteria

The user starts without a usable local signer profile for the desired keyset.

Expected starting conditions:

- no existing local profile for the target share on this host
- the user intends to create or rotate key material, not import an existing device profile

### Exit Criteria

This flow is complete only when:

- a local profile has been saved successfully
- the local runtime has initialized successfully
- the user has landed on the signer dashboard
- any remaining shares are available for onward distribution

### 1.1 Generate New Keyset

This path creates a brand new group secret and splits it into shares.

#### Step 1: Keyset Generation

The user provides:

- `Keyset Name`
- `Threshold`
- `Total Shares`

Optional:

- existing secret key material
- or a generated secret key

Outcome:

- a new group is generated
- the full set of shares is created

#### Step 2: Create Local Device Profile

The user selects the share that will belong to the current device and provides:

- local device name
- local storage password or secret, where applicable
- relay list

Outcome:

- a local device profile is created
- the local signer can be initialized

#### Step 3: Distribute Remaining Shares

The remaining shares are prepared for other devices or operators.

Expected actions per remaining share:

- copy onboarding package
- show QR code
- save to disk

Expected artifact:

- `bfonboard` for onboarding another device

The flow ends on the signer dashboard once the local device is live and the remaining shares are available for distribution.

#### Failure Cases

Expected failures include:

- invalid threshold or total-share configuration
- malformed provided secret key
- failure to generate or split shares
- failure to save the local profile
- failure to initialize the local signer after save

Required behavior:

- the dashboard must not appear before local profile save and runtime startup both succeed
- if local save fails, generated shares may remain in transient UI state but must not be presented as a completed device setup
- if runtime startup fails after save, the UI should remain in a recoverable post-save state and show a clear activation failure

### 1.2 Rotate Existing Keyset

This path re-issues shares for an existing group secret instead of creating a brand new secret.

Required inputs:

- enough existing share material to reconstruct the secret
- target threshold and total share count for the new distribution
- keyset metadata to preserve or update, depending on product policy

High-level steps:

1. recover the existing secret from sufficient shares
2. generate a new share set for the same underlying group secret
3. create the local replacement device profile
4. distribute the newly rotated shares as onboarding artifacts

Outcome:

- a new share set exists for the same underlying keyset
- the current device has a fresh local profile
- remaining devices can be onboarded from the rotated shares

#### Failure Cases

Expected failures include:

- insufficient valid existing shares to recover the secret
- inconsistent or mismatched recovery material
- failure to create replacement share material
- failure to save or activate the replacement local device profile

Required behavior:

- rotation must fail closed if the secret cannot be reconstructed unambiguously
- replacement shares must not be presented as valid outputs unless the rotation process completes successfully

## 2. Load Profile

`Load Profile` is used when the user already has device or share material and wants to restore a local signer without creating a new keyset.

This flow has two starting modes:

- `Load From File`
- `Recover From Relay`

### Entry Criteria

The user already possesses an importable package or enough recovery material to reconstruct a full local device profile.

Expected starting conditions:

- the user has either:
  - a `bfprofile`
  - or a `bfshare` and access to the needed relay backup data
- the target profile id does not already exist locally

### Exit Criteria

This flow is complete only when:

- the recovered or imported profile has been validated
- the local profile has been saved successfully
- the local runtime has initialized successfully
- the user has landed on the signer dashboard

### 2.1 Load From File (`bfprofile`)

This path imports a full encrypted local device profile package.

Required inputs:

- `bfprofile` package
- package password

High-level steps:

1. paste or select the `bfprofile`
2. enter the package password
3. decrypt and validate the profile package
4. show the resolved profile summary
5. save the device locally
6. initialize the signer

Expected review data:

- device name
- profile id
- keyset name
- group public key
- share public key
- relay list

Outcome:

- the device profile is stored locally
- the signer is started from the imported profile

#### Failure Cases

Expected failures include:

- malformed `bfprofile`
- wrong package password
- invalid outer or inner `profile_id`
- profile payload that fails cryptographic validation
- duplicate local profile id
- runtime initialization failure after save

Required behavior:

- duplicate profile import is a hard fail
- the imported package must not overwrite an existing profile
- the dashboard must not appear before save and runtime activation succeed

### 2.2 Recover From Relay (`bfshare` and Optional Relay)

This path starts from compact recovery credentials and rebuilds a full local profile from relay-backed encrypted backup data.

Required inputs:

- `bfshare` package
- package password

Optional:

- relay override or additional relay input, if the host allows supplementing the relays embedded in `bfshare`

High-level steps:

1. paste or select the `bfshare`
2. enter the package password
3. decrypt the share secret and relay hints
4. fetch the latest encrypted profile backup from relays
5. decrypt and validate the backup
6. reconstruct the full local profile
7. show the resolved profile summary
8. save the device locally
9. initialize the signer

Outcome:

- a full local profile is reconstructed from relay data
- the device is stored locally
- the signer is started

#### Failure Cases

Expected failures include:

- malformed `bfshare`
- wrong package password
- missing or unreachable relays
- missing encrypted profile backup on relays
- backup decrypt or validation failure
- duplicate local profile id
- runtime initialization failure after save

Required behavior:

- if relay recovery fails, no partial local profile should be committed as a completed result
- duplicate profile recovery is a hard fail
- any host-provided relay override must remain explicit and visible to the user

## 3. Onboard Device

`Onboard Device` is used when an existing running signer provisions another device using a compact onboarding package.

This flow starts from:

- `bfonboard`

Required inputs:

- `bfonboard` package
- package password

### Entry Criteria

The user has an onboarding package created by an already running signer and intends to create a new local device from that package.

Expected starting conditions:

- `bfonboard` is available
- the onboarding peer identified by `peer_pk` is expected to be reachable
- the target profile id does not already exist locally

### Exit Criteria

This flow is complete only when:

- the onboarding handshake has succeeded
- the resolved profile has been reviewed
- the local profile has been saved successfully
- the local runtime has initialized successfully
- the user has landed on the signer dashboard

### Step 1: Connect

The host:

1. decrypts the `bfonboard` payload
2. derives the local share identity from the share secret
3. connects to the callback peer identified by `peer_pk`
4. completes the onboarding handshake
5. receives the group package and peer bootstrap nonce package
6. constructs the local runtime snapshot and profile preview

User-facing result:

- the package is validated
- the live onboarding handshake succeeds
- the UI advances to a save/review screen

### Step 2: Review and Save Device

The user reviews the resolved device information and provides local save settings.

Expected editable inputs:

- local device name
- local storage password or secret, where applicable

Expected read-only review data:

- profile id
- keyset name
- group public key
- share public key
- relay list

Final actions:

1. store the local device profile
2. construct local `bfshare`
3. publish encrypted backup where applicable
4. initialize the signer

Outcome:

- the onboarded device becomes a full local signer
- the user lands on the signer dashboard

### Failure Cases

Expected failures include:

- malformed `bfonboard`
- wrong package password
- callback peer unreachable
- onboarding handshake rejection or timeout
- duplicate local profile id
- local save failure
- runtime initialization failure after save

Required behavior:

- the connect step and the save step must remain distinct
- the signer dashboard must not appear immediately after handshake success
- the dashboard must appear only after save and runtime initialization both succeed
- if runtime initialization fails after save, the host should surface the failure explicitly and leave the saved profile recoverable

## 4. Resulting Artifacts by Flow

### Create Keyset

Creates:

- local device profile
- additional shares for distribution
- `bfonboard` packages for other devices
- relay backup material after profile creation, where supported

### Load From File

Consumes:

- `bfprofile`

Creates:

- local device profile
- local runtime state

### Recover From Relay

Consumes:

- `bfshare`
- encrypted relay backup

Creates:

- reconstructed local device profile
- local runtime state

### Onboard Device

Consumes:

- `bfonboard`

Creates:

- local device profile
- local `bfshare`
- local runtime state
- encrypted relay backup publish, where supported

## 5. UX Consistency Requirements

- `Create Keyset`, `Load Profile`, and `Onboard Device` should always be the first visible choices on a fresh host.
- `Create / Rotate Keyset`, `Load Profile`, and `Onboard Device` should always be the first visible choices on a fresh host.
- `Load Profile` must clearly distinguish `Load From File` from `Recover From Relay`.
- `Onboard Device` must use a two-phase UX:
  - connect
  - review and save
- The signer dashboard should only appear after the local device has actually been saved and runtime initialization has succeeded.
- Hosts should avoid collapsing package types into a generic "import" concept where that would hide user intent.
- Profile identity should be displayed as:
  - full `profile_id` in detail views
  - first 8 hex chars in compact views

## 6. Cross-Flow Invariants

These rules apply across all onboarding-style flows:

- package type must always be visible to the user
- duplicate profile creation by canonical `profile_id` is a hard fail
- `profile_id` is not the same as the share public key
- the share public key is not the same as the group public key
- the signer dashboard is never the success state for a merely decrypted or connected package
- success means:
  - profile saved
  - runtime initialized
  - dashboard shown
- short profile ids are display-only and must never be used as lookup keys
- effective peer policy is runtime-derived and not part of onboarding review as an editable field

## 7. Terminology

### Profile Id

`profile_id` is the canonical host-level identifier for a device profile.

- it is derived from the share public key
- it is not the share public key itself
- full form is used for storage and lookup
- first 8 hex characters are used for compact display only

### Share Public Key

The share public key identifies the device's signer share within the group.

- it is the signer/member identity
- it is distinct from `profile_id`
- it is distinct from the group public key

### Group Public Key

The group public key identifies the keyset as a whole.

- multiple devices or shares belong to the same group public key
- one local profile corresponds to one share, not to the entire group

### `bfprofile`

Full encrypted local device profile package.

Used for:

- direct device-profile import

### `bfshare`

Compact encrypted recovery package.

Used for:

- relay-backed profile recovery

### `bfonboard`

Compact encrypted onboarding package.

Used for:

- onboarding a new device through a live peer handshake

## 8. Host Notes

All hosts should implement the same top-level flow model, but may differ in local constraints.

Examples:

- browser hosts may need explicit local save confirmation before runtime activation
- extension hosts may need offscreen/runtime activation steps that are invisible in other hosts
- shell/native flows may expose more operator detail during key rotation or export

These differences should not change:

- top-level entrypoint names
- package-type meaning
- completion criteria
- the rule that the dashboard is shown only after local save and runtime success

## 9. State Machines

This section defines the expected UI state progression for each top-level flow.

Hosts may implement these as explicit route states, modal states, or local component states, but the behavioral sequence should remain aligned.

### 9.1 Create / Rotate Keyset

```text
idle
-> editing_generation_inputs
-> generating_keyset
-> selecting_local_share
-> saving_local_profile
-> starting_runtime
-> ready
```

Optional rotation path:

```text
idle
-> editing_rotation_inputs
-> recovering_existing_secret
-> generating_rotated_shares
-> selecting_local_share
-> saving_local_profile
-> starting_runtime
-> ready
```

Failure exits:

- `generation_failed`
- `rotation_recovery_failed`
- `save_failed`
- `runtime_start_failed`

Behavioral rules:

- `ready` means the dashboard is active and the device is usable
- share-distribution UI belongs after local profile save has succeeded
- runtime activation is a separate step from profile save

### 9.2 Load From File (`bfprofile`)

```text
idle
-> entering_package
-> decrypting_package
-> validating_profile
-> review_profile
-> saving_local_profile
-> starting_runtime
-> ready
```

Failure exits:

- `decrypt_failed`
- `validation_failed`
- `duplicate_profile`
- `save_failed`
- `runtime_start_failed`

Behavioral rules:

- review happens only after decrypt and validation succeed
- `ready` is not reached directly from `review_profile`; save and runtime start must both complete

### 9.3 Recover From Relay (`bfshare`)

```text
idle
-> entering_package
-> decrypting_share
-> resolving_relays
-> fetching_backup
-> decrypting_backup
-> validating_profile
-> review_profile
-> saving_local_profile
-> starting_runtime
-> ready
```

Failure exits:

- `decrypt_failed`
- `relay_resolution_failed`
- `backup_fetch_failed`
- `backup_decrypt_failed`
- `validation_failed`
- `duplicate_profile`
- `save_failed`
- `runtime_start_failed`

Behavioral rules:

- relay recovery is not complete when backup fetch succeeds
- the reconstructed profile must still pass validation and local save before activation

### 9.4 Onboard Device (`bfonboard`)

```text
idle
-> entering_package
-> decrypting_package
-> connecting_to_peer
-> completing_onboarding_handshake
-> review_and_save
-> saving_local_profile
-> publishing_backup
-> starting_runtime
-> ready
```

Failure exits:

- `decrypt_failed`
- `peer_connect_failed`
- `handshake_failed`
- `duplicate_profile`
- `save_failed`
- `backup_publish_failed`
- `runtime_start_failed`

Behavioral rules:

- `review_and_save` is a required state after handshake success
- the host must not skip from handshake success directly to dashboard
- backup publish may happen before or after runtime start depending on host implementation, but must not be confused with local save success
- if backup publish fails but local save succeeds, the host must show the real degraded state rather than pretending onboarding fully succeeded

### 9.5 Common State Vocabulary

To keep host behavior aligned, these state names should remain conceptually stable:

- `idle`: no user input committed yet
- `entering_package`: user is entering or selecting package material
- `decrypting_*`: package password has been submitted and secret material is being resolved
- `validating_profile`: decrypted or recovered profile data is being checked
- `review_*`: user is confirming resolved identity and device information
- `saving_local_profile`: host is committing the profile to local persistence
- `publishing_backup`: host is publishing encrypted backup material where applicable
- `starting_runtime`: host is bringing the signer runtime online
- `ready`: dashboard-success state
- `*_failed`: recoverable error state with explicit retry or back action

## 10. Open Design Boundaries

This document intentionally does not define:

- detailed per-host page layouts
- copywriting for every form and error message
- QR presentation rules
- advanced rotation UX details beyond the top-level flow
- low-level protocol validation or package codecs

Those belong in host-specific UI docs or living protocol/package specs.
