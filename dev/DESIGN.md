# FROSTR Design Guide

## User Flows

The UX can be split into three categories:

* Onboard Operations (going from no device to a configured device)
* Device Operations (once a device is fully configured)
* Utility Operations (ops unrelated to a device, such as "key recovery")

## Onboard Operations

### Setting up a new Device

When setting up a new device, a user has three paths:

* Create Keyset
* Load Profile
* Onboard Device

Each of these options has their own guided UI flow.

### Create Keyset

There are two options for creating a keyset:

**Create New Keyset**

Creates a brand new keyset. User can provide an existing secret key, or generate a new one.

**Rotate Existing Keyset**

Rotate an existing keyset. User must provide enough existing `bfshare` payloads to recover the secret, and rotate the shares.

### Create New Keyset

**Step 1: Generate Shares**

The user generates a new keyset. Required fields:

`Keyset Name`: The name of the keyset. This information is part of the "group" profile.
`Threshold`: The number of shares required to produce the group secret key. Must be les or equal to the total number of shares.
`Total Shares`: The total number of key shares to create.

Optional Fields:

`secret key`: The secret key to use for the keyset generation. This field should include a `generate` button that generates a secure, random 32-byte secret key.

Once this information is provided, we can generate a new keyset, and proceed to the next step.

**Step 2: Create Profile**

Once the keyset has been created, the user must finish creating a device profile for their local device.

**Step 3: Onboard Devices**

Once a local device is setup and running, we can continue with onboarding other devices. The remaining shares are presented in a list, and each share has the following options:

**Copy**: Copies the share data to clipboard.

**Code**: Copies the share data and displays it as a QR code.

**Save**: Copies the share data to disk.

### Load Profile

Loading a user's profile has two options:

**Import**: Import an existing device profile using a bech32 encoded `bfprofile` string. This string is password-protected, and contains all the data required to bootstrap a FROSTR device.

**Login**: Use your `bfshare` to login to the device. Your share will be used to download and decrypt the device's profile data from the nostr relays.

> Note: Login requires that `bfshare` also includes a nostr relay in the encoded string.

### Onboard Device

Use a password-protected `bfonboard` string to "onboard" your device onto the network. Requires an existing online device to create the `bfonboard` package, and to complete the process once your device connects to the peer.

## Device Operations

This is the main page for observing your signing device.

### Node Information

Information about your signer.

`Group Pubkey`

`Share Pubkey`

### Peer Information

### Pending Approvals

### Pending Operations

### Device Logs

## Permissions Page

### Signer Permissions

### Peer Permissions

## Device Options

