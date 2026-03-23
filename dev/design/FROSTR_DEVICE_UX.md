# FROSTR Device UI / UX Design

## Status

Working design document.

This document defines the intended user experience for FROSTR device management across hosts. It focuses on:

- the logged-out workspace
- the logged-in device workspace
- the major flows that move a user between those two states

It is a product and UX document, not a wire-format or protocol spec. Protocol and package details live in the main `docs/` set.

## Summary

FROSTR has two primary UI states:

- `Logged out`
  - the user has no active device runtime on this host
  - the user is choosing how to create, load, recover, or onboard a device
- `Logged in`
  - the user has an active local device profile selected
  - the user is operating a signer, managing permissions, and maintaining that device

The logged-out workspace always begins with three top-level choices:

- `Create / Rotate Keyset`
- `Load Profile`
- `Onboard Device`

The logged-in workspace always organizes device operations into three major areas:

- `Device Dashboard`
- `Device Permissions`
- `Device Settings`

These six surfaces define the core FROSTR device UX.

## Design Goals

- Keep the top-level choices obvious and separate.
- Make package types visible and explicit:
  - `bfprofile` for full device profile import
  - `bfshare` for recovery and rotation source input
  - `bfonboard` for onboarding a new device
- Allow advanced operator workflows without forcing protocol knowledge on casual users.
- Keep the same flow structure across hosts even if the visual presentation differs.
- Make rotation feel like a first-class workflow, not a hidden operator trick.
- Keep logged-out profile storage privacy-minimal:
  - list only label and short profile id

## UX Principles

### 1. Top-level intent comes before package type

The user should first choose what they are trying to do:

- create or rotate a keyset
- load an existing device
- onboard a new device

Only after that should the UI ask for the relevant package or secret material.

### 2. Connection and save are separate moments

Any flow that first resolves or decrypts remote data should have a distinct review/save step before local persistence.

This applies especially to:

- `bfonboard`
- `bfshare` recovery
- rotation flows that generate replacement onboarding packages

### 3. Logged-out and logged-in workspaces should feel different

The logged-out workspace is about initialization and selection.

The logged-in workspace is about operation and maintenance.

The user should never feel unsure which mode they are in.

### 4. Rotation preserves keyset identity, but changes device identity

The UX must make this distinction understandable:

- the group public key stays the same
- the rotated device share changes
- the rotated device profile id changes

That means rotation is not "editing one field" on a profile. It is a controlled replacement of device share state while preserving the keyset identity.

## Application State Model

```text
+------------------+
| Logged Out       |
|                  |
| Create / Rotate  |
| Load Profile     |
| Onboard Device   |
+--------+---------+
         |
         | save / load / unlock / activate
         v
+------------------+
| Logged In        |
|                  |
| Dashboard        |
| Permissions      |
| Settings         |
+--------+---------+
         |
         | logout / stop / clear active session
         v
+------------------+
| Logged Out       |
+------------------+
```

## Logged-Out Workspace

## Entry Screen

The logged-out landing screen should present three equal-weight choices:

- `Create / Rotate Keyset`
- `Load Profile`
- `Onboard Device`

Short descriptions should make the distinction obvious:

- `Create / Rotate Keyset`
  - create a new keyset or rotate shares for an existing one
- `Load Profile`
  - load an existing device from storage, `bfprofile`, or `bfshare`
- `Onboard Device`
  - connect to an accepted onboarding package and save a new device

If local profiles already exist, the logged-out workspace should also show a profile list above or beside these actions:

- profile label
- short profile id
- action:
  - `Load Profile` if unlocked
  - `Unlock` if locked

No additional stored-profile metadata should be shown in this list.

## Logged-Out Flow Map

```text
Logged Out
|
+-- Create / Rotate Keyset
|   |
|   +-- Create New Keyset
|   \-- Rotate Existing Keyset
|
+-- Load Profile
|   |
|   +-- Select Existing Local Profile
|   +-- Import bfprofile
|   \-- Recover with bfshare
|
\-- Onboard Device
    |
    \-- Connect bfonboard -> Review -> Save Device
```

## 1. Create / Rotate Keyset

This is the "operator setup" flow.

It begins with a branch:

- `Create New Keyset`
- `Rotate Existing Keyset`

Both branches converge into:

- select the local share
- create the local device profile
- distribute the remaining rotated or newly generated shares

### Flow Structure

```text
Create / Rotate Keyset
|
+-- Step 1A: Create New Keyset
|   |
|   \-- generate new secret or provide existing secret
|
\-- Step 1B: Rotate Existing Keyset
    |
    \-- recover from threshold bfshare set

Then:
|
+-- Step 2: Select Share and Create Profile
\-- Step 3: Distribute Shares
```

### Step 1A: Create New Keyset

The user chooses to create a brand-new keyset.

Required inputs:

- `Keyset Name`
- `Share Count`
- `Threshold`

Secret source:

- `Generate New Secret`
- `Use Existing Secret`

Design notes:

- `Generate New Secret` should be the default.
- `Use Existing Secret` is an advanced option and should be visually secondary.
- threshold validation should be immediate and inline.

Outcome:

- a new keyset is generated
- a full set of shares is created
- the user moves to share selection

### Step 1B: Rotate Existing Keyset

The user chooses to rotate an existing keyset without changing the keyset public identity.

Required inputs:

- an existing local profile as the starting point
- enough `bfshare` strings to meet the current threshold
- package password(s) for those `bfshare` strings
- new share count
- new threshold

Design notes:

- the existing local profile gives the user context:
  - which keyset they are rotating
  - which device they are starting from
- the recovery set should behave like a visible checklist:
  - `shares collected`
  - `threshold required`
  - `recovery ready / not ready`
- the UI should clearly say:
  - rotation keeps the same group public key
  - rotation creates new device shares

Suggested layout:

```text
Rotate Existing Keyset
|
+-- Select Source Profile
+-- Add bfshare #1
+-- Add bfshare #2
+-- ...
+-- Recovery Set Status
\-- Configure New Share Count / Threshold
```

Outcome:

- the system reconstructs the current keyset from threshold shares
- the same signing key is split into a fresh share set
- the user moves to share selection

### Step 2: Select Share and Create Profile

This step is shared by both create and rotate.

The user selects which share becomes the local device profile on this host.

Required inputs:

- selected share
- profile label
- local password
- relay configuration

Defaults:

- when rotating, the share with the same member index as the source profile should be selected by default
- when rotating, the profile name should default to the existing local profile name
- relay configuration should default to the current device relays when rotating

Important behavior:

- when rotating, the resulting device profile is a replacement profile
- the group public key remains the same
- the share public key changes
- the canonical profile id changes

The UX should communicate this without overwhelming the user.

Suggested review copy:

- `Same keyset, fresh device share`
- `This rotation keeps the same group public key and replaces this device with a new share`

### Step 3: Distribute Shares

After the local profile is created, the remaining shares must be distributed.

Each target share should be distributed as a `bfonboard` package.

This is true for:

- brand-new keysets
- rotated keysets
- new-device setup
- existing-device in-place rotation

#### Distribution artifact

Use `bfonboard` for every non-local share.

Per-share actions:

- `Copy`
- `Show QR`
- `Save`

Design notes:

- the UI should not offer `bfshare` as a distribution option
- `bfshare` remains for recovery and threshold rotation input only
- during rotation, the operator may still label a target share by intent:
  - `New Device`
  - `Rotate Existing Device`
- but both intents produce the same package type: `bfonboard`

### Completion State

This flow is complete when:

- the local profile has been created and saved
- the local runtime is ready or ready to start
- the distribution artifacts are visible and exportable

## 2. Load Profile

This is the "I already have device material" flow.

The user has three choices:

- select an existing stored profile
- import a `bfprofile`
- recover using `bfshare`

### Flow Structure

```text
Load Profile
|
+-- Existing Stored Profiles
+-- Import bfprofile
\-- Recover with bfshare
```

### Existing Stored Profiles

If profiles are already saved locally, they should appear first.

Each row displays only:

- label
- short profile id
- action

Possible actions:

- `Load Profile`
- `Unlock`
- `Delete`

If a profile is selected and activated successfully, the user transitions directly into the logged-in workspace.

### Import bfprofile

Required inputs:

- `bfprofile` string
- package password

Flow:

1. paste or scan `bfprofile`
2. decrypt and validate
3. show read-only review
4. collect local label/password if needed
5. save locally
6. activate or unlock

The review step should emphasize:

- profile name
- share identity summary
- group identity summary
- relay configuration

### Recover with bfshare

Required inputs:

- `bfshare` string
- package password

Flow:

1. paste or scan `bfshare`
2. decrypt the share credential
3. recover the full profile from relay backup
4. show read-only review
5. save locally
6. activate or unlock

This path is recovery-oriented and should be labeled accordingly.

It should not be used for device-share distribution or in-place rotation replacement.

If the user wants to rotate a device, they should use `bfonboard` instead:

- while logged out through `Onboard Device`
- while logged in through `Device Settings -> Rotate Key`

## 3. Onboard Device

This is the "I received a live onboarding package" flow.

The onboarding experience should always be a two-step flow:

- `Connect`
- `Save Device`

### Step 1: Input bfonboard Package and Secret

Required inputs:

- `bfonboard` string
- package secret

The UI should present this as a live connection step, not as a file import step.

Expected actions:

- paste package
- scan QR
- enter secret
- connect

Result:

- the onboarding handshake resolves a concrete device profile candidate

### Step 2: Input Name and Password to Create Profile

After the handshake succeeds, the UI moves to a review/save screen.

Required inputs:

- device name
- local password

Read-only information should also be shown:

- keyset / group summary
- share summary
- relay summary

Result:

- the local profile is saved
- the device becomes active
- the user enters the logged-in workspace

### Onboarding Completion Rule

The dashboard should never appear before:

- onboarding handshake success
- local profile save success
- runtime activation success or explicit ready-to-start state

## Logged-In Workspace

Once a local device is active, the application moves into the logged-in device workspace.

This workspace has three tabs or sections:

- `Device Dashboard`
- `Device Permissions`
- `Device Settings`

## Logged-In Flow Map

```text
Logged In
|
+-- Device Dashboard
+-- Device Permissions
\-- Device Settings
```

## 1. Device Dashboard

This is the primary operator console for the active device.

It should answer four questions immediately:

- is the device configured?
- is the signer runtime running?
- are peers reachable?
- are there actions waiting for attention?

### Main sections

- `Device Status and Controls`
  - runtime state
  - start / stop
  - refresh status
- `Peer Status and Controls`
  - connected peers
  - ping peers
  - peer activity summary
- `Pending Actions`
  - signing requests
  - ECDH requests
  - pending approvals
- `Device Event Log`
  - recent runtime events
  - warnings
  - failures

### Dashboard priorities

The top of the dashboard should prioritize:

1. signer runtime state
2. any blocking or degraded condition
3. pending work
4. peer status

The event log belongs lower in the page.

## 2. Device Permissions

This is the control surface for policy.

It should be separate from the dashboard because it is administrative, not operational.

### Main sections

- `Peer Permissions`
  - which peers may request operations
  - request/response behavior
- `Signing Permissions`
  - allowed signing behavior
  - prompts, approvals, and overrides

### UX rules

- permission changes should be explicit and reviewable
- destructive or broad permissions should use warning copy
- permission state should never be hidden inside general settings

## 3. Device Settings

This is the maintenance surface for the active device profile.

### Main sections

- `Profile`
  - change name
  - change local password
- `Relays`
  - add / remove relays
  - update relay policy
- `Backup`
  - view backup status
  - publish or refresh backup
- `Device Operations`
  - export `bfshare`
  - export `bfprofile`
  - rotate key
  - logout
  - delete local profile

### Rotation-related settings actions

The active device settings should expose two different rotation-related actions:

- `Export bfshare`
  - export this device's recovery credential for threshold recovery / future rotation input
- `Rotate Key`
  - paste or scan a `bfonboard` package and replace this device with a rotated share while preserving local context where possible

Important distinction:

- `bfonboard` is used to set up a new device
- `bfonboard` is also used to rotate an existing device in place
- `bfshare` is used only for:
  - recovery
  - threshold share collection during operator-led rotation

There are only two supported ways to adopt a rotated share on a device:

- log out and use `Onboard Device` with `bfonboard`
- stay logged in and use `Device Settings -> Rotate Key` with `bfonboard`

### Rotate Key flow

`Rotate Key` is the logged-in path for replacing the active device share without making the user leave the device workspace first.

Required inputs:

- `bfonboard` package
- package secret

Flow:

1. open `Device Settings`
2. choose `Rotate Key`
3. paste or scan `bfonboard`
4. enter the package secret
5. connect and resolve the rotated profile
6. review the replacement:
   - same keyset
   - new device share
   - new profile id
7. confirm replacement
8. save and reactivate the device

Result:

- the current device profile is replaced by the rotated profile
- local operator context is preserved where possible
- the user remains in the logged-in workspace

### Logout behavior

Logout should:

- stop the active runtime
- clear active unlocked state for this session
- return the user to the logged-out workspace

Stored profiles should remain visible after logout.

## Cross-Flow UX Rules

### Review before persistence

Before saving a profile locally, the user should see a review screen whenever the source material was:

- decrypted from an imported package
- recovered from relay
- obtained through onboarding
- generated during keyset creation or rotation
- used to rotate an existing logged-in device with `bfonboard`

### Package terminology must remain visible

The UI should not hide package type names.

Users should see:

- `bfprofile`
- `bfshare`
- `bfonboard`

### Rotation terminology must remain precise

The UI should distinguish:

- `Create New Keyset`
  - new group public key
- `Rotate Existing Keyset`
  - same group public key, new shares

### Existing profile replacement must be explicit

Any flow that replaces an existing local profile should require:

- explicit confirmation
- clear messaging that the device share is being replaced
- a review step that shows:
  - same keyset identity
  - new device share identity
  - new profile identity

### Privacy-minimal logged-out lists

In the logged-out workspace, saved profile rows should show only:

- label
- short profile id

They should not show:

- share public key
- group public key
- relay list
- peer metadata

## Recommended Screen Inventory

## Logged Out

- `Landing`
- `Create / Rotate Keyset`
- `Create New Keyset`
- `Rotate Existing Keyset`
- `Select Share and Create Profile`
- `Distribute Shares`
- `Load Profile`
- `Import bfprofile`
- `Recover with bfshare`
- `Onboard Device: Connect`
- `Onboard Device: Save`

## Logged In

- `Device Dashboard`
- `Device Permissions`
- `Device Settings`
- `Export bfshare`
- `Rotate Key`

## End-to-End UX Diagram

```text
                           +----------------------+
                           | Logged Out           |
                           |                      |
                           | Create / Rotate      |
                           | Load Profile         |
                           | Onboard Device       |
                           +----------+-----------+
                                      |
                 +--------------------+--------------------+
                 |                    |                    |
                 v                    v                    v
        +----------------+   +----------------+   +----------------+
        | Create /       |   | Load Profile   |   | Onboard Device |
        | Rotate Keyset  |   |                |   |                |
        +--------+-------+   +--------+-------+   +--------+-------+
                 |                    |                    |
                 v                    v                    v
        +----------------+   +----------------+   +----------------+
        | Save / Load /  |   | Save / Load /  |   | Save / Load /  |
        | Activate       |   | Activate       |   | Activate       |
        +--------+-------+   +--------+-------+   +--------+-------+
                 \                    |                    /
                  \                   |                   /
                   \                  |                  /
                    v                 v                 v
                      +-------------------------------+
                      | Logged In                     |
                      |                               |
                      | Dashboard                     |
                      | Permissions                   |
                      | Settings                      |
                      +-------------------------------+
```

## Recommended Next Steps

- align `dev/UI_FLOWS.md` to this document or fold it into this one
- use this document as the source for host-specific UI plans
- derive dedicated UI specs for:
  - rotation wizard
  - logged-out profile inventory
  - device settings and rotate-key flow
