<!--
Per-target audit report template. Copy to findings/<target>-audit-<date>.md and
fill in. Carries the proven 2026-04-22 shape (framing → numbered findings with
Files / Why this matters / Smells / Streamline) and adds a `Rule:` field tying
each finding to a domain rule in ../rules/. Delete this comment when filling.
-->

# `<target>` audit

Date: YYYY-MM-DD

Scope: `<absolute path>` (<what was and wasn't covered>)

<1–2 paragraph framing: what this target is, the dominant patterns you saw, and
the overall shape of its debt. Set context before the numbered findings.>

## Findings

### 1. High: <one-line symptom>

Rule: `<DOMAIN-NN>` (<domain name>)

Files:
- `<repo>/<path>:<line-range>`
- `<repo>/<path>:<line-range>`

Why this matters:
- <factual context>
- <impact / risk if left>

Smells:
- <anti-pattern signal>
- <anti-pattern signal>

Streamline:
- <a direction, not a fix — where the change should head>

Cross-repo note: <only if this touches other targets; else omit. Mirror it into NOTES.md.>

### 2. Medium: <one-line symptom>

Rule: `<DOMAIN-NN>`

Files:
- `<repo>/<path>:<line-range>`

Why this matters:
- <...>

Smells:
- <...>

Streamline:
- <...>

<!-- Repeat per finding, ordered High → Medium → Low. -->

## Summary

| Severity | Count |
|---|---|
| High | <n> |
| Medium | <n> |
| Low | <n> |
| **Total** | **<n>** |
