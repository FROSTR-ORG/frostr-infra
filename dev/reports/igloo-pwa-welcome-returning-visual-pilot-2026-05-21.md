# Igloo PWA Welcome Returning Visual Pilot

## Target

- Paper reference: `repos/igloo-paper/screens/welcome/1b-returning/screenshot.png`
- Runtime target: `repos/igloo-pwa` landing state with one stored profile
- Viewport: `1440 x 1080`
- Captures:
  - Before: `.tmp/igloo-welcome-returning-visual-pilot/igloo-pwa-welcome-1b-current.png`
  - After: `.tmp/igloo-welcome-returning-visual-pilot/igloo-pwa-welcome-1b-after.png`

## Loop Result

The returning-profile screen now uses the same Paper-style public welcome shell as `Welcome — 1. Welcome`.

The patch replaces the generic one-profile landing composition with a focused returning-user surface:

- `Igloo Web` hero remains centered.
- Hero subtitle changes to `Welcome back.`
- The stored profile renders as a compact lock row.
- Primary profile actions are `Unlock` and `Rotate`.
- Secondary actions are `New Keyset`, `Import Device Profile`, and `Onboard`.

Returning multi-profile and many-profile states remain intentionally out of scope for this loop.

## Remaining Deltas

- Exact profile key truncation should be driven by real npub formatting rather than seeded demo text.
- Unlock/Rotate button text and border colors still need exact Paper color tuning.
- The fourth footer icon remains representative rather than the exact Paper glyph.
- Multi-profile layout still uses the previous generic landing composition until the next iteration.

## Verification

Commands run:

```bash
npm --prefix repos/igloo-ui test -- test/CreateFlow.test.tsx
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run build:app
```

Screenshot capture used Playwright with a seeded `igloo-pwa.state.v1` containing one stored profile.
