# Igloo PWA Welcome Visual Pilot

## Target

- Paper reference: `repos/igloo-paper/screens/welcome/1-welcome/screenshot.png`
- Runtime target: `repos/igloo-pwa` landing state with no stored profiles
- Viewport: `1440 x 1080`
- Captures:
  - Before: `.tmp/igloo-welcome-visual-pilot/igloo-pwa-welcome-1-current.png`
  - After: `.tmp/igloo-welcome-visual-pilot/igloo-pwa-welcome-1-after.png`
  - Iteration 2: `.tmp/igloo-welcome-visual-pilot/igloo-pwa-welcome-1-iteration-2.png`

## Loop Result

The screenshot loop works. Playwright can capture the live PWA at the Paper artboard size, and the side-by-side comparison makes the visual deltas concrete enough to drive small patches.

The first patch moved the no-profile PWA landing screen from the generic multi-card landing layout to a Paper-style first-launch Welcome screen:

- Public `AppHeader` spans the Paper width instead of the old constrained content width.
- No-profile state renders a centered `Igloo Web` hero.
- Primary action surface is one compact `New Keyset` panel with secondary `Import Device Profile` and `Onboard` actions.
- Footer icon row is present.
- Returning-profile states are intentionally unchanged for this pilot.

## Remaining Deltas

- Footer has four icons, but the fourth icon is representative rather than the exact Paper glyph.
- Secondary action buttons are darker and less blue than the Paper reference.
- Background gradient needs a closer stop/color match.

## Iteration 2 Notes

The second pass corrected the largest measurable drift:

- `PageLayout` now exposes a `surface="welcome"` mode instead of relying on a PWA-only CSS class that was purged from `igloo-ui/dist/styles.css`.
- Header frame coordinates now match the Paper export: `x=220`, `y=20`, `w=1000`, `h=80`.
- Main entry region starts at `y=120` with a `960px` height.
- Welcome stack uses a flex-centered column with the Paper export's `48px` hero-to-panel gap.
- The `Igloo Web` title uses the intended Share Tech Mono token.
- Footer now renders four icons.

## Verification

Commands run:

```bash
npm --prefix repos/igloo-ui test
npm --prefix repos/igloo-ui run build
npm --prefix repos/igloo-pwa run build:app
npm --prefix test exec -- playwright screenshot --browser chromium --viewport-size=1440,1080 http://localhost:1430/ .tmp/igloo-welcome-visual-pilot/igloo-pwa-welcome-1-current.png
npm --prefix test exec -- playwright screenshot --browser chromium --viewport-size=1440,1080 http://localhost:1430/ .tmp/igloo-welcome-visual-pilot/igloo-pwa-welcome-1-after.png
npm --prefix test exec -- playwright screenshot --browser chromium --viewport-size=1440,1080 http://localhost:1430/ .tmp/igloo-welcome-visual-pilot/igloo-pwa-welcome-1-iteration-2.png
```

Results:

- `igloo-ui` tests passed: 11 files, 27 tests.
- `igloo-ui` build passed.
- `igloo-pwa` build passed.
- Both PWA screenshots captured at `1440 x 1080`.

## Recommendation

Keep this loop and make the next iteration purely measurement-driven for `Welcome — 1. Welcome` before moving to returning-profile variants.
