# Workspace Gotchas

The footguns that most often cost time in `frostr-infra`. Each entry says what
to do and why. This is the long-tail companion to the short list in
[`../../AGENTS.md`](../../AGENTS.md); keep the few highest-impact items mirrored
there.

## Toolchain

- **Install Rust via rustup, not Homebrew.** Homebrew Rust on `PATH` is
  unsupported and breaks browser WASM builds. `rust-toolchain.toml` pins stable
  with the `wasm32-unknown-unknown` target and `rustfmt` + `clippy`; rustup
  honors it automatically.
- **Pin `wasm-pack` to `0.14.0`** (`cargo install --locked --version 0.14.0
  wasm-pack`). Other versions can emit incompatible artifacts.
- **macOS needs `llvm`/`clang`** for a WASM-capable `clang`. Without it the
  WASM build fails with opaque compiler errors.
- **Verify before building:** `make wasm-toolchain-check` confirms the toolchain
  is set up before you spend time on a failing WASM build.
- **Committed browser WASM must not drift from `bifrost-rs`.** The blobs in
  `repos/igloo-shared/public/wasm` are compiled from the bifrost-rs WASM crates;
  once they silently lagged the Rust core (still exporting a removed relay-backup
  API). A guard (`test:guards:wasm`) stamps a hash of the WASM-relevant crates
  (native-only crates excluded) into `test/browser-wasm-source.stamp` and fails if
  the committed blobs are stale. `make browser-wasm-refresh` rebuilds **and**
  re-stamps; after a bifrost-rs bump that touches WASM crates, rebuild + re-stamp,
  commit `public/wasm` in igloo-shared, bump its pointer, and commit the stamp.
- **JavaScript/TypeScript uses npm, not Bun.** Run JS workflows through `make`
  or `npm --prefix test ...`; do not assume a Bun runtime.

## Demo Harness

- **`make demo-start` backgrounds by default.** Use `make demo-foreground` when
  you want to stay attached to compose output in the current terminal.
- **The relay port auto-resolves.** If the default is occupied, the harness
  picks the next free port and records it in
  `./.tmp/test-harness/demo-relay-port.txt`. Pin one with
  `make demo-start PORT=<port>` when you need a fixed port.
- **`.env` is optional, not required.** `make repo-check` only warns if it is
  missing; the demo runs without it.

## Release Packaging

- **Chrome dev/test builds are not release-shape proof.** `igloo-chrome` keeps
  local relay CSP entries and debug command seams in normal builds so the
  workspace harness and manual demo relays work. Public release candidates must
  use the repo-local release path (`npm --prefix repos/igloo-chrome run
  build:release` or `release:candidate`), which runs
  `check:production-package` and fails if local relay CSP entries or
  `ext.debug.*` command strings remain in the production output.
- **Home beta artifacts are unsigned by design.** `make
  igloo-home-package-release` stages the current host's unsigned Tauri artifact
  plus `SHA256SUMS` and `manifest.json` under `./.tmp/release/igloo-home/`.
  macOS Developer ID signing/notarization, Linux deb/rpm packages, and GitHub
  Actions release upload are post-beta follow-ups, not prerequisites for this
  primitive.

## Scratch & State

- **Generated output belongs under `./.tmp/`,** not tracked-looking paths like
  `data/`. The live demo-harness scratch path is `./.tmp/test-harness/`; the
  prep/timing scratch path is `./.tmp/test-prebuild/`.
- **Override scratch locations** with `FROSTR_TEST_HARNESS_DIR` and
  `FROSTR_TEST_PREBUILD_DIR` only when you intentionally want a different path.
- **Repair a stale or unwritable scratch tree** with `make repo-reset` rather
  than hand-deleting directories.

## Submodules

- **Use non-recursive submodule commands.** Recursive operations from the parent
  workspace are unsupported and can scramble pointers.
- **Commit inside the submodule first, then bump the pointer here.** A parent
  commit that points at an unpushed submodule commit is unreproducible for
  everyone else.
- **Treat each repo under `repos/` as an independent project** with its own root
  manuals and release surface.

## Design Reference Boundary

- **`repos/igloo-paper` is reference-only design material.** Never import it into
  runtime code, product packages, or app builds.
- **Design tokens flow one way:** Paper canvas → `igloo-paper` export → parent
  workspace sync → `igloo-ui` package-local generated files. `igloo-ui` does not
  import or run Paper tooling. See [`DESIGN.md`](./DESIGN.md) for the full
  handoff rules.
- **Paper sync targets are manual** and excluded from default test/CI lanes:
  `make igloo-paper-sync` / `make igloo-paper-verify` require Paper desktop and
  Paper MCP.
