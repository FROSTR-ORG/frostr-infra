---
name: frostr-paper-ui-workflows
description: Use when working on FROSTR Paper Desktop, igloo-paper exports, igloo-ui design alignment, igloo-pwa screenshots, or choosing between Paper-to-export, export-to-UI, and dual Paper plus UI workflows.
---

# FROSTR Paper/UI Workflows

Start by classifying the request into exactly one workflow:

1. Paper source -> `igloo-paper`: edit or sync Paper Desktop source, then export and verify `repos/igloo-paper`.
2. `igloo-paper` -> `igloo-ui`: compare Paper references to rendered UI, then update shared components and app previews.
3. Paper source + `igloo-ui`: make the same product change in Paper MCP and the React implementation, then sync, compare, and commit both tracks.

Read `dev/docs/WORKFLOWS.md` first, then `dev/docs/DESIGN.md` for boundary rules. For live Paper Desktop edits, also read `repos/igloo-paper/docs/mcp-edit-workflow.md`.

Use root `make` targets for Paper and token sync:

```bash
make igloo-paper-sync
make igloo-paper-verify STRICT=1
make igloo-ui-paper-token-sync
make igloo-ui-paper-token-check
```

For visual alignment loops, capture PWA screens and generate the Markdown review report:

```bash
npm --prefix test run test:e2e:igloo-pwa:visual
npm --prefix test run test:visual:report
```

Keep commits scoped by repo. Commit implementation submodules first, then the parent workspace submodule pointer and docs.
