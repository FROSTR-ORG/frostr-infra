# Design Handoff

This document describes the workspace-owned design handoff between
`repos/igloo-paper` and `repos/igloo-ui`.

## Ownership

`repos/igloo-paper` is reference material. It stores a versioned export from
Paper Desktop, design-contract metadata, generated reference HTML/images, and
token source files.

`repos/igloo-ui` is an independent React UI package. It must not import
`igloo-paper`, run Paper Desktop tooling, depend on Paper MCP, or treat
`igloo-paper` as a package-level design system. It owns package-local source,
tests, generated token files, and published artifacts.

The parent `frostr-infra` workspace owns the bridge between the two repos.
That bridge can be removed with the parent repo without leaving runtime,
package, or build-time dependencies inside `igloo-ui`.

## Command Surface

Use root `make` targets only:

```bash
make igloo-paper-sync
make igloo-paper-verify
make igloo-ui-paper-token-sync
make igloo-ui-paper-token-check
```

`make igloo-paper-sync` exports the live Paper canvas and runs strict design
verification by default. `make igloo-paper-verify` validates the checked-in
design export without refreshing it. Both require Paper Desktop and Paper MCP.

`make igloo-ui-paper-token-sync` refreshes the package-local token files in
`repos/igloo-ui/src/tokens/`. `make igloo-ui-paper-token-check` verifies that
those token files match the current parent-owned handoff.

Do not add a package-local sync script to `repos/igloo-ui`.

## File Flow

The flow is one-way:

1. Paper Desktop canvas
2. `repos/igloo-paper` generated export and design contract
3. parent workspace token handoff script
4. `repos/igloo-ui/src/tokens/design-tokens.ts`
5. `repos/igloo-ui/src/tokens/design-tokens.css`

The parent script currently lives at:

```bash
scripts/sync-igloo-paper-tokens-to-ui.mjs
```

That script is private workspace plumbing. Contributors should use the root
`make` targets instead of calling it directly.

## Boundary Rules

- `igloo-paper` may name Paper-specific source paths, canvas IDs, screenshots,
  generated reference pages, and contract metadata.
- `frostr-infra` may name both repos because it coordinates the handoff.
- `igloo-ui` must keep generated token files source-agnostic.
- `igloo-ui` must not reference `igloo-paper`, Paper Desktop, Paper MCP, or
  historical `design-system/` paths in source, tests, package scripts, or
  package docs.
- Runtime apps must consume `igloo-ui` as a UI package, not `igloo-paper` as a
  design dependency.

## Validation

After refreshing design material, run:

```bash
make igloo-paper-verify STRICT=1
make igloo-ui-paper-token-check
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix test run test:guards
```

`make igloo-paper-verify STRICT=1` requires the Paper MCP environment. The
guard suite may also require initialized release-doc submodules for link checks.

## Release Treatment

Treat `igloo-paper` pointer updates as design-reference checkpoints unless they
are paired with implementation changes in a product repo. They do not require
`igloo-ui` to release and do not create runtime validation obligations by
themselves.

When token changes are intentionally accepted into `igloo-ui`, commit the
package-local generated token files with the implementation change that consumes
them.
