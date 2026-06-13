# Code quality & practices

Judges the craft inside a function: how errors are modeled, how failure is
handled, whether types are honest, and whether logic is expressed once. This is
the domain of small recurring habits that compound into fragility.

## What good looks like

- Errors are typed and carry structure; callers can branch on them.
- Failures are handled where they can be, not papered over with `unwrap`.
- Types describe reality; `as`/`any` escapes are rare and justified.
- One expression of each rule; constants are named.

## Rules

### CQ-01 — Stringly-typed errors
- **Severity:** Medium
- **Look for:** `Result<T, String>`, `Result<T, Box<dyn Error>>` on a public surface, thrown bare strings, errors that exist only as log text.
- **Fails when:** callers can't distinguish error kinds without parsing a message.
- **Passes when:** errors are an enum / typed taxonomy the caller can match on.
- **Prompt:** "Can a caller tell *why* this failed without reading the message string?"

### CQ-02 — Panic / unwrap / expect discipline
- **Severity:** High
- **Look for:** `.unwrap()`, `.expect()`, `panic!`, `unreachable!`, non-null assertions, especially on locks (`.lock().unwrap()`), parsed input, or anything reachable from a request.
- **Fails when:** a recoverable or input-driven path can panic (a poisoned mutex crashing the backend; `verifying_key_to_group_pk` panicking instead of returning `Err`).
- **Passes when:** panics are confined to genuine invariant violations and documented as such.
- **Prompt:** "Who triggers this panic — an impossible state, or a hostile input?"

### CQ-03 — Type escapes
- **Severity:** Medium
- **Look for:** `as` casts between runtime shapes, `any`, `as any`, `@ts-ignore`, `unsafe`, `as unknown as`.
- **Fails when:** an escape hatch hides a real shape mismatch or sidesteps the type system rather than expressing an unavoidable boundary.
- **Passes when:** the cast is at a true FFI/serialization boundary and is checked or documented.
- **Prompt:** "Is this cast describing a real boundary, or lying to the compiler to make an error go away?"

### CQ-04 — Duplicated logic
- **Severity:** Medium
- **Look for:** copy-pasted blocks, parallel implementations of one transform, the same validation inlined in several call sites.
- **Fails when:** one behavior lives in many places and they can drift.
- **Passes when:** shared logic is factored to one home (without over-abstracting unrelated callers into a false shared shape).
- **Prompt:** "If the rule behind this changes, how many edits — and would they stay in sync?"

### CQ-05 — Premature or leaky abstraction
- **Severity:** Low
- **Look for:** one-implementation interfaces, config-driven mini-languages (a 360-line stamp engine with its own grammar), indirection that adds hops without removing duplication.
- **Fails when:** abstraction costs more comprehension than the duplication it removes.
- **Passes when:** abstractions earn their indirection with real reuse or a clear seam.
- **Prompt:** "Does this abstraction pay for itself, or is it indirection for its own sake?"

### CQ-06 — Magic values
- **Severity:** Low
- **Look for:** unexplained numeric literals (timeouts, sizes, KDF params, polling intervals), repeated string keys, inline byte lengths.
- **Fails when:** a value's meaning or origin can't be recovered from the code.
- **Passes when:** values are named constants with a comment on the why, or recorded alongside the data they govern (e.g. KDF params stored with the record).
- **Prompt:** "Why *this* number — and where is that written down?"

### CQ-07 — Mutation-heavy / re-render-prone state
- **Severity:** Medium
- **Look for:** large mutable shared state, context whose whole value is a memo dependency (re-renders on every change), polling where subscription fits.
- **Fails when:** state shape forces wasteful work or makes change-tracking impossible to reason about.
- **Passes when:** state is scoped, derivations are memoized at the right grain, updates are subscribed not polled.
- **Prompt:** "What re-runs when this changes — and is that the minimum it could be?"

## Review prompts

- Could a caller handle this failure if they wanted to, or is the information gone?
- Where does this code lie to the type system, and why?
- Is each rule here expressed exactly once?
