# igloo-paper Sync Churn Investigation

Date: 2026-05-25

## Scope

Investigate whether `make igloo-paper-sync` still creates generated-file churn
after the Paper MCP/export workflow hardening.

## Result

Blocked before export by Paper Desktop state. The MCP endpoint was reachable,
but the Paper tool response reported:

```text
Open a Paper file to use this tool.
```

The exporter now surfaces that tool-level error directly:

```text
paper_mcp.PaperMCPError: Paper tool get_basic_info returned an error: Open a Paper file to use this tool.
```

No generated files were changed by this failed sync attempt, so this run cannot
confirm or rule out repeat-sync churn.

## Follow-Up

Re-run the churn check when Paper Desktop is open to the `igloo-ui-shared` file
on the `core` page:

```bash
make igloo-paper-sync
git -C repos/igloo-paper status --short
make igloo-paper-sync
git -C repos/igloo-paper status --short
```

If the second sync is dirty without source edits, classify each changed path as
timestamp/order nondeterminism, Paper canvas drift, export metadata drift, or
generated screenshot drift before patching.
