// Canonical test passwords — one definition each, imported everywhere instead of
// re-typing the literal. ADR-013 §(c) flagged the test password as triplicated
// ('playwright-passphrase' / 'playwright-password' / 'playwright-live-passphrase'
// scattered across specs + fixtures); these are the single source.
//
//  - PROFILE_BLOB_PASSWORD — seals/opens profile blobs and browser seed artifacts
//    (the browser keygen + PWA/Chrome stored-profile unlock password).
//  - RPC_PROFILE_PASSWORD — igloo-home + cross-client RPC profile imports
//    (`import_profile_from_raw`, `start_profile_session`, …).
//  - LIVE_SIGNER_PASSWORD — the headless igloo-shell co-signer passphrase.
export const PROFILE_BLOB_PASSWORD = 'playwright-passphrase';
export const RPC_PROFILE_PASSWORD = 'playwright-password';
export const LIVE_SIGNER_PASSWORD = 'playwright-live-passphrase';
