# Igloo UI Paper API And Mismatch Ledger

Date: 2026-05-20
Status: Review gate before public API changes

## Decisions Locked For Implementation

- Keep `repos/igloo-ui` and `repos/igloo-shared` as separate packages.
- Keep `repos/igloo-paper` reference-only. Do not import Paper JSX, screenshots, or repo paths into runtime packages or app builds.
- Treat `igloo-paper` as the visual and interaction reference.
- Treat existing functional behavior and `igloo-shared` runtime contracts as authoritative when Paper and implementation assumptions differ.
- Use explicit UI view models and adapter helpers instead of making `igloo-ui` a runtime package.
- Review every public API break listed here before changing exported types or component props.

## Package Boundary Ledger

| Surface | Current Owner | Target Owner | Hard-Cut Decision |
| --- | --- | --- | --- |
| React primitives and design tokens | `igloo-ui` | `igloo-ui` | Keep. Add Paper token bridge and semantic primitive variants. |
| Flow composition and reusable screens | `igloo-ui` | `igloo-ui` | Keep, but move to Paper-aligned view models. |
| Runtime/profile/package semantics | `igloo-shared` | `igloo-shared` | Keep. No React or CSS dependency. |
| Runtime-to-UI projection | Mixed in consumers and `igloo-ui` props | Adapter boundary | Add pure adapter helpers or documented mappings. Keep adapters free of Paper imports. |
| Paper export and screenshots | `igloo-paper` | `igloo-paper` | Keep reference-only. Sync selected tokens into `igloo-ui` as committed artifacts. |

## Proposed Public API Breaks

These are the breaks that need review before implementation.

| Area | Current API | Proposed API | Reason |
| --- | --- | --- | --- |
| `AppHeader` | Generic `title`, `subtitle`, `right`, `centered`, `logoSrc` props | Variant API: `mode: 'welcome' | 'task' | 'profile' | 'dashboard'`, with typed right-cluster props per mode | Paper defines distinct header states with fixed layout and content rules. |
| `AppHeader` styling | Gradient Share Tech Mono uppercase wordmark | Inter wordmark, optional subtitle, Paper pill container | Current header conflicts with Paper navigation reference. |
| Flow back navigation | Ad hoc `onBack` in `ContentCard` and flow shells | Dedicated `PageBackLink` component used as screen-level navigation | Paper explicitly separates task-flow header tags from page-level back links. |
| `StoredProfilesLandingCard` | `HostStoredProfileSummary` with `subtitle`, `statusLabel`, `loadLabel` | `StoredProfileCardModel` with label, short id, threshold label, public key display, updated/locked state, and action labels | Paper returning-profile cards carry richer profile context and fixed actions. |
| `CreateFlowGenerateCard` | Mixed `mode: 'new' | 'rotate'` in one create card | Separate create-keyset and rotate-keyset components or view models | Paper treats create, rotate, replacement, and recovery as separate flows. |
| `StepProgress` | String array plus active index | Paper stepper model with `id`, `label`, `state`, and optional description | Paper has active, pending, progress, success, and error step states. |
| `OperatorSignerPanel` | Large prop list for profile, runtime labels, peers, pending ops, logs | Single `SignerDashboardViewModel` plus callbacks | Current props duplicate runtime structure and make Paper dashboard parity hard. |
| `OperatorPermissionsPanel` | Parallel UI policy types: `OperatorPeerPermissionState`, `OperatorMethodPermissionOverride` | `PolicyDashboardViewModel` with runtime-backed policy rows and adapter mapping from `igloo-shared` | Current UI duplicates `RuntimePeerPermissionState` with renamed fields. |
| `OperatorSettingsPanel` | Duplicated `OperatorSignerSettings` type | UI settings model derived from `SignerSettings`, plus primitive field rows | Avoid type drift from `igloo-shared` signer settings. |
| `PeerList` | `PeerPolicy` combines policy booleans, liveness, nonce counts, and UI status | `PeerReadinessRowModel` and `PeerPolicyRowModel` split by display purpose | Paper separates peer pool/readiness visuals from policy matrix displays. |
| `EventLog` and `LogEntry` | Custom log levels and labels | Event log view model mapped from `ObservabilityEvent` plus display-only badge tone | Align diagnostics with shared observability while preserving Paper badge colors. |
| Primitive variants | `Button`, `Badge`, `Alert`, `StatusBadge` use Tailwind palette literals | Semantic variants backed by Paper CSS variables | Required to make Paper tokens real implementation inputs. |

## Paper Versus Functional Mismatches

| Topic | Paper Assumption | Functional/Shared Reality | Implementation Rule |
| --- | --- | --- | --- |
| Header state | Header right cluster is driven by high-level auth/flow state | Current `AppHeader` accepts arbitrary `right` content | Implement Paper header variants, but keep dashboard actions supplied by host callbacks. |
| Welcome returning cards | Cards show visual profile metadata and load/delete actions | Current model only has label/subtitle/status label | Add richer UI model; consumers can adapt from stored profile summaries. |
| Create and rotate | Paper separates create, rotate, replacement, recovery screens | Current `CreateFlowGenerateCard` overloads new and rotate modes | Split presentation surfaces. Keep runtime behavior from existing flows. |
| Threshold selection | Paper shows explicit selector controls and helper text | Current create flow uses plain number inputs | Add Paper selector primitive while preserving current validation limits. |
| Dashboard readiness | Paper shows signer readiness, relay state, peer pool ring, policy prompt rows | `igloo-shared` exposes `RuntimeReadiness`, `RuntimePeerStatus`, `RuntimePendingOperation`, and policy states | Functional state wins. Paper visuals map to shared runtime fields where available. Missing Paper-only states become display-only labels only after review. |
| Peer policy labels | Paper event/policy tags include broader badge taxonomy | Runtime policy methods are `ping`, `onboard`, `sign`, `ecdh`; shared package policy overrides may also include `echo` in package data | Runtime dashboard uses runtime methods first. Package-level `echo` is shown only where backed by shared data. |
| Event log | Paper uses visual badge categories such as signing, ECDH, ping, echo, policy | `ObservabilityEvent` uses level, component, domain, event, and sanitized details | Add deterministic mapping from observability fields to Paper badge tones. Do not invent runtime events. |
| Fonts | Paper uses Inter for UI/body and Share Tech Mono for values/headings/tags | Current `igloo-ui` body uses Share Tech Mono globally | Hard cut body to Inter. Use Share Tech Mono for wordmark-adjacent display, value data, and compact tags per Paper. |
| Token source | Foundations tokens are canonical but usage coverage contains more colors | Current `igloo-ui` hard-codes many Tailwind palette values | Promote only repeated canonical values to semantic tokens. Keep one-off usage coverage out of package API. |
| Visual acceptance | Paper has static HTML/screenshots | Current tests are behavior/unit oriented | Add Playwright showcase screens for deterministic screenshot review. |

## Adapter Boundary

Target adapter rules:

- `igloo-ui` components receive UI view models and callbacks only.
- `igloo-ui` does not call runtime helpers, storage helpers, or package encode/decode helpers.
- `igloo-shared` may expose pure projection helpers that return serializable data, but it does not import React or CSS.
- Host apps own lifecycle, storage, runtime wiring, and async actions.
- Adapter code must be deterministic and covered by unit tests where it lives.

Candidate shared-to-UI mappings:

- `BrowserRuntimeProfileSummary` to stored/active profile card models.
- `RuntimeStatusSummary` and `deriveReadinessExplanation()` to signer dashboard readiness models.
- `RuntimePeerStatus` plus `RuntimePeerPermissionState` to peer readiness and policy row models.
- `RuntimePendingOperation` to pending operation rows.
- `SignerSettings` to settings form fields.
- `ObservabilityEvent` to event log rows.

## Minimum First Milestone

The first implementation milestone is complete only when all of these are true:

- This ledger has been reviewed and any rejected API breaks are removed.
- Paper tokens are synced into `igloo-ui` as committed package artifacts.
- Core primitives render from semantic Paper-backed variants.
- `AppHeader` and `PageBackLink` follow the Paper navigation contract.
- A Playwright showcase covers at least:
  - welcome returning profiles
  - create keyset
  - signer dashboard
  - policies
- `npm test` and `npm run build` pass in `repos/igloo-ui`.

## Open Review Items

- Confirm whether `igloo-ui` should export adapter helpers, or whether host apps should own all adapters.
- Confirm which exported `igloo-ui` components remain public after the hard cut versus moving to internal modules.
- Confirm whether `echo` belongs in runtime dashboard policy/event UI or only in package/profile policy contexts.
- Confirm whether Paper-only visual states without runtime backing should be hidden, disabled, or represented as placeholder display rows in showcase only.
