# Aesthetics & formatting

Judges the visual texture of the code — the part that makes a file feel
effortless or exhausting to read before you've parsed a single token. Whitespace,
grouping, alignment, and density. This is the axis the maintainer called out
explicitly: *make code less dense and easier on the eyes.*

A note on tooling: no TypeScript repo here configures eslint/prettier and there's
no `rustfmt.toml`. So this domain judges **hand-tunable structure** a formatter
wouldn't touch — and treats the *absence of an enforced formatter* as its own
finding (`AES-06`) rather than re-litigating what auto-formatting would fix.

## What good looks like

- Blank lines group related statements into visual paragraphs.
- Lines aren't wall-to-wall; long expressions break at meaningful points.
- Related declarations align so differences pop and scanning is fast.
- Comments are formatted consistently and sit where they help.

## Rules

### AES-01 — No vertical rhythm
- **Severity:** Low
- **Look for:** long runs of statements with no blank lines; functions that are one undifferentiated block; setup, work, and return all jammed together.
- **Fails when:** a reader can't see the logical paragraphs at a glance.
- **Passes when:** blank lines separate phases (inputs → work → result) into scannable groups.
- **Prompt:** "Can I see the shape of this function squinting, before reading it?"

### AES-02 — High line density
- **Severity:** Low
- **Look for:** very long lines, several statements per line, deeply chained calls with no line breaks, dense object literals.
- **Fails when:** lines are so packed the eye can't track them and meaningful breaks are missing.
- **Passes when:** long expressions break at natural seams; one idea per line where it aids reading.
- **Prompt:** "Does each line carry one idea, or am I parsing three at once?"

### AES-03 — Unaligned related declarations
- **Severity:** Low
- **Look for:** clusters of related assignments, struct/object fields, match arms, or enum variants that could align but don't, so differences hide.
- **Fails when:** a column of related items is ragged enough that scanning for the odd-one-out is slow.
- **Passes when:** related lines align so the varying part stands out (without fighting the formatter or causing churn).
- **Prompt:** "If one of these lines were wrong, would the misalignment make it pop — or hide it?"

### AES-04 — Inconsistent comment shape
- **Severity:** Low
- **Look for:** mixed comment styles in one file, banner comments of varying widths, trailing comments that push code off-screen, ASCII-art dividers.
- **Fails when:** comment formatting is noisy or inconsistent enough to distract.
- **Passes when:** comments follow one style and sit above or beside the code they explain without crowding it.
- **Prompt:** "Do the comments calm the page down or add visual noise?"

### AES-05 — Disordered imports / declarations
- **Severity:** Low
- **Look for:** import blocks with no ordering, mixed external/internal/relative with no grouping, declarations scattered rather than grouped by kind.
- **Fails when:** the top of the file is a jumble that gives no sense of dependencies.
- **Passes when:** imports are grouped (std/external/internal) and ordered consistently across files.
- **Prompt:** "Can I read this file's dependencies as organized groups, or is it a pile?"

### AES-06 — No enforced formatter
- **Severity:** Medium
- **Look for:** absence of `prettier`/`eslint` config in a TS repo; absence of `rustfmt.toml` / no `cargo fmt --check` gate; formatting decided per-author.
- **Fails when:** style is unenforced, so aesthetic findings are doomed to recur and reviews argue formatting.
- **Passes when:** a formatter is configured and gated in CI, freeing this domain to focus on what the formatter can't do.
- **Prompt:** "Is consistency a tool's job here, or a thing humans re-argue every PR?"

## Review prompts

- Before reading a word, does this file look inviting or punishing?
- Where would two blank lines and an alignment pass do the most good?
- Which of these findings should just be a formatter's job?
