# Profile and Secret Material Guidance

Use this document to review changes that touch shell-managed profiles, secret artifacts, or runtime persistence.

## Standing Rules

- do not store managed share material plaintext under shell-controlled paths
- do not make `bifrost-rs` crates depend on shell vault layout, shell keyring behavior, or shell profile manifests
- do not treat runtime state files as a substitute for imported share or onboarding artifacts
- do not write plaintext secret artifacts except through an explicit export flow

## Expected Ownership

`igloo-shell` owns:

- profile manifests
- relay profiles
- shell-managed secret storage
- unlock policy and keyring/passphrase behavior
- import/export UX

`bifrost-rs` owns:

- runtime hosting from resolved material
- runtime state persistence
- signer, router, bridge, and host behavior

## Secret Classification

- group package: managed, non-secret
- share package: secret
- imported `bfonboard` package: secret until imported
- runtime state: operational persistence, not import source material
- relay profile and shell config: non-secret

## Review Prompts

- is new secret material being written plaintext into shell-managed storage?
- is a `bifrost-rs` crate learning about shell-specific storage or unlock behavior?
- is a runtime persistence file being used as if it were an import/export artifact?
- does a new host surface clearly document whether it handles profile storage, secret storage, or runtime persistence?
