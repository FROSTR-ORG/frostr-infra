# Igloo PWA UI Design

# Landing

The user should land on a page with three options:

* Create Keyset
* Load Profile
* Onboard Device

Each option represents a UI flow.

## Create Keyset

Keyset generation and distribution is a multi-step process:

Step 1: Generate the keyset.

Step 2: Create a device Profile.

Step 3: Distribute the keyset.

### Generate the Keyset

This section must ask the user for the following information:

Keyset Name: The name to give to the keyset. This name is stored in the "group data" for the keyset.

Secret Key: a 32-byte hexadecimal string, or an encoded `nsec` string. There should be an button to "generate" a key as well.

Threshold: The number of keys required to produce a signing operation. Default is 2.

Total Keys: The total number of keys to produce. Default is 3.

Once this information is provided, they keyset can be generated, and the user can move to step 2.

### Generate a Device Profile

Next, the user is shown a preview of the group profile data, plus a list of the shares that have been created. The user must select a share, then give it a name and password. The user must also input the relays to be used. Once this is complete, the user is asked to review the full profile information, then click "accept" to move onto the next step.

### Distribute the Keyset.

On this page, the user's signing device is loaded, initialized and connected, and the remaining shares are listed below.

Each share has a number of options attached to them: Copy (to clipboard), QR (display as a QR code), and Save (saves encrypted to disk).

When a share is copied or displayed as a QR code, the user is asked to give the share a name and password. A `bfonboard` package is created using the share, the pubkey of the running signer, and the relays.

Whe a share is saved, the user is asked to provide a name and password for the share. The device profile is created, and saved locally to the device.

Once the user is finished, they can click "finish". This will bring them to the device dashboard.

### Load a keyset. 

## Load Profile

The user should land on a page with two options:

**Import**: Imports an existing device profile using a bech32 encoded `bfprofile` string.

**Login**: Uses your `bfshare` to login to the device. This string includes your share secret, and suggested relays Your profile data will be downloaded and decrypted from the nostr relays.

### Import

If the user chooses **import**, they are prompted to enter the `bfprofile` string, and a decryption password. Upon successful decryption, the user is shown their profile data for inspection. If the information is confirmed by the user, then the device is loaded, and the user is moved to the device dashboard screen.

### Login

If the user chooses **login**, they are prompted to enter their `bfshare` string, and a decryption password. Upon successful decryption, the share is used to fetch an encrypted kind 0 "profile" from the relays (provided with `bfshare`). If that profile is fetched and decrypted successfully, the user is shown their profile data for inspection. If the information is confirmed by the user, then the device is loaded, and the user is moved to the device dashboard screen.

## Onboard Device

Use a password-protected `bfonboard` string to add your device to the FROSTR network. Requires an existing online device to create the `bfonboard` package, and to complete the process once your device connects to the peer.

Onboarding is a two-step process:

Step 1: Input the onboarding package, and the decryption password. Hit the "connect" button. The onboarding device will dial-out to the peer, and negotiate the handshake. Once the process is complete, the user is shown the profile information to confirm that it looks correct, then moves to the next step.

Step 2: Input a name for your device, and a password (with confirmation). The password is used to encrypt the device data when stored on disk. Once the user completes this process, the device is initialized, and the user is forwarded to the device dashboard.