# dev/fixtures

Throwaway devnet key material for the fast native dev loop (`make dev`).

**These are NOT secrets.** They are a fixed 2-of-3-style devnet keyset wired to a
local relay (`ws://127.0.0.1:8194`), committed on purpose so `make dev` never has
to keygen or onboard. The device profile/share are sealed with the trivial
password `devpass`. Never reuse any of this for anything real.

- `dev-keyset/` — fixed 2-of-2 keyset (`alice` = co-signer loaded by `make dev`,
  `bob` = the PWA device).
- `dev-device.bfprofile` — `bob` exported as an importable device backup. First
  run: in the PWA, **Import Existing Device** with this file + password `devpass`.
- `dev-device.bfshare` — `bob`'s encrypted share artifact (for the future
  zero-import auto-seed).

Regenerate with `dev/fixtures/regen.sh` (rebuilds the binaries if needed). The
keyset is intentionally stable: the PWA device persists in the browser across
`make dev` restarts and must keep matching the co-signer's group.
