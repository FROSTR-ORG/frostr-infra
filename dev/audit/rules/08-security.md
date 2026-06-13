# Security

Judges the handling of secrets and the discipline at trust boundaries. FROSTR is
a threshold signer: the crypto primitives are strong, but the 2026-04-22 pass
found the failures live at the *seams* — secrets escaping their envelopes,
defences absent or unenforced, trust boundaries under-validated. This domain
keeps those seams under audit.

## What good looks like

- Secret material is zeroized on drop and never logged, persisted in clear, or
  passed through inheritable channels.
- Crypto comparisons are constant-time; nonces are single-use; KDF params are
  recorded and bound.
- Every trust boundary validates before it acts.
- IPC/daemon channels authenticate with unguessable, least-privilege credentials.

## Rules

### SEC-01 — Secret material lifecycle
- **Severity:** High
- **Look for:** passphrases, shares, nsec/hex keys, derived secrets held in plain `String`/`Vec`/JS strings with no zeroization; secrets in `localStorage`/cleartext at rest; the "only one type zeroizes" pattern.
- **Fails when:** secret material outlives its use without being scrubbed, or rests in clear.
- **Passes when:** secrets live in zeroizing types, are scrubbed promptly, and are encrypted at rest.
- **Prompt:** "Where does this secret go after use — and what guarantees it's gone?"

### SEC-02 — Secret leakage through logs / errors
- **Severity:** High
- **Look for:** debug logs of raw envelopes/completions; readiness blobs or seed material inlined into `Error.message`; redaction that's substring-based rather than allow-list.
- **Fails when:** a secret can reach a log sink or error string, or redaction is the only (and fragile) defence.
- **Passes when:** secret-bearing values are typed/redacted by allow-list and never logged raw.
- **Prompt:** "If this log line or error fired in production, what secret might ride along?"

### SEC-03 — Crypto correctness
- **Severity:** High
- **Look for:** non-constant-time comparisons (MAC/tag checks via `==`), nonce reuse, missing AAD binding, `Argon2::default()` with params unrecorded, home-rolled cipher stacks.
- **Fails when:** a primitive is used in a way that weakens it (timing leak, unbound ciphertext, unrecorded KDF params).
- **Passes when:** comparisons are constant-time, nonces single-use, AAD bound, params recorded with the record.
- **Prompt:** "Does this use of the primitive preserve the property it depends on?"

### SEC-04 — Input / envelope validation
- **Severity:** High
- **Look for:** decrypt-before-validate ordering; shape-only checks with no membership/signature verification; missing outer-size ceiling on envelopes; accepting plaintext `ws://` on non-loopback.
- **Fails when:** the code acts on untrusted input before fully validating it, or omits a bound.
- **Passes when:** envelopes are validated (size, membership, signature) before being trusted; transports are constrained.
- **Prompt:** "What does this trust about its input before it has verified it?"

### SEC-05 — IPC / daemon authentication
- **Severity:** High
- **Look for:** predictable auth tokens (`daemon-<id>-<unix_secs>`), tokens on the command line (`/proc/*/cmdline`), secrets in inherited env (`/proc/<pid>/environ`), Unix sockets / test servers with no permission floor or token.
- **Fails when:** a local channel can be reached or impersonated by another process/UID.
- **Passes when:** channels use unguessable credentials passed out-of-band, with least-privilege socket/file permissions.
- **Prompt:** "Which local process or UID could talk to this channel that shouldn't?"

### SEC-06 — File / scratch permissions
- **Severity:** Medium
- **Look for:** files created under default umask for secret-bearing data; world-readable staging dirs; `chmod 0777` on artifacts; containers running as root with `:rw` repo mounts.
- **Fails when:** secret-bearing files or mounts are broader than `0o600`/`0o700` need.
- **Passes when:** secret files/dirs are mode-hardened and containers drop privilege.
- **Prompt:** "Who else on this machine can read what this writes?"

### SEC-07 — Defence-in-depth at the shell boundary
- **Severity:** Medium
- **Look for:** disabled CSP (`csp: null`), no SRI on WASM, missing COOP/COEP, broad Tauri capabilities (`core:default` with no narrowing), test servers exposing the full command surface on loopback.
- **Fails when:** the browser/desktop shell omits a defence layer a signing host should have.
- **Passes when:** CSP/SRI/headers are set, capabilities are narrowed, test surfaces are gated.
- **Prompt:** "If one layer fails here, what's the next one — or is this the only one?"

## Review prompts

- Trace one secret end to end: birth, use, death. Where could it escape?
- What does each trust boundary verify before it acts — and what does it assume?
- Which defence here is the *only* defence?
