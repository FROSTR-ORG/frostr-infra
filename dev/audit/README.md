# `dev/audit/`

Point-in-time audit artifacts for the FROSTR workspace, generated 2026-04-22.

This pass audited the parent workspace plus every active submodule under
`repos/` except `igloo-paper` (reference-only, uninitialized) and
`igloo-chrome` (a detailed audit exists from 2026-04-02; see
`../reports/igloo-chrome-audit-2026-04-02.md`).

## Start Here

- **[workspace-audit-synthesis-2026-04-22.md](./workspace-audit-synthesis-2026-04-22.md)** — cross-cutting executive summary, theme map, per-repo severity rollup, and prioritized remediation buckets. Read this first.

## Per-Repo Reports

Each report follows the `dev/reports/` convention: framing paragraph, numbered
findings with `High` / `Medium` / `Low` severity, verified `file:line`
references, and a per-finding `Streamline:` direction (not a fix).

| Repo | Report | H / M / L |
|---|---|---|
| `bifrost-rs` (Rust signer/runtime core) | [bifrost-rs-audit-2026-04-22.md](./bifrost-rs-audit-2026-04-22.md) | 5 / 6 / 4 |
| `igloo-shell` (CLI operator host) | [igloo-shell-audit-2026-04-22.md](./igloo-shell-audit-2026-04-22.md) | 5 / 6 / 3 |
| `frostr-infra` (parent workspace) | [frostr-infra-audit-2026-04-22.md](./frostr-infra-audit-2026-04-22.md) | 4 / 7 / 3 |
| `igloo-shared` (TS adapter / runtime bridge) | [igloo-shared-audit-2026-04-22.md](./igloo-shared-audit-2026-04-22.md) | 5 / 5 / 4 |
| `igloo-home` (Tauri desktop host) | [igloo-home-audit-2026-04-22.md](./igloo-home-audit-2026-04-22.md) | 4 / 6 / 3 |
| `igloo-pwa` (browser PWA host) | [igloo-pwa-audit-2026-04-22.md](./igloo-pwa-audit-2026-04-22.md) | 3 / 6 / 3 |
| `igloo-ui` (shared React UI package) | [igloo-ui-audit-2026-04-22.md](./igloo-ui-audit-2026-04-22.md) | 3 / 6 / 2 |
| | **Totals** | **29 / 42 / 22** |

## Audit Dimensions

Every report evaluates six axes:

1. **Security** — secret-material handling, crypto correctness, input validation, dependency exposure, `unsafe` / panic discipline.
2. **Code quality** — error taxonomy, modularity, idioms, abstraction discipline.
3. **Readability** — naming, file sizes, complexity, dead code.
4. **Technical debt** — TODOs / FIXMEs, duplication, half-finished work, legacy shims.
5. **Test coverage** — presence, shape, adversarial-vs-happy-path coverage, gap analysis.
6. **Documentation** — README accuracy, in-code docs, doc-vs-code drift against `docs/`.

## What Was Not Audited

- `igloo-paper` — reference-only submodule, uninitialized in the working tree.
- `igloo-chrome` — prior audit at `dev/reports/igloo-chrome-audit-2026-04-02.md` still stands. A re-audit is recommended (tracked in the synthesis under Bucket J6).
- Live `cargo audit` / `npm audit` against registries — flagged as a recommendation in individual reports but not executed.
- Fuzzing / property testing at runtime — several findings call for adding it; none was performed during the audit.
- Production deployment surfaces (headers, package publication chain, release signing) — out of scope.

## Working With These Reports

- Findings cite absolute paths under `/home/cscott/Repos/frostr/frostr-infra/…`. All line numbers were verified at write time (2026-04-22) but will drift as the codebase changes.
- Cross-repo concerns are flagged per finding with a `Cross-repo note:` line; the synthesis aggregates them under the Theme Map.
- Reports contain findings only. Fixes are not written and decisions are not taken here — that belongs in follow-up plans under `dev/plans/`.
