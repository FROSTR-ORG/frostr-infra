# Bucket H — Shared UI Package Boundary (Hard-Cut Plan)

Status: draft, pending user approval
Related: ships in the same second coordinated release as Bucket G (structural refactor + UI hygiene together). No operator migration.

## Context

The 2026-04-22 `igloo-ui` audit found three High-severity issues:

1. **Host-specific tokens bleed into shared CSS.** `HostShell` and friends
   render class names like `igloo-pwa-entry-tile`, `igloo-pwa-entry-head`,
   `igloo-pwa-entry-copy`, `igloo-pwa-entry-kicker`, `igloo-pwa-entry-icon`,
   and the compiled `styles.css` ships matching `@layer components` rules.
   The "shared" library publishes a product-specific visual idiom.
2. **Secret material rendered as plain DOM text.** `RecoveryWorkspace`
   renders the recovered `nsec` and hex signing key as readonly
   `<Textarea>` values. `CreateImportPanel` renders the regenerated
   `nsec`, full group package JSON, and every share package JSON as
   plain text. `QrPayloadModal` dumps the entire onboarding payload in a
   `<pre>`. None have a reveal gate, masking, auto-clear, or redaction
   seam.
3. **`LogEntryComponent` walks arbitrary internals.** The JSON fallback
   reads `(log.data as object)?.constructor?.name` and `Object.keys(...)`,
   with no length cap (only a CSS `max-h-[500px]` clip on the `<pre>`,
   not a DOM-level bound). Any runtime diagnostic blob can bleed internal
   object structure into the UI.

Plus seven Medium / Low findings on dialog/accessibility primitives
(`Modal` + `ConfirmModal` missing `role="dialog"`, duplicate Escape
listeners, no focus trap), a 259-line `peer-list.tsx` mixing layout +
policy + ping state + nonce visualization, click-only affordances with
no keyboard path, a runtime Google Fonts `@import` in the shipped
stylesheet, an unscoped `export *` barrel across 38 modules, and a
thin test suite (6 of 13 flows covered; 22 primitive files have zero
direct tests; no jest-axe).

Bucket H closes all three High findings, the four accessibility-
adjacent Medium findings, the CSS-boundary / barrel findings, and the
test-coverage gap. The structural `peer-list.tsx` split and the
`CreateFlow` / `OperatorPermissionsPanel` parameter-heavy components
are out of scope — flag for a later UI-modularization bucket.

No operator-facing impact. Alpha; ships with Bucket G in the second
coordinated release. Hard-cut throughout — every rename / move lands
atomically with its consumer migration in the same PR. No transitional
shim files, no re-export aliases preserved for compat. Old files are
deleted when replacements ship.

## Scope

**In:**
- H.1 — Rename `igloo-pwa-entry-*` CSS tokens to neutral
  `igloo-entry-*`. Adjust consumers. Remove the product-prefix from the
  shared stylesheet.
- H.2 — Introduce `SensitiveTextarea` / `SensitiveField` primitives.
  Default `nsec`, hex signing keys, share package JSON, and onboarding
  payload renders to the sensitive variant. Reveal requires an explicit
  user action; auto-mask on unmount.
- H.3 — Remove the `@import url(...)` for Google Fonts from
  `src/styles.css`. Vendor the font (Share Tech Mono) into the package,
  OR leave font loading to the host. Decision: vendor — one-time build
  cost, predictable offline behavior, no runtime network request from
  a shared library.
- H.4 — Replace the 38-line `export *` barrel in `src/index.ts` with
  explicit named exports. Curate the public surface.
- H.5 — Hoist `NonceBar`'s hardcoded `20` denominator into a
  `capacity` prop with a sane default.
- H.6 — Collapse `Modal` and `ConfirmModal` onto one primitive with
  `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, focus trap,
  return-focus on close, scroll lock, and a single Escape listener.
- H.7 — Harden `LogEntryComponent`: accept a `formatter?: (data) =>
  string` prop; bound the rendered string by both character count
  (~10 KB) and line count (~200 lines) with a "… (truncated)" marker;
  drop the `data.constructor.name` / `Object.keys` walk in favor of a
  safe fallback.
- H.8 — Accessibility affordances: `Backdrop` / `StepIndicator` /
  `HelpHint` primitives with keyboard parity and ARIA; audit every
  click-only dismiss affordance and add keyboard paths.
- H.9 — Test coverage: add `jest-axe` (or `vitest-axe`) to the vitest
  setup; unit tests for every primitive with nontrivial behavior
  (`PeerList`, `LogEntryComponent`, `EventLog`, `Modal`,
  `OperatorPermissionsPanel`, `HostShell`, `QrPayloadModal`,
  `Collapsible`); keyboard interaction tests (Enter/Space/Escape) on
  every clickable primitive.

**Out of scope for Bucket H:**
- `peer-list.tsx` split (audit finding 4) — meaningful structural
  refactor; defer.
- `CreateFlow.tsx` + `OperatorPermissionsPanel.tsx` prop-surface
  simplification (audit finding 10) — structural; defer.
- `CHANGELOG` / semver / `0.0.0` → real version (audit finding 11) —
  flag for a release-polish pass.
- Visual regression testing infrastructure — add if time permits in
  H.9; not a gating deliverable.

## Execution Order

Five PRs. Numbering continues from Bucket G (PR29–PR33).

| PR | Items | Depends on |
|---|---|---|
| PR34 | H.1 (token rename) + H.3 (vendor fonts) + H.4 (named exports) + H.5 (NonceBar prop) | none |
| PR35 | H.2 (SensitiveTextarea/SensitiveField + migrate callers) | PR34 (for named-export discipline) |
| PR36 | H.6 (dialog consolidation) + H.8 (accessibility primitives) | none |
| PR37 | H.7 (LogEntry hardening) | none |
| PR38 | H.9 (test coverage expansion: jest-axe + primitive unit tests) | PR34–PR37 |

PR34, PR36, PR37 are independent and can run in parallel. PR35
depends on PR34's named-export discipline so the new primitives are
added to the explicit export list cleanly. PR38 lands last so it
exercises the final post-bucket shape.

Rough touch: ~1,500 lines across `igloo-ui` + consumer migration
(~300 lines) in `igloo-home`, `igloo-pwa`, `igloo-chrome`.

Ships in the same coordinated release as Bucket G.

---

## H.1 — Rename `igloo-pwa-entry-*` → `igloo-entry-*`

### Targets

CSS tokens in TSX:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx:9,32,33,35,36` — `igloo-pwa-entry-tile`, `igloo-pwa-entry-head`, `igloo-pwa-entry-copy`, `igloo-pwa-entry-kicker`, `igloo-pwa-entry-icon`.

Rules in shipped stylesheet:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:506, 525, 537, 566, 978`.

### Change

Simple rename: `igloo-pwa-entry-*` → `igloo-entry-*`. Same semantics,
neutral name. Keep the `.is-primary` and `.is-secondary` suffixes.

No consumer TSX in the hosts references these class names directly
(audit confirmed `HostShell` emits them from inside `igloo-ui`). If any
host CSS has overriding rules targeting the old names, grep-audit:

```bash
rg 'igloo-pwa-entry-' repos/igloo-home/src repos/igloo-pwa/src repos/igloo-chrome/src
```

Zero expected. If nonzero, update those overrides to the new name in
the same PR.

### Testing

- `npm run test` in `igloo-ui` — existing visual / snapshot tests pass.
- `rg 'igloo-pwa-entry-' repos/` — zero matches.
- Manual: build PWA, Chrome extension, Home app. Visual inspection of
  the landing/entry tiles: primary vs secondary visually distinguished
  the same way as before.

---

## H.2 — `SensitiveTextarea` / `SensitiveField` primitives

### Design

Two new primitives in `igloo-ui/src/components/ui/`:

**`sensitive-field.tsx`** — for inline single-line values (nsec, hex
keys, short identifiers). Masked by default; `reveal()` toggles.

```tsx
export type SensitiveFieldProps = {
  value: string;
  label?: React.ReactNode;
  revealLabel?: string;       // default "Reveal"
  hideLabel?: string;          // default "Hide"
  copyable?: boolean;          // default true
  copyLabel?: string;          // default "Copy"
  autoMaskMs?: number;         // default 30_000; 0 disables auto-remask
  initiallyRevealed?: boolean; // default false
  maskPlaceholder?: string;    // default "••••••••••"
  onReveal?: () => void;       // observability hook
  onCopy?: () => void;
};

export function SensitiveField(props: SensitiveFieldProps): JSX.Element;
```

Behavior:
- Renders `maskPlaceholder` until the user clicks "Reveal".
- On reveal: shows the value; starts a timer; at `autoMaskMs`, remasks
  automatically.
- On unmount: schedules no further work; the component's React state
  goes away. For `SecretBytes`-backed values, host code should call
  `wipe()` separately in the unmount effect; the primitive cannot
  enforce this because it receives `string` (immutable) by contract.
- `copyable` shows a copy-to-clipboard button that works without
  revealing. On copy, the value is put on the clipboard for the
  revealed duration; document this timing behavior in the JSDoc.
- Emits `onReveal`/`onCopy` so hosts / observability can log the
  events.

**`sensitive-textarea.tsx`** — for multi-line values (share package
JSON, onboarding payloads, recovery bundles).

```tsx
export type SensitiveTextareaProps = {
  value: string;
  label?: React.ReactNode;
  rows?: number;
  revealLabel?: string;
  hideLabel?: string;
  copyable?: boolean;
  autoMaskMs?: number;
  initiallyRevealed?: boolean;
  placeholderLines?: number;  // default 6; number of "••••" lines to show when masked
  onReveal?: () => void;
  onCopy?: () => void;
};

export function SensitiveTextarea(props: SensitiveTextareaProps): JSX.Element;
```

Same behavior model as `SensitiveField`. When masked, renders
`placeholderLines` rows of blocks; when revealed, renders the actual
content inside a readonly `<textarea>` that inherits the existing
`Textarea` styling for visual consistency.

### Migration (inside `igloo-ui`)

Replace plain `<Textarea value={...} readOnly>` with `<SensitiveTextarea
value={...}>` in:

- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/RecoveryWorkspace.tsx:79,83` — recovered `nsec` and hex signing key.
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateImportPanel.tsx:298,303,320` — regenerated `nsec`, group package JSON, share package JSON.
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/QrPayloadModal.tsx:46` — the `<pre>` block with the onboarding payload.

`QrPayloadModal` specifically: the QR grid itself is the intended
reveal; the *text* representation below should be masked by default
with a reveal-to-copy path. The QR is already a visual reveal — if a
user doesn't intend to reveal the secret, they shouldn't see it in
text form too.

### Opt-in reveal overrides

Hosts that render these components inside an already-trusted reveal
flow (e.g. a dedicated "show recovery phrase" screen the user has
explicitly navigated to) can pass `initiallyRevealed={true}`. Greppable
with `rg 'initiallyRevealed' repos/` so reviewers can audit all
explicit-reveal sites.

### Accessibility

- Reveal button is a real `<button>`, not a styled `<div>`.
- Keyboard accessible: Enter/Space activates.
- `aria-label` on the reveal button: `"Reveal {label ?? 'sensitive value'}"`.
- `aria-expanded` on the reveal button tracks state.
- The masked placeholder has `aria-hidden="true"` so screen readers
  announce the label, not the bullet characters.
- When revealed, the value region has `role="region"` with
  `aria-label`.

### Testing

- Unit: masked by default; reveal button toggles; auto-remask fires
  at `autoMaskMs`; copy button copies without revealing; onReveal/onCopy
  fire.
- Axe: no violations on masked or revealed state.
- Keyboard: Enter on reveal button toggles; Escape on component while
  revealed returns to masked.
- Visual snapshot: masked state and revealed state.

---

## H.3 — Vendor Share Tech Mono; remove Google Fonts `@import`

### Current

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css:1`:

```css
@import url('https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap');
```

### Target

Download the Share Tech Mono font family (Open Font License) once,
commit the `.woff2` files under
`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/fonts/`, and
replace the `@import` with `@font-face` declarations pointing at the
vendored files:

```css
@font-face {
  font-family: 'Share Tech Mono';
  src: url('./fonts/ShareTechMono-Regular.woff2') format('woff2');
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
```

Vite / the build pipeline bundles the fonts with the CSS as part of
`dist/styles.css`. Hosts consume once; no runtime network fetch.

Also update `tailwind.config.js` line 7 to reference the local
family. Remove any `<link>` preconnect to `fonts.googleapis.com` in
host HTML (grep: `rg 'fonts.googleapis' repos/`).

### Rationale

- Shared library shouldn't trigger third-party network requests at
  runtime. Every host that renders an `igloo-ui` component pays this
  request today.
- Chrome extension CSP (Bucket E) is strict — Google Fonts loads would
  fail without an explicit exception.
- Offline-capable PWA and Tauri desktop app benefit from fully local
  fonts.
- OFL license allows redistribution.

### Testing

- `npm run build` in `igloo-ui` produces `dist/styles.css` with font
  faces pointing at local paths.
- PWA / Home / Chrome render with the correct font.
- Network panel in DevTools shows no request to `fonts.googleapis.com`.
- `rg 'fonts.googleapis' repos/` returns zero matches post-PR.

---

## H.4 — Named exports in `index.ts`

### Current

```ts
export * from './lib/utils';
export * from './lib/e2e-test-ids';
export * from './components/OnboardingInstructions';
// ... 35 more export * lines
```

Adding any new type or helper to any file is automatically public.

### Target

Replace with explicit named exports grouped by category:

```ts
// Utilities
export { cn /* ... */ } from './lib/utils';
export { E2E_TEST_IDS } from './lib/e2e-test-ids';

// Primitives
export { Alert } from './components/ui/alert';
export { AppHeader } from './components/ui/app-header';
export { Badge } from './components/ui/badge';
export { Button } from './components/ui/button';
export { Card } from './components/ui/card';
export { Collapsible } from './components/ui/collapsible';
export { ContentCard } from './components/ui/content-card';
export { EventLog } from './components/ui/event-log';
export { IconButton } from './components/ui/icon-button';
export { Input } from './components/ui/input';
export { InputWithValidation } from './components/ui/input-with-validation';
export { Label } from './components/ui/label';
export { LogEntryComponent } from './components/ui/log-entry';
export type { LogEntryData } from './components/ui/log-entry';
export { PageLayout } from './components/ui/page-layout';
export { PeerList /* ... */ } from './components/ui/peer-list';
export { RelayInput } from './components/ui/relay-input';
export { StatusIndicator } from './components/ui/status-indicator';
export { Tabs } from './components/ui/tabs';
export { Textarea } from './components/ui/textarea';
export { Tooltip } from './components/ui/tooltip';

// Post-H.2 primitives
export { SensitiveField } from './components/ui/sensitive-field';
export { SensitiveTextarea } from './components/ui/sensitive-textarea';

// Post-H.6 primitive (replaces Modal + ConfirmModal)
export { Dialog, ConfirmDialog } from './components/ui/dialog';

// Post-H.8 primitives
export { Backdrop } from './components/ui/backdrop';
export { StepIndicator } from './components/ui/step-indicator';
export { HelpHint } from './components/ui/help-hint';

// Flow composites
export { OnboardingInstructions } from './components/OnboardingInstructions';
export { CreateFlow } from './components/flows/CreateFlow';
export { CreateImportPanel } from './components/flows/CreateImportPanel';
export { HostShell } from './components/flows/HostShell';
export { DesktopAppShell } from './components/flows/DesktopAppShell';
export { ManagedProfilesPanel } from './components/flows/ManagedProfilesPanel';
export { OperatorDashboardTabs } from './components/flows/OperatorDashboardTabs';
export { OperatorPermissionsPanel } from './components/flows/OperatorPermissionsPanel';
export { OperatorSettingsPanel } from './components/flows/OperatorSettingsPanel';
export { OperatorSignerPanel } from './components/flows/OperatorSignerPanel';
export { ProfileConfirmationCard } from './components/flows/ProfileConfirmationCard';
export { QrPayloadModal } from './components/flows/QrPayloadModal';
export { RecoveryWorkspace } from './components/flows/RecoveryWorkspace';

// Types from flow surfaces
export type { /* explicit type list */ } from './components/flows/...';
```

At implementation time, go through each existing `export *` file and
enumerate what the consumers actually import. Anything not imported by
a host goes unexported; reduces the real public surface.

### Consumer migration

The three host repos that import from `igloo-ui`:
- `repos/igloo-pwa`
- `repos/igloo-chrome`
- `repos/igloo-home`

Build each to surface missing exports. Add any genuinely-used symbol
to the export list. Any symbol that was exported but unused becomes
internal (not listed in `index.ts`).

### Testing

- `rg '^export \*' repos/igloo-ui/src/index.ts` — zero matches.
- `tsc --noEmit` across the three host repos — passes.
- `npm --prefix repos/igloo-pwa run build` succeeds.
- `npm --prefix repos/igloo-chrome run build` succeeds.
- `npm --prefix repos/igloo-home run build` succeeds.

---

## H.5 — Hoist `NonceBar` denominator

### Current

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx` hardcodes `20` as the progress-bar denominator in `NonceBar`:

```ts
const percentage = Math.min(100, (value / 20) * 100);
```

The `20` is a runtime policy constant (max nonce pool size) living
inside a shared presentational primitive.

### Target

Accept `capacity` as a prop:

```tsx
export type NonceBarProps = {
  value: number;
  capacity?: number;  // default 20 for back-compat; hosts should pass the real value
  label?: React.ReactNode;
  className?: string;
};

export function NonceBar({ value, capacity = 20, label, className }: NonceBarProps): JSX.Element {
  const percentage = Math.min(100, (value / Math.max(capacity, 1)) * 100);
  // ... rest unchanged
}
```

Hosts pass `capacity={nonce_pool_max}` sourced from the bifrost-rs
config. `igloo-shared` (post-Bucket G) publishes a selector that
returns the configured capacity; hosts feed it to `NonceBar`.

Callers to migrate:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx:140,145` — the three inline `NonceBar` instances inside `PeerCard`. Each gets `capacity={...}`.

### Testing

- Unit: `NonceBar value=10 capacity=20` → 50%; `value=15 capacity=30`
  → 50%; `value=20 capacity=20` → 100%; `value=100 capacity=50` →
  clamped to 100%.
- Snapshot: visual unchanged for `capacity=20` default.

---

## H.6 — Dialog primitive consolidation

### Current

Two parallel primitives:
- `Modal` (`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/modal.tsx:13-39`) — backdrop + centered card, Escape listener, no `role="dialog"`, no focus trap.
- `ConfirmModal` (`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/confirm-modal.tsx:16-61`) — same backdrop + card shape with alert icon, separate Escape listener, duplicates dialog semantics.

Opening `Modal` from inside `ConfirmModal` (or vice versa) registers
two Escape listeners that both fire.

### Target

New primitive `Dialog` in `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/dialog.tsx`:

```tsx
export type DialogProps = {
  open: boolean;
  onClose: () => void;
  title?: React.ReactNode;
  description?: React.ReactNode;
  initialFocusRef?: React.RefObject<HTMLElement>;
  preventDismissOnBackdrop?: boolean;  // default false
  preventDismissOnEscape?: boolean;    // default false
  className?: string;
  children: React.ReactNode;
};

export function Dialog(props: DialogProps): JSX.Element | null;
```

Internals:
- Root `<div role="dialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={descId}>`.
- **Focus trap** via a lightweight `useFocusTrap(ref)` hook (no new
  dep; 30-line implementation using `focus-trap` patterns).
- **Focus on open**: `initialFocusRef?.current?.focus()` or the first
  tabbable child.
- **Return focus on close**: remember `document.activeElement` before
  open; restore it after close.
- **Scroll lock** on body while open (`document.body.style.overflow
  = 'hidden'` + restore).
- **One Escape listener** registered at the document level; nested
  dialogs use a stack so only the topmost handles Escape.
- **Backdrop click** is semantically a dismiss: `<button type="button"
  aria-label="Dismiss">`, keyboard-focusable, Enter/Space triggers
  `onClose`.

Plus a thin `ConfirmDialog` convenience wrapper:

```tsx
export type ConfirmDialogProps = {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
  variant?: 'danger' | 'warning';
};

export function ConfirmDialog(props: ConfirmDialogProps): JSX.Element {
  return (
    <Dialog open={props.open} onClose={props.onCancel} title={props.title} description={props.message}>
      {/* alert-icon + button row */}
    </Dialog>
  );
}
```

### Migration (atomic within PR36)

Rename every `Modal` caller → `Dialog`. Every `ConfirmModal` caller →
`ConfirmDialog`. In the same PR:

1. Create `dialog.tsx` with both exports.
2. **Delete** `modal.tsx` and `confirm-modal.tsx` entirely.
3. Update every call site across `igloo-ui/src/`, `igloo-pwa/src/`,
   `igloo-home/src/`, `igloo-chrome/src/` to use the new names.
4. Update `igloo-ui/src/index.ts` to export `Dialog` and `ConfirmDialog`
   (not `Modal` or `ConfirmModal`).

Grep-audit post-PR36:
- `rg "from ['\"].*(modal|confirm-modal)['\"]" repos/` — zero matches.
- `rg "\bModal\b|\bConfirmModal\b" repos/` — only internal type-predicate
  references inside `dialog.tsx` itself, if any; zero in consumer code.

### Testing

- Axe: no violations on open state.
- Keyboard: Tab cycles within the dialog; Shift+Tab cycles backward;
  focus never escapes to elements behind the backdrop.
- Focus restoration: open dialog, close, assert the previously-focused
  element has focus.
- Nested: open `Dialog` from inside `ConfirmDialog`; Escape closes only
  the top.
- Scroll lock: open dialog, assert `document.body.style.overflow` is
  `'hidden'`; close, assert it's restored.

---

## H.7 — `LogEntryComponent` hardening

### Current risks (confirmed by Read)

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/log-entry.tsx:31-59`:
- `JSON.stringify(log.data, null, 2)` is the happy path. No length cap.
  A 50 KB diagnostic blob renders as 50 KB of text in the DOM.
- Catch-fallback walks `(log.data as object)?.constructor?.name` and
  `Object.keys(log.data as object)`. If the host passed a raw bifrost-rs
  DeviceState (shouldn't, but could), internals leak.
- `max-h-[500px]` on the `<pre>` (line 105) is a CSS clip only —
  the full string is in the DOM, just scrollable.

### Target

Replace the inline formatter with:

```tsx
export type LogEntryProps = {
  log: LogEntryData;
  formatter?: (data: unknown) => string;
  maxChars?: number;       // default 8_192
  maxLines?: number;       // default 200
  truncationMarker?: string; // default "… (truncated)"
};

const DEFAULT_FORMATTER = (data: unknown): string => {
  try {
    return JSON.stringify(data, null, 2);
  } catch {
    // Safe fallback: just report the type, no introspection.
    if (Array.isArray(data)) return `[array, ${data.length} items]`;
    if (typeof data === 'object' && data !== null) return '[object]';
    return String(data);
  }
};

function boundString(raw: string, maxChars: number, maxLines: number, marker: string): string {
  const lines = raw.split('\n');
  let truncated = false;
  let bounded = lines;
  if (lines.length > maxLines) {
    bounded = lines.slice(0, maxLines);
    truncated = true;
  }
  let joined = bounded.join('\n');
  if (joined.length > maxChars) {
    joined = joined.slice(0, maxChars);
    truncated = true;
  }
  return truncated ? `${joined}\n${marker}` : joined;
}
```

Changes:
- No more `constructor.name` or `Object.keys` walks.
- DOM-level length bounds, not just CSS clip.
- `formatter` prop lets hosts provide a domain-specific safe formatter
  (redact known secret fields by shape, prettify specific event
  types).
- `maxChars` / `maxLines` props let hosts tune; defaults (8 KB / 200
  lines) are generous for legitimate logs, rejecting obvious DoS-shaped
  blobs.

### Integration with Bucket D redactor

Hosts that want their logs to pass through the allow-list redactor
(Bucket D) compose the formatter:

```tsx
const formatter = (data: unknown) => {
  const sanitized = sanitizeDetails('host', 'log_entry', data as Record<string, unknown>);
  return JSON.stringify(sanitized, null, 2);
};

<LogEntryComponent log={log} formatter={formatter} />
```

Document this composition pattern in the JSDoc.

### Testing

- Unit: oversized string (20 KB) → truncated to 8 KB + marker.
- Unit: 1,000-line input → truncated to 200 lines + marker.
- Unit: custom formatter receives `log.data` and renders its output
  instead of JSON.
- Unit: circular reference → safe fallback `[object]`, no throw.
- Snapshot: existing happy-path rendering unchanged for small data.

---

## H.8 — Accessibility affordances bundle

### New primitives

**`backdrop.tsx`** — the semantic "dismiss overlay" used by `Dialog`
and any future floating UI:

```tsx
export function Backdrop({ onDismiss }: { onDismiss: () => void }): JSX.Element {
  return (
    <button
      type="button"
      aria-label="Dismiss"
      className="absolute inset-0 bg-black/65 backdrop-blur-sm cursor-default"
      onClick={onDismiss}
    />
  );
}
```

- Real button, focusable, keyboard-triggerable.
- Replaces every `<div onClick={...}>` backdrop in the codebase.

**`step-indicator.tsx`** — for `StepProgress` UI that today renders
steps without `aria-current`:

```tsx
export type StepIndicatorProps = {
  steps: Array<{ id: string; label: string }>;
  currentStepId: string;
  ariaLabel?: string;  // default "Flow progress"
};

export function StepIndicator(props: StepIndicatorProps): JSX.Element {
  return (
    <ol role="list" aria-label={props.ariaLabel ?? 'Flow progress'}>
      {props.steps.map(step => (
        <li
          key={step.id}
          aria-current={step.id === props.currentStepId ? 'step' : undefined}
        >
          {step.label}
        </li>
      ))}
    </ol>
  );
}
```

**`help-hint.tsx`** — for `HelpCircle` tooltips that today use a
non-focusable `title` attribute:

```tsx
export type HelpHintProps = {
  content: React.ReactNode;
  ariaLabel: string;
  placement?: 'top' | 'bottom' | 'left' | 'right';
};

export function HelpHint(props: HelpHintProps): JSX.Element {
  // Button-wrapped trigger; keyboard-accessible Tooltip showing `content`.
}
```

Keyboard-focusable, announced by screen readers, tooltip opens on
focus or hover.

### Click-to-dismiss audit

Find every `<div onClick={...}>` in `repos/igloo-ui/src/components/` and
either:
- Upgrade to `<button>` with keyboard handlers, or
- Apply a `role` + `tabIndex` + `onKeyDown` combo if the semantic
  doesn't fit a button.

Expected sites: `modal.tsx:27`, `confirm-modal.tsx:38` (both replaced
by `Backdrop` in H.6), `HostShell.tsx:82`, `OperatorSignerPanel.tsx:112`.

### Testing

- Axe on every primitive.
- Keyboard: Tab to backdrop, Enter dismisses dialog.
- Screen reader (simulated via `@testing-library/dom` matchers):
  `aria-current="step"` present on the correct step.

---

## H.9 — Test coverage expansion

### Add `jest-axe` (vitest-axe)

Install:
```bash
npm --prefix repos/igloo-ui install --save-dev jest-axe @types/jest-axe
```

Extend `src/test/setup.ts` to include axe matchers:

```ts
import { expect } from 'vitest';
import { toHaveNoViolations } from 'jest-axe';
expect.extend(toHaveNoViolations);
```

Add `test/axe/*.test.tsx` files that render each exported primitive
with typical props and assert `await axe(container)` returns no
violations.

### New primitive unit tests

Expected new test files (covering what the audit flagged as untested):
- `test/ui/PeerList.test.tsx` — collapse/expand, ping state machine,
  nonce bar renders.
- `test/ui/LogEntry.test.tsx` — formatter, bounds, safe fallback (from
  H.7).
- `test/ui/EventLog.test.tsx` — scroll, filter, virtualization if any.
- `test/ui/Dialog.test.tsx` — focus trap, scroll lock, return focus,
  nested dialogs (from H.6).
- `test/ui/OperatorPermissionsPanel.test.tsx` — policy override cycle
  (`nextOverrideValue` state machine).
- `test/ui/HostShell.test.tsx` — entry tile rendering + primary/secondary variants.
- `test/ui/QrPayloadModal.test.tsx` — sensitive textarea default
  (after H.2).
- `test/ui/Collapsible.test.tsx` — keyboard open/close, aria-expanded.

### Keyboard interaction tests

For every click-dismissible surface (dialogs, dropdowns, collapsibles,
tabs):
- Enter / Space activates.
- Escape closes (for dialogs).
- Tab focus is correctly scoped.

### Testing the tests

- `npm --prefix repos/igloo-ui test` completes in reasonable time
  (~30s).
- Coverage: `npm --prefix repos/igloo-ui test -- --coverage` shows
  every primitive file has at least one test file importing it.
- Axe suite: zero violations across all exported primitives.

---

## Critical Files

Modify (`igloo-ui`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/styles.css` (rename tokens, remove `@import`, add `@font-face`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/fonts/ShareTechMono-Regular.woff2` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/fonts/LICENSE.txt` (NEW — OFL license text)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/tailwind.config.js` (font family name; no CDN)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/index.ts` (named exports)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/HostShell.tsx` (token rename)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/RecoveryWorkspace.tsx` (SensitiveTextarea)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/CreateImportPanel.tsx` (SensitiveTextarea)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/QrPayloadModal.tsx` (SensitiveTextarea)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/sensitive-field.tsx` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/sensitive-textarea.tsx` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/dialog.tsx` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/modal.tsx` (DELETE in PR36)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/confirm-modal.tsx` (DELETE in PR36)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/log-entry.tsx` (formatter prop + bounds)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/peer-list.tsx` (NonceBar capacity prop)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/backdrop.tsx` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/step-indicator.tsx` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/ui/help-hint.tsx` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/components/flows/OperatorSignerPanel.tsx` (HelpHint migration)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/lib/use-focus-trap.ts` (NEW)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/src/test/setup.ts` (axe matchers)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/package.json` (jest-axe devDep)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/test/axe/*.test.tsx` (NEW — axe suite)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui/test/ui/*.test.tsx` (NEW — primitive unit tests)

Modify (consumers — minimal, via SensitiveTextarea migration inside
igloo-ui):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/App.tsx` (if any call site passes `initiallyRevealed` to override the new default, add it explicitly with a comment citing the flow's trust context)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-home/src/App.tsx` (same)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/src/options.html` / equivalent (same)

Reuse (do not re-invent):
- `Textarea` (from `igloo-ui/src/components/ui/textarea.tsx`) — the
  new `SensitiveTextarea` wraps it, doesn't replace it.
- `Button` (ditto).
- Bucket D's `Secret<T>` type — the host captures the secret in
  `Secret<string>`, calls `.expose()` when rendering via
  `SensitiveField`. The primitive itself takes `string` because the
  reveal timing requires React state transitions.

## Verification

**PR34 (H.1 + H.3 + H.4 + H.5):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui
npm run build
npm run test
# Regressions:
rg 'igloo-pwa-entry-' repos/
rg '^export \*' src/index.ts
rg 'fonts.googleapis' repos/
```
All four greps zero.

**PR35 (H.2):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-ui
npm run test
# Visual: build PWA; navigate to recovery flow; confirm nsec is masked by default; click Reveal; see value; 30s later, auto-remasks.
npm --prefix ../igloo-pwa run test:e2e  # includes a sensitive-reveal regression test
```

**PR36 (H.6 + H.8):**
```bash
npm run test
# Keyboard: full manual keyboard walkthrough of Dialog + ConfirmDialog.
# Axe: new axe suite passes.
```

**PR37 (H.7):**
```bash
npm run test
# Manual: seed a 20 KB diagnostic into a host app's EventLog; confirm UI shows truncation marker.
```

**PR38 (H.9):**
```bash
npm run test -- --coverage
# Assert coverage: every file in src/components/ui/ has at least one test file importing it.
npm run test -- --run test/axe/
# Every primitive's axe test passes.
```

**Full-bucket verification (after PR38):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-release  # exercises UI across Chrome + PWA + Home E2E
```

## Cross-Repo Coordination

Ships in the second coordinated release alongside Bucket G. No
operator impact. No version bumps.

Host-side impact:
- `SensitiveTextarea` migration happens inside `igloo-ui` flows that
  hosts already consume. Hosts get the masked-by-default behavior for
  free unless they explicitly opt out with `initiallyRevealed={true}`.
- `Modal` / `ConfirmModal` renamed to `Dialog` / `ConfirmDialog`
  atomically in PR36. Every consumer call site is rewritten in the
  same PR — no `Modal`/`ConfirmModal` names remain after PR36 merges.
- Named exports in `index.ts` may surface missing-export errors in
  hosts that imported symbols the old `export *` leaked. Audit + fix
  in the same PR.

No bifrost-rs changes. No TS type changes in `igloo-shared`. Bucket H
is self-contained UI work.

## Out-of-Bucket Flags

- **`peer-list.tsx` split** (audit finding 4) — 259-line file mixing
  layout, policy, ping, nonce meter. Structural refactor; defer.
- **`CreateFlow.tsx` + `OperatorPermissionsPanel.tsx` prop-surface
  simplification** (audit finding 10) — introduce state + event-callback
  pattern to collapse 10+ prop contracts. Structural; defer.
- **CHANGELOG + version** (audit finding 11) — stamp a real semver.
  Part of a release-polish pass. Defer.
- **Visual regression testing** — add Chromatic / Percy / Playwright
  visual snapshots. Nice-to-have if H.9 time permits; not a gating
  deliverable.
- **Storybook** — `igloo-ui` would benefit from a Storybook for
  isolated component development. Defer.

## Summary

Five PRs, ~1,500 lines, in `igloo-ui` plus minimal consumer touch-ups.
Closes the three High-severity audit findings (host-prefixed class
tokens, secret-material plaintext rendering, `LogEntry` internals
walk) plus the accessibility gaps and the `export *` boundary issue.

- **Tokens**: `igloo-pwa-entry-*` → `igloo-entry-*`. Shared library no
  longer advertises a host-specific name.
- **`SensitiveField` / `SensitiveTextarea`**: masked by default,
  explicit Reveal required, auto-remask, keyboard + axe-clean. Every
  in-library render of `nsec` / hex keys / share package JSON /
  onboarding payload defaults to the sensitive variant.
- **Fonts**: Share Tech Mono vendored via `@font-face` on local
  `.woff2`. Shared library no longer triggers a runtime Google Fonts
  request.
- **Named exports**: `index.ts` enumerates the public API; `export *`
  gone. Adding a new export is a visible diff.
- **`NonceBar` capacity**: hardcoded `20` denominator promoted to a
  prop with `20` default. Hosts pass the configured max from
  bifrost-rs.
- **Dialog primitive**: `Modal` + `ConfirmModal` collapse onto one
  `Dialog` + `ConfirmDialog` with `role="dialog"`, `aria-modal`, focus
  trap, return-focus, scroll lock, single document-level Escape
  stack. Old names deleted atomically in PR36; every consumer call
  site renamed in the same PR.
- **`LogEntryComponent`**: `formatter` prop, DOM-level character /
  line bounds, safe fallback for unserializable values, no
  `constructor.name` or `Object.keys` walks.
- **Accessibility primitives**: `Backdrop`, `StepIndicator`,
  `HelpHint` — keyboard-accessible, ARIA-correct, axe-clean. Every
  click-only affordance migrated.
- **Test coverage**: `jest-axe` integrated; every primitive has at
  least one unit test; keyboard-interaction tests for every
  click-dismissible surface.

Ships in the second coordinated release with Bucket G.
