# Documentation

Judges whether the code explains itself to someone who didn't write it: doc
comments on the surfaces people call, READMEs that match reality, and the absence
of drift between code and the canonical specs in
[`../../../docs/`](../../../docs/).

## What good looks like

- Exported functions/types carry a doc comment saying what and why.
- READMEs describe what the code actually does today.
- Code behavior matches the shared specs; neither silently leads the other.
- Comments explain intent and trade-offs, not the obvious mechanics.

## Rules

### DOC-01 — Undocumented public surface
- **Severity:** Medium
- **Look for:** exported functions/types/commands with no rustdoc (`///`) or JSDoc; a runtime API module with zero doc comments on its exports.
- **Fails when:** a caller must read the implementation to learn how to use a public surface.
- **Passes when:** exported surfaces document purpose, key params, failure modes, and any secret-handling contract.
- **Prompt:** "Could someone call this correctly from the doc comment alone?"

### DOC-02 — README drift
- **Severity:** Medium
- **Look for:** README/`AGENTS.md`/`CLAUDE.md` describing commands, surfaces, or services that no longer exist or behave differently (retired services in `.env.example`, stale make targets, a "render-only" lane described as behavioral).
- **Fails when:** the doc would mislead someone following it literally.
- **Passes when:** docs match current behavior; commands run as written.
- **Prompt:** "If I did exactly what this README says, would it work?"

### DOC-03 — Code-vs-spec drift
- **Severity:** High
- **Look for:** behavior in code that contradicts `docs/` (protocol, recovery, rotation, onboarding, wire specs); a protocol decision implemented only in code with no spec, or a spec describing behavior the code dropped.
- **Fails when:** code and the canonical manual disagree on system behavior.
- **Passes when:** they agree, or the divergence is flagged with which one leads.
- **Prompt:** "Does the code do what `docs/` says — and if not, which one is wrong?"

### DOC-04 — Missing rationale for non-obvious choices
- **Severity:** Low
- **Look for:** surprising constants, security-relevant decisions, deliberate deviations, workarounds — all with no "why" comment.
- **Fails when:** a future reader would likely "fix" something that's deliberate, or can't tell intent from accident.
- **Passes when:** non-obvious choices carry a short why (and link an ADR under [`../../adrs/`](../../adrs/) when there is one).
- **Prompt:** "Would a well-meaning contributor break this because the reason isn't written down?"

### DOC-05 — Stale or misleading comments
- **Severity:** Medium
- **Look for:** comments describing code that has since changed, TODOs referencing closed work, doc comments whose signature no longer matches.
- **Fails when:** a comment actively lies about what the code does.
- **Passes when:** comments track the code; stale ones are removed in the same change.
- **Prompt:** "Does this comment still describe what's directly below it?"

### DOC-06 — Changelog / version hygiene
- **Severity:** Low
- **Look for:** a perpetual single `[Unreleased]` block, package still at `0.0.0`, no record of what shipped when.
- **Fails when:** there's no usable history of what changed across versions.
- **Passes when:** changes are logged against versions in a way a consumer can follow.
- **Prompt:** "Could a consumer tell what changed between two versions of this package?"

## Review prompts

- What would a new contributor have to read the source to learn that a doc should tell them?
- Where does a doc promise something the code no longer does?
- Is the *why* written down anywhere for the non-obvious parts?
