# Paper Onboard + Create Alignment Hard-Cut Plan

Date: 2026-05-23

## Summary

Hard-cut the next Paper alignment loop to the remaining Onboard recipient and
Create/distribution screens covered by the PWA visual harness. Welcome variants
remain out of scope for this pass.

## Implementation

- Add `onboard-handshake` to the PWA visual manifest and capture it in the
  onboard visual spec.
- Align Onboard recipient screens to Paper:
  - handshake timeline
  - failed package warning
  - completion group/device summary cards
- Align Create screens to Paper:
  - relay rows and peer permission defaults on create profile
  - Paper-style distribution step guide
  - single package password field that mirrors the hidden confirmation value
  - completion summary status
- Keep `igloo-paper` as reference material only; do not import it from runtime
  apps or packages.

## Tests

- `npm --prefix repos/igloo-ui test -- --run`
- `npm --prefix repos/igloo-ui run build`
- `npm --prefix test run test:e2e:igloo-pwa:visual`
- `npm --prefix test run test:guards:visual`
- `npm --prefix test run test:guards:workflows`

## Assumptions

- Distribution keeps existing confirmation validation internally, but the Paper
  UI presents one password input and mirrors it to `confirmPassword`.
- Peer permission rows are visual/default rows in this pass; editable peer
  policy behavior remains a later dashboard/settings task.
- Welcome alignment is the next loop after this hard cut.
