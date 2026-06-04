# Bucket E — Browser / Desktop Shell Hardening (Hard-Cut Plan)

Status: draft, pending user approval
Related: `bucket-a-bifrost-rs-crypto.md`, `bucket-b-kdf-aad.md`, `bucket-c-secret-hygiene.md` (provides `Passphrase` newtype), `bucket-d-browser-secrets.md` (provides allow-list redactor and typed-error patterns). Ships in the same coordinated release as A+B+C+D.

## Context

The 2026-04-22 audit found the browser and desktop shell layers ship with
minimal or absent defense-in-depth:

- **`igloo-home`** ships `"csp": null` in `tauri.conf.json`, uses `core:default`
  (broad) + `dialog:default` + `autostart:default` with no narrowing, exposes
  a `IGLOO_HOME_TEST_MODE` TCP dispatcher on loopback with zero authentication
  and no feature-flag gating, accepts raw `String` path inputs in
  `export_profile_command` and `list_session_logs_command` without
  canonicalization or scope checks, returns `Result<T, String>` from every
  `#[tauri::command]` so the frontend regex-matches error messages, and
  accepts passphrases as plain `String` with no zeroization.
- **`igloo-pwa`** ships with no CSP, no SRI on the WASM blobs, and no
  COOP/COEP headers. Every secret-carrying state path was covered in
  Bucket D; Bucket E closes the network and loader surface around it.
- **`igloo-chrome`** ships a manifest CSP that allows `connect-src http: ws:`
  (plaintext). Tighter than the PWA, but looser than it needs to be.
- **`igloo-shared`** `dynamicImportModule(url)` uses `/* @vite-ignore */` and
  imports whatever URL the host supplies. The `.wasm` binaries are fetched
  without verification. `scripts/sync-bridge-wasm.mjs` is a plain
  `fs.copyFile` with no digest captured at sync time. Bifrost-rs crypto
  correctness depends on these blobs.

Bucket E closes all of the above. Alpha; no operator-burden concerns.
Ships alongside Buckets A+B+C+D in the same coordinated release.

## Scope

**In:**
- E.1 — Tauri CSP + capabilities narrowing (`igloo-home`).
- E.2 — PWA CSP + COOP/COEP (`igloo-pwa`).
- E.3 — Chrome manifest CSP tightening (`igloo-chrome`).
- E.4 — WASM SHA-384 content integrity: build-time capture embedded in
  generated `.mjs` wrapper, load-time verification, SRI on `<script>` tag
  that loads the wrapper.
- E.5 — Test-mode TCP server hardening: `#[cfg(feature = "test-server")]`
  gate + `IGLOO_HOME_TEST_TOKEN` handshake.
- E.6 — Path canonicalization on every Tauri command that accepts path
  inputs.
- E.7 — Tauri IPC typed errors: `HomeError` enum replaces `Result<T, String>`
  across every `#[tauri::command]`; frontend matches on discriminated union.
- E.8 — Tauri IPC passphrase newtype migration: Bucket C's `Passphrase`
  replaces `String` on every command input carrying secret material.

**Out of scope for Bucket E:**
- Tauri updater hardening — not currently enabled; no attack surface today.
  If the feature is added later, this plan's CSP defaults cover it. Flag.
- Chrome extension MV3 service worker lifecycle hardening — the
  2026-04-02 audit covered this separately; re-audit + cleanup is Bucket J.
- `App.tsx` monolith refactor (audit finding 8) — structural, not security.
  Flag for separate bucket.
- Connect-src tightening to specific relay hosts — operators configure
  arbitrary relays; a per-profile CSP would require runtime policy injection
  that is out of scope. Chrome drops `http:` and `ws:`; beyond that, keep
  `https:` and `wss:` broad.

## Execution Order

Seven PRs. Numbering continues from Bucket D (PR13–PR17).

| PR | Items | Submodule | Depends on |
|---|---|---|---|
| PR18 | E.1 (Tauri CSP + capabilities) | `igloo-home` | none |
| PR19 | E.2 (PWA CSP + COOP/COEP) + E.3 (Chrome CSP tightening) | `igloo-pwa`, `igloo-chrome` | none |
| PR20 | E.4 (WASM SHA-384 integrity) | `bifrost-rs` build script + `igloo-shared` loader + PWA/Chrome sync scripts | none |
| PR21 | E.5 (test-mode server gating) | `igloo-home` | none |
| PR22 | E.6 (path canonicalization) | `igloo-home` | none |
| PR23 | E.7 (Tauri IPC typed errors) | `igloo-home` | none |
| PR24 | E.8 (Tauri IPC passphrase newtype migration) | `igloo-home` | Bucket C PR9 (`Passphrase`) + PR23 (`HomeError`) |

PR18–PR22 are fully independent. PR23 is independent from the others but
large. PR24 depends on both Bucket C's `Passphrase` newtype and PR23's
`HomeError` enum (the command signatures change in both dimensions; clean
to land the structural error-type migration first, then thread the secret
newtypes through).

Rough touch: ~1,800 lines. Largest PR is PR23 (~25 command handlers to
migrate, plus frontend `api.ts` call sites).

---

## E.1 — Tauri CSP + capabilities narrowing

### CSP

Current: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/tauri.conf.json:25-27`:
```json
"security": { "csp": null }
```

Target:
```json
"security": {
  "csp": "default-src 'none'; script-src 'self'; connect-src 'self' ipc: http://ipc.localhost; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'none'; manifest-src 'self';",
  "freezePrototype": true,
  "capabilities": ["default"]
},
```

Rationale (verified by Agent 1):
- Renderer makes **zero direct fetches** (`fetch`, `WebSocket`, `new Worker`,
  `new EventSource`). All renderer ↔ backend traffic goes through Tauri's
  `invoke()` which uses the IPC scheme (`ipc:` / `http://ipc.localhost`
  depending on Tauri version). `connect-src 'self' ipc: http://ipc.localhost`
  covers the IPC path without allowing any outbound network.
- No third-party scripts, no external fonts. `default-src 'none'` is the
  fail-closed base. `script-src 'self'` covers the in-app bundle.
- `'unsafe-inline'` on `style-src` is required by Tauri's runtime style
  injection and React inline styles; scoped narrowly.
- `img-src` allows `data:` and `blob:` for QR payloads (rendered in-app).
- `freezePrototype: true` — additional hardening against prototype-pollution.

**dev CSP**: Tauri supports `devCsp` as a relaxed override for `cargo tauri dev`
with HMR. Add:
```json
"devCsp": "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; connect-src 'self' ws: http: ipc: http://ipc.localhost; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; object-src 'none';"
```
Loosened only as required for Vite HMR (`ws:` for HMR socket, `'unsafe-eval'`
for devtools / React dev refresh). Never shipped.

### Capabilities

Current: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/capabilities/default.json:6`:
```json
["core:default", "dialog:default", "autostart:default"]
```

Target — explicit set only for what's actually used (determined by
cross-referencing `invoke_handler![...]` in `bootstrap.rs` with the
renderer's usage):

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Default capabilities for the Igloo Home renderer.",
  "windows": ["main"],
  "permissions": [
    "core:event:default",
    "core:path:default",
    "core:window:default",
    "core:webview:default",
    "core:app:default",
    "core:menu:default",
    "dialog:allow-confirm",
    "autostart:allow-enable",
    "autostart:allow-disable",
    "autostart:allow-is-enabled"
  ]
}
```

- Drops `core:default` (which bundles every core plugin). Lists only the
  subset the renderer calls.
- Replaces `dialog:default` with `dialog:allow-confirm` — the only dialog
  call in `App.tsx` is `confirm()` (close-confirm dialog). No file-save or
  file-open exposure.
- Replaces `autostart:default` with the three named commands actually
  invoked in `settings.rs`.

**Cross-check at implementation time**: run the app under dev, click every
major flow, verify no `Unauthorized` capability error in the console. Any
missed permission gets added explicitly with a comment citing the feature
that needs it.

### Testing

- Manual: build `cargo tauri build`, open the binary, verify the renderer
  loads, every flow works, no CSP console errors.
- Automated: Playwright `test/igloo-home/` harness currently does full
  onboard → sign flow; re-run and confirm no CSP / capability regressions.
- Unit: add `src-tauri/tests/config_test.rs` that deserializes
  `tauri.conf.json` and asserts the CSP string matches the expected constant
  (prevents silent regression).

---

## E.2 — PWA CSP + COOP/COEP

### CSP

Current: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/index.html` has no CSP.

Target: add to `<head>`:

```html
<meta http-equiv="Content-Security-Policy" content="
  default-src 'self';
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' 'unsafe-inline';
  connect-src 'self' wss: https: ws://localhost:* ws://127.0.0.1:* http://localhost:* http://127.0.0.1:*;
  img-src 'self' data: blob:;
  font-src 'self' data:;
  object-src 'none';
  base-uri 'self';
  frame-ancestors 'none';
  form-action 'none';
  manifest-src 'self';
">
```

- `'wasm-unsafe-eval'` required for WebAssembly compile + instantiate in
  modern Chromium/Firefox CSP-L3.
- `connect-src` — relays are arbitrary host `wss://`; `https:` covers any
  future fetch to non-relay endpoints. Plaintext `ws://` and `http://` are
  disallowed **for non-loopback hosts** — metadata leakage on the wire is
  the concern, and loopback traffic never leaves the machine.
  `ws://localhost:*`, `ws://127.0.0.1:*`, `http://localhost:*`, and
  `http://127.0.0.1:*` are explicitly allowed so the demo harness (dev-relay
  at `ws://localhost:8194` per `.env.example`) and any local dev tooling
  work without a production-time policy relaxation. This matches the
  existing `CLAUDE.md` guidance: "Prefer `localhost` over `127.0.0.1` for
  browser-facing local relay URLs." Aligns with `igloo-shared` audit
  finding 11, which framed the concern as "ws:// on non-loopback."
- `style-src 'self' 'unsafe-inline'` — required by current inline React
  styles and the `styles.css` from `igloo-ui`. Flag for Bucket H (UI) to
  remove inline styles where possible; no action required here.
- `manifest-src 'self'` — PWA manifest.

### COOP / COEP

Add response headers via Vite dev server config + documented production
requirement. In `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/vite.config.ts`:

```ts
server: {
  headers: {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
  },
},
```

Production: document in `igloo-pwa/README.md` "Deployment" section that
the hosting layer must serve the same three headers. COOP `same-origin`
isolates the browsing context from cross-origin windows; COEP `require-corp`
blocks any subresource that isn't CORP-tagged. Together they enable
`crossOriginIsolated` (needed if `SharedArrayBuffer` is ever used, though
not today) and close cross-origin window reference attacks.

### Tradeoff note

COEP `require-corp` may require every subresource (fonts from Google, etc.)
to send `Cross-Origin-Resource-Policy`. Since the PWA ships zero
third-party subresources today (verified: no `<link rel="stylesheet">` or
`<script src="https://...">` in `index.html`), this is compatible.

### Testing

- Serve the built PWA with `make demo-start`, open DevTools → Network →
  inspect response headers. Verify all three COOP/COEP/CORP headers are
  set.
- In DevTools Console: `crossOriginIsolated` → should be `true`.
- Open an arbitrary external page in a new tab, try to script-reference
  back to this window — should fail due to COOP isolation.

---

## E.3 — Chrome manifest CSP tightening

Current `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/public/manifest.json:26-28`:

```json
"content_security_policy": {
  "extension_pages": "script-src 'self' 'wasm-unsafe-eval'; object-src 'self'; connect-src 'self' http: https: ws: wss:;"
}
```

Target: drop plaintext schemes on non-loopback hosts; keep loopback
plaintext for the dev-relay / demo harness.

```json
"content_security_policy": {
  "extension_pages": "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; connect-src 'self' wss: https: ws://localhost:* ws://127.0.0.1:* http://localhost:* http://127.0.0.1:*; img-src 'self' data: blob:; font-src 'self' data:; object-src 'none'; base-uri 'self';"
}
```

- Drops non-loopback `http:` and `ws:` — remote relays must use `wss:`.
  Operators configuring `ws://example.com/relay` get a CSP block from the
  extension.
- Loopback `ws://localhost:*` / `ws://127.0.0.1:*` / `http://localhost:*` /
  `http://127.0.0.1:*` explicitly allowed for the dev-relay at
  `ws://localhost:8194` and any local dev tooling. Traffic stays on the
  machine; no metadata leak.
- Adds `default-src 'none'` as the fail-closed base (previously implicit).
- Adds `style-src`, `img-src`, `font-src` for completeness.

Flag in release notes: the extension will refuse to connect to
non-loopback `ws://` relays after this change. Loopback `ws://` continues
to work for local dev/test. Alpha, no operator burden concern.

### Testing

- Build the extension; run the chrome Playwright suite (`make igloo-chrome-test-e2e`).
  The suite already drives `ws://localhost:*` for the dev-relay — passing
  the suite confirms loopback plaintext works.
- Manually attempt to add a `ws://example.com` relay in the UI; verify
  the UX shows a clear CSP-block error.
- Manually attempt to add a `ws://localhost:8194` relay; verify it
  connects.
- Add a Playwright regression test `loopback_ws_allowed_nonloopback_ws_blocked.spec.ts`
  in `test/igloo-chrome/specs/` that exercises both paths: loopback succeeds,
  non-loopback is blocked by CSP and surfaces a typed error in the UI.

---

## E.4 — WASM SHA-384 content integrity

### Design

Embed the expected SHA-384 of the `_bg.wasm` **directly in the generated
`.mjs` loader wrapper** at build time. The wrapper is self-verifying: it
fetches `_bg.wasm`, computes SHA-384, compares against the embedded hex
literal, and throws before calling `WebAssembly.instantiate` on a mismatch.

Additionally, add `integrity=` (SRI) on the `<script>` tag that imports
the `.mjs` wrapper itself in `index.html` (PWA). Chrome extension resources
are trusted by the extension sandbox; no SRI needed there.

Why embed vs. a separate `wasm.integrity.json`:
- A separate JSON file adds one more fetch and another file the loader has
  to validate. Two-file integrity is a footgun: if the attacker swaps both
  files, the check passes.
- Embedding in the `.mjs` wrapper means: to bypass the check, an attacker
  must swap the `.mjs` too — at which point SRI on the `<script>` tag
  catches it.
- The `.mjs` wrapper is already generated deterministically by
  `build-bridge-wasm.sh`; adding a constant line is trivial.

### Build-side changes (`igloo-shared` + `bifrost-rs` together)

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/scripts/build-bridge-wasm.sh`:
After `wasm-pack build` completes, for each of the two blobs:

```bash
for name in bifrost_bridge_wasm bifrost_profile_wasm; do
  wasm_file="public/wasm/${name}_bg.wasm"
  js_file="public/wasm/${name}.js"
  mjs_file="public/wasm/${name}_loader.mjs"

  # SHA-384 of the wasm binary (raw bytes, hex-encoded).
  wasm_sha384=$(openssl dgst -sha384 -binary "$wasm_file" | openssl base64 -A)
  # SHA-384 of the glue JS (what wasm-bindgen emits).
  js_sha384=$(openssl dgst -sha384 -binary "$js_file" | openssl base64 -A)

  # Generate the self-verifying loader.
  cat > "$mjs_file" <<EOF
// Auto-generated by build-bridge-wasm.sh. Do not edit.
// Embedded SHA-384 of ${name}_bg.wasm captured at build time.
const EXPECTED_WASM_SHA384 = 'sha384-${wasm_sha384}';
const EXPECTED_JS_SHA384 = 'sha384-${js_sha384}';

import init, * as wasmExports from './${name}.js';

async function sha384Base64(buf) {
  const digest = await crypto.subtle.digest('SHA-384', buf);
  return 'sha384-' + btoa(String.fromCharCode(...new Uint8Array(digest)));
}

export default async function loadWasm(options = {}) {
  const wasmUrl = options.module_or_path ?? new URL('./${name}_bg.wasm', import.meta.url);
  const response = await fetch(wasmUrl);
  if (!response.ok) {
    throw new Error('wasm_fetch_failed: status ' + response.status);
  }
  const binary = await response.arrayBuffer();
  const actual = await sha384Base64(binary);
  if (actual !== EXPECTED_WASM_SHA384) {
    throw new Error('wasm_integrity_check_failed: expected=' + EXPECTED_WASM_SHA384 + ' actual=' + actual);
  }
  await init({ module_or_path: binary });
  return wasmExports;
}

export const __integrity = Object.freeze({
  wasmSha384: EXPECTED_WASM_SHA384,
  jsSha384: EXPECTED_JS_SHA384,
});
EOF
done
```

The `__integrity` named export lets higher-level code assert the SHA values
programmatically (useful in tests). The self-verification runs unconditionally.

### Loader-side changes (`igloo-shared`)

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/loader-core.ts`:

- Remove the unconditional `console.warn` that logs `loader_import_url`
  (audit finding).
- No other changes — the verification runs inside the `.mjs` wrapper; the
  loader just calls the wrapper's `default()` export as before.

### PWA SRI

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/index.html`: the
PWA dynamically imports the `.mjs` via `configureWasmBridgeLoader(url)`,
not a static `<script src>`. So SRI on the `<script>` tag isn't the
right mechanism here.

Alternative: have the PWA fetch and SHA-384-verify the `.mjs` before calling
`dynamicImportModule`. Implementation: extend `loader-core.ts` to fetch
the URL, SHA-verify against an expected hash passed in the config, then
`dynamicImportModule(URL.createObjectURL(new Blob([verifiedText], { type: 'text/javascript' })))`.

Simpler: accept that the `.mjs` is same-origin + served by the same
deployment that served the HTML; trust origin integrity at the HTML level,
and let the embedded-hash `.mjs` catch `.wasm` swaps. Document this:

```
Integrity contract:
  index.html       ← trusted by origin
  *_loader.mjs     ← trusted by same-origin fetch; contains SHA-384 of .js + _bg.wasm
  *.js             ← verified by .mjs via EXPECTED_JS_SHA384 (future enhancement)
  *_bg.wasm        ← verified by .mjs via EXPECTED_WASM_SHA384
```

Today, the `.mjs` verifies the `.wasm`. Verifying the `.js` glue is a
nice-to-have; flag for a follow-up pass. The main attack surface (a
tampered crypto binary) is covered.

### Sync-script changes

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/scripts/sync-bridge-wasm.mjs`:
No changes. The script copies every file in the `public/wasm/` tree; the
new embedded-hash `.mjs` goes along automatically.

Same for `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/scripts/sync-bridge-wasm.mjs`.

### Testing

- Build. Open PWA. Verify signer initializes (WASM loads). Open devtools →
  Network → inspect the `.wasm` response → no change.
- Tamper test: after build, flip one byte of
  `igloo-pwa/public/wasm/bifrost_bridge_wasm_bg.wasm` with `dd`. Reload the
  PWA. Expected: console error "wasm_integrity_check_failed" and the
  signer fails to initialize.
- Playwright: add `test/igloo-pwa/specs/wasm-integrity.spec.ts` that
  substitutes a byte in the `.wasm` before page load and asserts the
  expected error message appears in the console / UI.

---

## E.5 — Test-mode TCP server hardening

### Feature-flag gating

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/Cargo.toml`:

```toml
[features]
default = []
test-server = []
```

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/test_mode.rs`:

Wrap the entire module body in:
```rust
#![cfg(feature = "test-server")]
```

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs`:

```rust
#[cfg(feature = "test-server")]
if crate::paths::is_test_mode() {
    crate::test_mode::start_server(&app.handle())?;
}

#[cfg(not(feature = "test-server"))]
if crate::paths::is_test_mode() {
    tracing::warn!("IGLOO_HOME_TEST_MODE set but binary built without test-server feature; ignoring");
}
```

**Release builds** never enable `test-server`. Playwright Chrome harness
(the main consumer of the test server today) invokes `cargo build --features test-server`
in its setup; add that flag to:
- `/home/cscott/Repos/frostr/frostr-infra/test/igloo-home/run-e2e.sh`
- Any CI job that runs igloo-home E2E

### Token handshake

In `test_mode.rs::start_server`, require `IGLOO_HOME_TEST_TOKEN` env var at
startup (independent of the existing `IGLOO_HOME_TEST_MODE` + `IGLOO_HOME_TEST_PORT`).
If unset → refuse to start listener, log error, exit function cleanly.

Token format: 64 hex chars (same as Bucket C's daemon token). Generated by
the Playwright harness at test-spawn time, passed to the Tauri process via
env, passed to the test client via shared fixture.

Connection protocol change: every TCP connection's first line is
`{"token": "..."}`. Server validates constant-time (using `subtle` from
Bucket A PR1 — pull in `subtle.workspace = true` for `bifrost-app` already
done). Token mismatch → close connection, no response (no timing leak).
Token match → proceed to the existing `TestRequest` JSON protocol.

### Dispatcher drift

Audit finding 10 identified the test dispatcher drifting from the Tauri
command list. PR21 also:
- Removes the legacy `refresh_all_peers` alias at `test_dispatch.rs:278-283`.
- Adds `import_profile_from_bfprofile` and `recover_profile_from_bfshare`
  (Tauri commands that the test dispatcher currently lacks).
- Adds a compile-time assertion that the test dispatch table covers every
  command in `invoke_handler![...]`. Implementation: `build.rs` parses
  `bootstrap.rs`'s `invoke_handler!` macro and cross-checks
  `test_dispatch.rs`. Simpler alternative: a `#[cfg(test)]` test in
  `test_dispatch.rs` that asserts `COMMAND_NAMES` (a module-level array)
  matches a known set; add/remove to the array in the same PR as
  adding/removing Tauri commands. Choose the latter (simpler; manual sync
  with a guard test).

### Testing

- Release build without `test-server` feature: verify `IGLOO_HOME_TEST_MODE=1`
  logs the warning and the TCP server does not bind a port.
- Debug build with `test-server` feature: verify TCP server starts, rejects
  connections that don't send the token first, accepts connections that
  do.
- Harness: update Playwright setup to generate a random 64-hex token per
  test run and pass via `IGLOO_HOME_TEST_TOKEN`.

---

## E.6 — Path canonicalization on Tauri commands

### Target commands

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs`:
- `export_profile_command` (line 134-143): accepts `ExportProfileInput.destination_dir: String`.
- `list_session_logs_command` / `resolve_session_log_runtime_dir` (line 301-314): accepts `ListSessionLogsInput.runtime_dir: Option<String>`.

### Canonicalization helper

New helper in `bifrost-profile` or `igloo-home-tauri` (prefer the latter for
now since it's Tauri-specific; extract to shared crate if other hosts need it):

```rust
pub fn canonicalize_under_scope(
    raw: &str,
    allowed_roots: &[PathBuf],
) -> Result<PathBuf, PathScopeError> {
    let input = Path::new(raw);

    // Canonicalize. If the path doesn't exist yet (export destination dir),
    // canonicalize the parent and re-append.
    let canonical = if input.exists() {
        input.canonicalize()?
    } else {
        let parent = input.parent().ok_or(PathScopeError::NoParent)?;
        let file_name = input.file_name().ok_or(PathScopeError::NoFileName)?;
        parent.canonicalize()?.join(file_name)
    };

    // Verify the canonical path is inside at least one allowed root.
    for root in allowed_roots {
        let canonical_root = root.canonicalize()?;
        if canonical.starts_with(&canonical_root) {
            return Ok(canonical);
        }
    }

    Err(PathScopeError::OutsideAllowedRoots {
        path: canonical,
        roots: allowed_roots.to_vec(),
    })
}
```

`PathScopeError` is a new variant of `HomeError` (PR23).

### Allowed roots

For `export_profile_command`: allow the app's `data_dir()` and the user's
home directory's `Documents/` (common export target). Explicit:
```rust
let allowed = vec![
    tauri::path::BaseDirectory::AppData.resolve(&app)?,
    tauri::path::BaseDirectory::Document.resolve(&app)?,
];
```

For `list_session_logs_command`: allow only `data_dir()`; session logs
don't belong anywhere else.

### Testing

- `canonicalize_under_scope_accepts_child_of_allowed_root`.
- `canonicalize_under_scope_rejects_path_traversal` — `"../../etc/passwd"`
  → `PathScopeError::OutsideAllowedRoots`.
- `canonicalize_under_scope_rejects_symlink_escape` — create a symlink
  inside `data_dir` pointing to `/tmp`; request the symlink; assert
  rejection (canonicalization resolves symlinks).
- `canonicalize_under_scope_rejects_absolute_path_outside_roots` —
  `/tmp/export.bfprofile` → rejected.

---

## E.7 — Tauri IPC typed errors (`HomeError`)

### The shape

New module `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/error.rs`:

```rust
#[derive(Debug, thiserror::Error, serde::Serialize)]
#[serde(tag = "kind", content = "detail", rename_all = "snake_case")]
pub enum HomeError {
    /// Profile already exists with the given id.
    #[error("profile already exists")]
    ProfileAlreadyExists { id: String },

    /// Passphrase could not decrypt the profile.
    #[error("invalid passphrase")]
    InvalidPassphrase,

    /// Encrypted profile package could not be decoded.
    #[error("invalid package")]
    InvalidPackage { reason: String },

    /// An onboarding operation is already in progress for this profile.
    #[error("onboarding already pending")]
    OnboardingPending { profile_id: String },

    /// Path outside the allowed root directories.
    #[error("path outside allowed roots")]
    PathOutsideAllowedRoots { path: String },

    /// Session is not active for the requested profile.
    #[error("session not active")]
    SessionNotActive,

    /// Tauri runtime / plugin error (opaque internal error).
    #[error("runtime error")]
    Runtime { message: String },

    /// Bifrost-rs returned an error; message is operator-safe (secret-scrubbed).
    #[error("bifrost error")]
    Bifrost { message: String },

    /// Unexpected internal error. Should not happen in normal operation.
    #[error("internal error")]
    Internal { message: String },
}
```

`serde(tag = "kind", content = "detail")` serializes to
`{"kind": "invalid_passphrase", "detail": null}` or
`{"kind": "invalid_package", "detail": {"reason": "..."}}`. TypeScript
discriminated union matches on `kind`.

### Command migration

Every `#[tauri::command]` signature changes from
`Result<T, String>` → `Result<T, HomeError>`.

Every `.map_err(|e| e.to_string())` pattern replaced with an explicit
conversion. `From` impls for common upstream error types:
- `From<bifrost_app::host::Error>` → `HomeError::Bifrost`
- `From<bifrost_profile::Error>` → map by variant to specific `HomeError` types
- `From<anyhow::Error>` → `HomeError::Runtime` (catch-all; minimize usage)

### Secret scrubbing

The `Bifrost { message }` and `Runtime { message }` variants carry strings
that are shown to the operator. Before constructing these variants, run
the message through a secret-scrubber that ensures no passphrase-adjacent
context is included:

```rust
fn scrub_for_display(raw: &str) -> String {
    // Strip anything that looks like a hex-32 or longer hex run (potential keys).
    // Redact the literal passphrase buffer if present (can't really happen, but defense-in-depth).
    // Cap length at 512 chars.
    // ...
}
```

Implementation detail; the Bucket D allow-list redactor pattern applies
here too.

### Frontend migration

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/lib/api.ts`:

Replace `normalizeHomeImportError` (regex-based) with a discriminated-union
matcher:

```ts
type HomeErrorPayload =
  | { kind: 'profile_already_exists'; detail: { id: string } }
  | { kind: 'invalid_passphrase'; detail: null }
  | { kind: 'invalid_package'; detail: { reason: string } }
  | { kind: 'onboarding_pending'; detail: { profile_id: string } }
  | { kind: 'path_outside_allowed_roots'; detail: { path: string } }
  | { kind: 'session_not_active'; detail: null }
  | { kind: 'runtime'; detail: { message: string } }
  | { kind: 'bifrost'; detail: { message: string } }
  | { kind: 'internal'; detail: { message: string } };

export function isHomeError(value: unknown): value is HomeErrorPayload {
  return typeof value === 'object' && value !== null && 'kind' in value;
}

export function homeErrorMessageForUser(err: HomeErrorPayload): string {
  switch (err.kind) {
    case 'profile_already_exists':
      return `A profile with id ${err.detail.id} already exists.`;
    case 'invalid_passphrase':
      return 'Incorrect passphrase.';
    // ...
  }
}
```

Every `.catch` call site in `api.ts` switches from regex to
`isHomeError` + `homeErrorMessageForUser`. No more string parsing.

### Testing

- Unit: `home_error_serialize_round_trip` — serialize each variant, JSON-parse, assert shape matches `HomeErrorPayload`.
- Unit: `scrub_for_display_removes_hex_runs` — feed `"decrypt failed: key=11..."`, assert output doesn't contain `11`.
- Integration: trigger each error path via the test-mode server; assert the returned JSON has the expected `{kind, detail}` shape.
- Frontend: vitest unit tests for `isHomeError` + `homeErrorMessageForUser` on each variant.

---

## E.8 — Tauri IPC passphrase newtype migration

### Scope

Every Tauri command input that carries secret material adopts Bucket C's
`Passphrase` (re-exported from `bifrost_core::secret`).

### serde adapter

`Passphrase` is not `Deserialize` by default (per Bucket C). Add a
`#[serde(transparent)]` or `#[serde(deserialize_with = "...")]` shim on
the Tauri command input struct:

```rust
use bifrost_core::secret::Passphrase;

#[derive(serde::Deserialize)]
pub struct ImportProfileFromRawInput {
    pub profile_id: String,
    pub group_package_json: String,
    pub share_package_json: String,
    #[serde(deserialize_with = "deserialize_passphrase")]
    pub passphrase: Passphrase,
}

fn deserialize_passphrase<'de, D>(deserializer: D) -> Result<Passphrase, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let raw = String::deserialize(deserializer)?;
    Ok(Passphrase::new(raw))
}
```

This keeps `Passphrase` non-`Deserialize` in general (can't be
accidentally deserialized into a persisted struct) while allowing the
explicit Tauri-input conversion.

### Command migration targets (from Agent 1)

| Command | Secret field(s) |
|---|---|
| `import_profile_from_raw_command` | `passphrase` |
| `import_profile_from_onboarding_command` | `passphrase`, `onboarding_password` |
| `connect_onboarding_package_command` | `onboarding_password` |
| `finalize_connected_onboarding_command` | `passphrase` |
| `import_profile_from_bfprofile_command` | `passphrase`, `package_password` |
| `recover_profile_from_bfshare_command` | `passphrase`, `package_password` |
| `apply_rotation_update_command` | `passphrase`, `onboarding_password` |
| `export_profile_command` | `passphrase` |
| `export_profile_package_command` | `passphrase`, `package_password` |
| `publish_profile_backup_command` | `passphrase` |
| `create_generated_onboarding_package_command` | `package_password` |
| `start_profile_session_command` | `passphrase` |

12 commands, ~20 field migrations.

### Secret-bearing command outputs

`create_generated_keyset_command`, `create_rotated_keyset_command` return
a `GeneratedKeyset` containing `nsec` + shares with `seckey` hex. These
return `Serialize`d output that crosses the Tauri IPC boundary to the
frontend, where Bucket D stripped persistence. The frontend receives them
into a non-persisted React state variable (`generatedKeyset` is removed
from `PwaPersistedState` in Bucket D — the analog should happen in
igloo-home's React store too).

Add to `igloo-home`'s frontend state audit: confirm no `localStorage` or
`sessionStorage` write includes `generatedKeyset`-shaped data. Out-of-bucket
finding if any found.

### Frontend side

TypeScript `Passphrase` type is a `Secret<string>` from `igloo-shared`
(Bucket D PR13). The frontend does:

```ts
import { Secret } from 'igloo-shared';

const passphrase = Secret.of(inputValue);  // captured from prompt
await invoke('import_profile_from_raw_command', {
  input: {
    profile_id,
    group_package_json,
    share_package_json,
    passphrase: passphrase.expose(),  // explicit expose at IPC boundary
  },
});
// passphrase is dropped when the function returns; no localStorage write.
```

The `expose()` call is the audit seam — every IPC call that sends a secret
has a greppable `.expose()` site. CI test: no code outside `api.ts` and
the form-handling boundary may call `.expose()`.

### Testing

- `passphrase_command_rejects_when_field_missing` — JSON without the
  passphrase field returns a deserialization error.
- `passphrase_is_redacted_in_any_error_path` — simulate a command failure
  after the passphrase is received; assert the thrown `HomeError` does
  not contain the passphrase bytes in any `message` string.
- Frontend: grep CI check `rg '\.expose\(\)' src/` returns only sites
  near the `invoke(...)` boundary.

---

## Critical Files

Modify (`igloo-home`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/tauri.conf.json` (CSP, devCsp, freezePrototype)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/capabilities/default.json` (narrow permissions)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/Cargo.toml` (add `test-server` feature)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/bootstrap.rs` (cfg-gate test server init)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/test_mode.rs` (full cfg gate + token handshake)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/test_dispatch.rs` (drop legacy alias, add missing commands, assertion test)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/app/commands.rs` (migrate every `Result<T, String>` → `Result<T, HomeError>`, `Passphrase` inputs, path canonicalization)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/models.rs` (input structs adopt `Passphrase`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/error.rs` (NEW — `HomeError` enum)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/src/path_scope.rs` (NEW — `canonicalize_under_scope`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src-tauri/tests/config_test.rs` (NEW — CSP regression test)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/lib/api.ts` (typed-error matcher replaces regex)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/run-e2e.sh` (add `--features test-server`)

Modify (`igloo-pwa`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/index.html` (CSP meta)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/vite.config.ts` (COOP/COEP headers)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/README.md` (deployment headers section)

Modify (`igloo-chrome`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/public/manifest.json` (tighten CSP)

Modify (`igloo-shared`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/scripts/build-bridge-wasm.sh` (emit self-verifying `.mjs` with embedded SHA-384)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/loader-core.ts` (remove `loader_import_url` console log)

Reuse (do not re-invent):
- `Passphrase` newtype (Bucket C PR9).
- `subtle::ConstantTimeEq` (Bucket A PR1) for test-server token compare.
- Bucket D's `Secret<T>` TypeScript wrapper for the frontend `passphrase` carrier before `.expose()` at the IPC boundary.
- Bucket D's allow-list redactor pattern (`observability-schema.ts`) for `HomeError::Bifrost.message` scrubbing.

## Verification

Per PR:

**PR18 (Tauri CSP + capabilities):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-home
cargo test -p igloo-home-tauri --offline
cargo tauri build
# Run the built binary; click every major flow; verify no CSP / capability errors in DevTools.
make igloo-home-test-visual  # visual regression
```

**PR19 (PWA + Chrome CSP):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make demo-start
# Open PWA in browser; DevTools → Network → verify COOP/COEP headers;
# DevTools → Console → `crossOriginIsolated` should be `true`.
make igloo-pwa-test-e2e
make igloo-chrome-test-e2e
```

**PR20 (WASM SHA-384 integrity):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make browser-wasm-sync
# Verify public/wasm/*.mjs contains `const EXPECTED_WASM_SHA384 = 'sha384-...'`.
make igloo-pwa-test-e2e  # includes new integrity regression test
# Tamper test: flip a byte of _bg.wasm; assert wasm_integrity_check_failed.
```

**PR21 (test-mode server gating):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-home
# Release build without feature:
cargo build --release -p igloo-home-tauri
IGLOO_HOME_TEST_MODE=1 IGLOO_HOME_TEST_PORT=9999 ./target/release/igloo-home &
nc -z 127.0.0.1 9999 && echo "LEAK: server bound in release" || echo "ok: no bind"
# Debug build with feature:
cargo build --features test-server -p igloo-home-tauri
IGLOO_HOME_TEST_MODE=1 IGLOO_HOME_TEST_PORT=9999 IGLOO_HOME_TEST_TOKEN=$(openssl rand -hex 32) ./target/debug/igloo-home &
# Send request without token line: expect disconnect, no dispatch.
# Send request with wrong token: expect disconnect.
# Send request with correct token: expect dispatch.
make test-demo  # end-to-end Chrome/Home demo harness on the new protocol
```

**PR22 (path canonicalization):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-home
cargo test -p igloo-home-tauri path_scope --offline
# Integration: trigger export with "../../etc/export.bfprofile"; assert typed error.
```

**PR23 (Tauri IPC typed errors):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-home
cargo test -p igloo-home-tauri --offline
cargo clippy -p igloo-home-tauri --all-targets --offline --no-deps -- -D warnings
npm test  # frontend vitest
# Grep: rg 'Result<.*, String>' src-tauri/src/app/commands.rs returns no matches.
# Grep: rg '\.message.\s*(match|test)' src/ returns no matches (no regex on errors).
```

**PR24 (Passphrase newtype migration):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-home
cargo test -p igloo-home-tauri --offline
# Grep: rg 'passphrase:\s*String' src-tauri/src/ returns no matches.
# Grep: rg '\.expose\(\)' src/ returns only sites in api.ts or adjacent form-submit.
make igloo-home-test-desktop-xvfb  # full desktop E2E on new signatures
```

**Full-bucket verification (after PR24):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-release
```

## Cross-Repo Coordination

Ships in the same coordinated release as Buckets A + B + C + D. 24 PRs
total across the release.

Downstream impact:
- `igloo-home` operators: no observable behavior change unless an operator
  was scripting against the old `Result<T, String>` regex-matchable error
  format (unlikely; internal-only contract) or relied on `IGLOO_HOME_TEST_MODE`
  from a release build (will now warn-and-ignore).
- `igloo-pwa` operators: PWA will refuse non-`wss:`/`https:` outbound
  connections. Deployment layer must serve COOP/COEP headers in production.
  Release notes document this.
- `igloo-chrome` operators: extension refuses `ws://` and `http://` relay
  URLs. Relay configuration UI surfaces a clear error.
- `igloo-shared` / build infrastructure: `wasm-pack` artifacts now come
  with embedded SHA-384 in the `.mjs` loader. Any consumer bypassing the
  `.mjs` (e.g. directly calling `init({ module_or_path })`) loses the
  integrity check — grep to confirm no such bypass exists.

No version bumps specific to Bucket E.

## Out-of-Bucket Flags

- **Tauri updater hardening** — not currently enabled. If added in a later
  release, the CSP landed in PR18 already covers the update channel (no
  outbound HTTP allowed). Revisit when updater lands.
- **Connect-src tightening to specific relay hosts** — operators configure
  arbitrary relays; a per-profile CSP would require runtime policy
  injection. Out of scope.
- **`App.tsx` monolith refactor** (igloo-home audit finding 8) —
  structural, not security. Flag for a later "browser-host modularization"
  bucket.
- **`igloo-chrome` 2026-04-02 re-audit** — the background.ts monolith +
  onboarding lifecycle bug noted in the prior audit are still present.
  Targeted re-audit is Bucket J.
- **`.js` wasm-bindgen glue SHA-384 verification** — the `.mjs` currently
  verifies the `.wasm`. Extending to verify the `.js` glue before `init`
  is nice-to-have; flag as a follow-up to PR20.
- **Per-profile relay CSP** — see above.

## Summary

Seven PRs, ~1,800 lines, across `igloo-home`, `igloo-pwa`, `igloo-chrome`,
`igloo-shared`. Closes the defense-in-depth gap around the browser and
desktop shells:

- **Tauri CSP** goes from `null` → strict `default-src 'none'` + ipc-only
  `connect-src`. Capabilities narrow from `core:default` to the specific
  subset the renderer calls.
- **PWA CSP + COOP/COEP** land simultaneously — `default-src 'self'`,
  WASM-enabled, `wss://` + `https://` for remote + loopback `ws:`/`http:`
  for the dev-relay. Cross-origin isolation via COOP/COEP.
- **Chrome manifest CSP** drops non-loopback plaintext `http:` / `ws:`
  from `connect-src`. Loopback (`localhost` / `127.0.0.1`) plaintext
  remains allowed so the dev-relay + demo harness work out of the box.
  Extension refuses insecure remote relays at the browser policy layer.
- **WASM SHA-384 integrity** is captured at build time and embedded
  directly in the generated `.mjs` loader wrapper. Self-verifying:
  swapping the `.wasm` fails before `WebAssembly.instantiate`.
- **Test-mode TCP server** is gated behind `#[cfg(feature = "test-server")]`
  (absent in release builds) AND requires a constant-time token handshake.
  Test harness passes the token per-run. Legacy dispatch-table alias
  removed; dispatch ↔ Tauri-handler drift pinned by a test.
- **Path canonicalization** on every Tauri command that accepts paths;
  typed `PathOutsideAllowedRoots` error on rejection.
- **`HomeError` enum** replaces `Result<T, String>` across every Tauri
  command. Discriminated union consumed on the frontend — no more regex
  matching on error strings. Messages scrubbed before crossing the IPC
  boundary.
- **`Passphrase` newtype** (Bucket C) replaces `String` on every Tauri
  command input carrying secret material. Explicit `.expose()` site at
  the IPC boundary. Frontend uses `Secret<string>` (Bucket D) to carry
  the captured passphrase before the boundary.

Ships in the same coordinated release as Buckets A + B + C + D.
