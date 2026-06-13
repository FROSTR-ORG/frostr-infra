# Readability & searchability

Judges how fast a stranger can find the right code and understand it once found.
Two halves: **readability** (can I follow this function?) and **searchability**
(can I `grep` my way to it, and is the name I'd guess the name that's there?).

## What good looks like

- Names say what the thing is and are consistent across the codebase.
- Functions are short enough to hold in your head; nesting is shallow.
- Identifiers are distinctive enough to grep without 200 false hits.
- Entry points are obvious; you can find "where does X start" in one search.

## Rules

### RS-01 — Unclear or inconsistent naming
- **Severity:** Medium
- **Look for:** `data`, `info`, `tmp`, `obj`, `handle2`, `doStuff`; the same concept under different names across files (is it a `peer`, a `node`, a `member`?); abbreviations that aren't shared vocabulary.
- **Fails when:** a name misleads, or one concept has several names across the tree.
- **Passes when:** names are specific and one term is used consistently for one concept.
- **Prompt:** "If I only read this name, would I guess what it holds — and is it called the same thing everywhere?"

### RS-02 — Over-long functions
- **Severity:** Medium
- **Look for:** functions past ~60 lines, or doing setup + work + teardown + error handling inline with no extraction.
- **Fails when:** you must scroll and hold many locals to understand one function.
- **Passes when:** functions are scoped to one task; sub-steps are named via extraction.
- **Prompt:** "Can I see the whole function without scrolling, and state what it does in one sentence?"

### RS-03 — Deep nesting / high branching
- **Severity:** Low
- **Look for:** 4+ levels of indentation, nested ternaries, arrow-shaped code, conditionals that could be early returns.
- **Fails when:** control flow is hard to trace through the indentation.
- **Passes when:** guard clauses and early returns flatten the happy path.
- **Prompt:** "Where's the happy path — and how many branches do I trace to find it?"

### RS-04 — Poor grep-ability
- **Severity:** Medium
- **Look for:** identifiers assembled at runtime (string concatenation into keys/events so the literal never appears in source), generic names that collide across the tree, event/command names built from fragments.
- **Fails when:** you can't find a definition or all uses by searching the literal a user/log would show.
- **Passes when:** the searchable string exists verbatim in source.
- **Prompt:** "If I saw this name in a log, could I `grep` it and land on the definition?"

### RS-05 — Hidden entry points
- **Severity:** Low
- **Look for:** the "where does this flow start" being buried; barrel re-exports that obscure the real definition; indirection chains with no obvious top.
- **Fails when:** finding the origin of a behavior takes several hops with no signpost.
- **Passes when:** entry points are named and discoverable; re-exports point somewhere obvious.
- **Prompt:** "Starting cold, how many jumps to find where this behavior begins?"

### RS-06 — Inconsistent terminology vs the domain
- **Severity:** Low
- **Look for:** code terms that don't match the canonical names in [`../../../docs/`](../../../docs/) (protocol/architecture vocabulary), UI strings inventing new words for established concepts.
- **Fails when:** code and the system manual use different words for the same thing.
- **Passes when:** code reuses the domain's established vocabulary.
- **Prompt:** "Does this match what `docs/` calls it?"

## Review prompts

- Could a new contributor find this code from a symptom, using only search?
- Do the names here let me predict behavior, or do I have to read the body?
- Is one idea named one way across the whole tree?
