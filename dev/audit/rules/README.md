# Audit rules

The criteria an audit pass judges against, organized into eight **domains**. Each
domain file is a flat list of **rules**; each rule names a concrete smell, says
when it fails and passes, and gives a prompt that surfaces it. Rules are the
shared definition of "good" so every pass starts from the same bar instead of
re-deriving it.

These are criteria, not law. A rule can be waived for a given file with a written
reason in the finding — but the waiver has to be explicit.

## Domains

| # | Domain | Prefix | Judges |
|---|---|---|---|
| 01 | [Legacy & deprecation](./01-legacy-deprecation.md) | `LEG-` | compat shims, dead code, version-suffixed files, retired APIs still wired in |
| 02 | [Architecture & boundaries](./02-architecture-boundaries.md) | `ARC-` | god files, mixed responsibilities, layering / thin-host drift, module-boundary leaks |
| 03 | [Code quality & practices](./03-code-quality-practices.md) | `CQ-` | error taxonomy, panic discipline, type escapes, duplication, magic values |
| 04 | [Readability & searchability](./04-readability-searchability.md) | `RS-` | naming, function size, nesting, grep-ability, discoverable entry points |
| 05 | [Aesthetics & formatting](./05-aesthetics-formatting.md) | `AES-` | vertical rhythm, density, alignment, comment shape, formatter enforcement |
| 06 | [Documentation](./06-documentation.md) | `DOC-` | rustdoc/JSDoc on exports, README accuracy, doc-vs-code drift, stale comments |
| 07 | [Testing](./07-testing.md) | `TST-` | core-journey coverage, adversarial vs happy-path, KAT/property tests, test shape |
| 08 | [Security](./08-security.md) | `SEC-` | secret lifecycle, crypto correctness, input/envelope validation, IPC auth, file perms |

## Rule format

Every rule reads the same way:

```markdown
### LEG-01 — One-line rule title
- **Severity:** High | Medium | Low
- **Look for:** concrete signals, grep patterns, or metrics a reviewer scans for
- **Fails when:** the condition that makes it a finding
- **Passes when:** the healthy state
- **Prompt:** a question that surfaces the issue when read against a file
```

Rule IDs (`LEG-01`, `ARC-02`, …) are **stable and greppable**. A finding cites
its rule via the `Rule:` field in the report template
([`../templates/repo-report.md`](../templates/repo-report.md)); that field is the
link between a rule and the evidence for it.

## Severity rubric

Severity is the rule's **default weight**; a specific instance can deviate (note
why in the finding).

- **High** — correctness, security, or data-integrity risk; or debt that actively
  blocks safe change (a 4k-line god file every change must route through).
- **Medium** — real friction or latent risk; should be fixed but not on fire.
- **Low** — polish, consistency, ergonomics; safe to batch.

A pass produces **findings only**. Fixes are not written and decisions are not
taken in `dev/audit/`; confirmed work graduates to
[`../../BACKLOG.md`](../../BACKLOG.md) (see [`../README.md`](../README.md)).

## Relationship to `dev/policies/`

[`../../policies/`](../../policies/) is contributor-facing review guidance for a
single change in flight. These rules are the audit pass's lens across the whole
tree. They overlap on purpose — `02-architecture-boundaries.md` reuses the drift
signals in [`../../policies/architecture-guidance.md`](../../policies/architecture-guidance.md)
rather than restating them — but the policies answer "should I merge this PR?"
while the rules answer "where is the debt across everything we own?"
