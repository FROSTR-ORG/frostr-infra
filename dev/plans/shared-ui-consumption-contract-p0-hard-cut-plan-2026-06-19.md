# Shared-UI Consumption Contract (P0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all three clients (`igloo-pwa`, `igloo-chrome`, `igloo-home`)
consume one shared UI identically — `igloo-ui` JS **and** CSS resolved from source,
styled through one shared Tailwind preset — and delete the prebuilt-`dist` path and
its Makefile band-aids outright.

**Architecture:** `igloo-ui` ships a Tailwind **preset** (the single source of
design tokens) and its **source** `styles.css`. Each client builds its own CSS with
the preset, scanning its own `src` + `igloo-ui/src`, and imports `igloo-ui`'s source
`styles.css`. The CSS→`dist` Vite alias, `igloo-ui`'s `dist` build, and the
`make igloo-ui-styles` / `igloo-ui-watch` targets are removed. After this, editing
any shared component **or** its styles is live via HMR in all three clients with no
intermediate build step.

**Tech Stack:** TypeScript, React 18, Vite 5 (pwa/home), esbuild (chrome MV3
`scripts/build.mjs`), Tailwind CSS 3.4, PostCSS + Autoprefixer.

## Global Constraints

- **Hard cut (ADR-014).** Each step deletes the old path in the same change. **No**
  deprecation aliases, compat shims, dual code paths, feature flags, or "legacy"
  fallbacks. Done means the old code is gone.
- **One canonical token source.** `igloo-ui/tailwind.preset.js` is the only place
  design tokens live. Client `tailwind.config` files carry **only** `presets`,
  `content`, and `darkMode` — no local `theme.extend` of colors/fonts.
- **No client left on the old path.** `igloo-ui`'s prebuilt `dist` is deleted only
  **after** all three clients consume source CSS (Task order enforces this). The
  end state lands as one coordinated set of submodule commits + a single parent
  pointer bump (Task 8).
- **Submodule workflow.** Commit **inside each submodule first**, then bump the
  parent pointer with `make bump-pointers` (non-recursive). Note submodule + hash +
  why in the pointer commit.
- **Verification is behavioral.** Each client task ends by rendering the client and
  confirming styled output (`make screenshot CLIENT=<c> STATE=dashboard-running`),
  not just a green typecheck.

---

## Current state (verified 2026-06-19)

- `repos/igloo-ui/package.json`: `main`/`module`/`types`/`exports` point at `dist`;
  `exports["./styles.css"] = "./dist/styles.css"`; `files: ["dist","README.md"]`;
  `build` script = esbuild (`scripts/build.mjs`) + `tsc --emitDeclarationOnly` +
  `tailwindcss -i ./src/styles.css -o ./dist/styles.css`. `tailwindcss@^3.4.17` is
  a devDep.
- `repos/igloo-ui/tailwind.config.js`: `darkMode: ['class']`,
  `content: ['./src/**/*.{ts,tsx}']`, `theme.extend = { fontFamily: {inter,
  sharetech}, colors: { igloo: {…} } }`, `plugins: []`.
- `repos/igloo-ui/src/styles.css`: `@import "./tokens/design-tokens.css";` +
  `@font-face` blocks with **relative** `url("./fonts/*.woff2")` + `@tailwind
  base/components/utilities` + `@layer` rules. Relative asset URLs must rebase when
  a client imports this from source.
- `repos/igloo-pwa/vite.resolve.ts` (shared by `vite.config.ts` + `vitest.config.ts`):
  aliases `igloo-shared`→src, `igloo-ui`→src, **`igloo-ui/styles.css`→`../igloo-ui/dist/styles.css`**.
  `src/main.tsx:4` `import 'igloo-ui/styles.css'`, `:7` `import './index.css'`.
  `src/index.css` = the `.igloo-dashboard-nav*` rules only. **No** tailwind/postcss
  devDeps.
- `repos/igloo-home/vite.config.ts`: inline aliases incl.
  **`igloo-ui/styles.css`→`../igloo-ui/dist/styles.css`**. `src/main.tsx:3`
  `import 'igloo-ui/styles.css'`, `:5` `import '@/index.css'`. `src/index.css` is
  empty. **No** tailwind/postcss devDeps.
- `repos/igloo-chrome`: builds its **own** Tailwind via `scripts/build.mjs` (inlines
  `node_modules/igloo-ui/dist/styles.css`, then runs PostCSS+Tailwind).
  `tailwind.config.ts` `content: ['./src/**/*.{ts,tsx}', '../igloo-ui/src/**/*.{ts,tsx}']`
  with a large shadcn-style `theme.extend`. `postcss.config.js` = tailwind +
  autoprefixer. `src/index.css` = `@import "igloo-ui/styles.css";`. devDeps:
  `tailwindcss@^3.4.14`, `postcss@^8.4.47` (autoprefixer referenced by config).
  **Verified:** chrome-local code uses the shadcn semantic classes
  (`bg-background`, `text-foreground`, `border-border`, …) **0 times** — that theme
  block is dead. Its live dependency is the raw `blue/gray/cyan/purple` palette.

---

## Canonical preset (the content Task 1 creates)

`repos/igloo-ui/tailwind.preset.js` — igloo-ui's current `theme.extend` (canonical)
plus the explicit `blue/gray/purple` palette values chrome/pwa inline-utility usage
relies on, so nothing shifts when chrome's local theme is deleted. `content` is
intentionally **absent** (each consumer sets its own):

```js
/** @type {import('tailwindcss').Config} */
// Single source of igloo design tokens. Consumed by every client's
// tailwind.config via `presets: [iglooPreset]`. Do NOT add `content` here —
// each consumer scans its own src + ../igloo-ui/src.
export default {
  darkMode: ['class'],
  theme: {
    extend: {
      fontFamily: {
        inter: ['var(--igloo-font-inter)'],
        sharetech: ['var(--igloo-font-share-tech-mono)'],
      },
      colors: {
        igloo: {
          page: '#030712',
          panel: 'rgb(15 23 42 / 0.6)',
          'panel-strong': 'rgb(15 23 42 / 0.8)',
          text: 'rgb(var(--igloo-rgb-slate-200) / <alpha-value>)',
          muted: 'rgb(var(--igloo-rgb-slate-400) / <alpha-value>)',
          subtle: 'rgb(var(--igloo-rgb-slate-500) / <alpha-value>)',
          border: 'rgb(var(--igloo-rgb-blue-900) / 0.3)',
          'border-muted': 'rgb(var(--igloo-rgb-blue-900) / 0.2)',
          primary: 'rgb(var(--igloo-rgb-blue-400) / <alpha-value>)',
          action: 'rgb(var(--igloo-rgb-blue-600) / <alpha-value>)',
          'action-hover': 'rgb(var(--igloo-rgb-blue-700) / <alpha-value>)',
          success: 'rgb(var(--igloo-rgb-status-success) / <alpha-value>)',
          warning: 'rgb(var(--igloo-rgb-status-warning) / <alpha-value>)',
          error: 'rgb(var(--igloo-rgb-status-error) / <alpha-value>)',
          info: 'rgb(var(--igloo-rgb-status-info) / <alpha-value>)',
        },
        // Explicit values preserved from chrome's (deleted) config so its inline
        // blue/gray/purple utilities render identically. Tailwind defaults still
        // apply for cyan etc. via theme.extend.
        gray: { 800: '#1f2937', 900: '#111827', 950: '#030712' },
        blue: {
          100: '#dbeafe', 200: '#bfdbfe', 300: '#93c5fd', 400: '#60a5fa',
          500: '#3b82f6', 600: '#2563eb', 700: '#1d4ed8', 900: '#1e3a8a',
          950: '#172554',
        },
        purple: { 900: '#581c87' },
      },
    },
  },
  plugins: [],
};
```

The shared client CSS entry (Tasks 2–4 create this per client as `src/index.css`):

```css
/* Build igloo-ui's source styles through this client's Tailwind pipeline.
   The @import pulls in igloo-ui's tokens, vendored fonts, @tailwind layers,
   and @layer component classes from source — no prebuilt dist. */
@import "../../igloo-ui/src/styles.css";
```

> Note on the import path: it is written relative to the **client `src/`** dir
> (`repos/igloo-<c>/src/index.css` → `../../igloo-ui/src/styles.css`). PostCSS/Vite
> rebase the nested `url("./fonts/*.woff2")` / `@import "./tokens/…"` inside
> igloo-ui's styles.css relative to that file, so the vendored fonts emit
> correctly. Task verification explicitly checks fonts load (no 404).

---

## File structure

- `repos/igloo-ui/tailwind.preset.js` — **create** (canonical tokens).
- `repos/igloo-ui/package.json` — **modify** (export preset + source styles;
  later, Task 7, repoint to src + drop dist build).
- `repos/igloo-pwa/`, `repos/igloo-home/` — **create** `tailwind.config.js` +
  `postcss.config.js`; **modify** `package.json` (devDeps), CSS resolution, and the
  CSS entry.
- `repos/igloo-chrome/tailwind.config.ts` — **modify** (use preset, delete dead
  theme); `scripts/build.mjs` + `src/index.css` — **modify** (source, not dist).
- `repos/igloo-ui/scripts/build.mjs`, `dist/`, build script — **delete** (Task 7).
- `Makefile` — **modify** (delete `igloo-ui-styles`, `igloo-ui-watch`, home dev
  prereqs) (Task 6).
- Parent repo — pointer bump (Task 8).

---

### Task 1: igloo-ui ships the Tailwind preset (additive — breaks nothing)

**Files:**
- Create: `repos/igloo-ui/tailwind.preset.js`
- Modify: `repos/igloo-ui/package.json` (exports map + files)
- Modify: `repos/igloo-ui/tailwind.config.js` (consume own preset, keep `content`)

**Interfaces:**
- Produces: `igloo-ui/tailwind.preset` (default export, a Tailwind config preset);
  `igloo-ui/styles.css` resolvable to **`./src/styles.css`** as well as the existing
  dist (both kept until Task 7).

- [ ] **Step 1: Create `tailwind.preset.js`** with the exact content from the
  "Canonical preset" section above.

- [ ] **Step 2: Point igloo-ui's own config at the preset** so its dist build (still
  used by un-migrated clients until Task 7) stays identical. Replace
  `repos/igloo-ui/tailwind.config.js` body with:

```js
/** @type {import('tailwindcss').Config} */
import iglooPreset from './tailwind.preset.js';

export default {
  presets: [iglooPreset],
  content: ['./src/**/*.{ts,tsx}'],
};
```

- [ ] **Step 3: Export the preset + source styles** from `package.json`. Add to the
  `exports` map (keep the existing `.` and `./styles.css` for now):

```json
    "./styles.css": "./dist/styles.css",
    "./src/styles.css": "./src/styles.css",
    "./tailwind.preset": "./tailwind.preset.js"
```

  And add `"tailwind.preset.js"` and `"src"` to the `files` array.

- [ ] **Step 4: Verify the dist build still produces identical CSS** (preset refactor
  must be a no-op for the current output):

Run: `npm --prefix repos/igloo-ui run build`
Expected: build succeeds; `git -C repos/igloo-ui diff --stat dist/styles.css` shows
**no change** (token output unchanged — the preset is a pure refactor).

- [ ] **Step 5: Commit (inside submodule).**

```bash
git -C repos/igloo-ui add tailwind.preset.js tailwind.config.js package.json
git -C repos/igloo-ui commit -m "Add canonical Tailwind preset; consume it in own config"
```

---

### Task 2: igloo-pwa consumes source CSS via the preset

**Files:**
- Create: `repos/igloo-pwa/tailwind.config.js`, `repos/igloo-pwa/postcss.config.js`
- Modify: `repos/igloo-pwa/package.json` (devDeps)
- Modify: `repos/igloo-pwa/vite.resolve.ts` (delete the CSS→dist alias)
- Modify: `repos/igloo-pwa/src/main.tsx` (CSS import), `repos/igloo-pwa/src/index.css`

**Interfaces:**
- Consumes: `igloo-ui/tailwind.preset` (Task 1).

- [ ] **Step 1: Add the CSS toolchain devDeps.**

```bash
npm --prefix repos/igloo-pwa install -D tailwindcss@^3.4.17 postcss@^8.4.47 autoprefixer@^10.4.20
```

- [ ] **Step 2: Create `repos/igloo-pwa/postcss.config.js`:**

```js
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
```

- [ ] **Step 3: Create `repos/igloo-pwa/tailwind.config.js`:**

```js
/** @type {import('tailwindcss').Config} */
import iglooPreset from 'igloo-ui/tailwind.preset';

export default {
  presets: [iglooPreset],
  content: ['./src/**/*.{ts,tsx}', '../igloo-ui/src/**/*.{ts,tsx}'],
};
```

- [ ] **Step 4: Delete the CSS→dist alias** in `repos/igloo-pwa/vite.resolve.ts` —
  remove this entry from the `alias` array:

```js
    {
      find: /^igloo-ui\/styles\.css$/,
      replacement: path.resolve(__dirname, '../igloo-ui/dist/styles.css'),
    },
```

- [ ] **Step 5: Rewrite the CSS entry.** In `repos/igloo-pwa/src/main.tsx`, delete
  line 4 `import 'igloo-ui/styles.css';` (the local `./index.css` import on line 7
  now carries it). Prepend to `repos/igloo-pwa/src/index.css`:

```css
@import "../../igloo-ui/src/styles.css";
```

  (Leave the existing `.igloo-dashboard-nav*` rules below it — P1 removes them.)

- [ ] **Step 6: Verify build + render.**

Run: `npm --prefix repos/igloo-pwa run build`
Expected: build succeeds; the emitted CSS bundle is non-empty and contains an
`igloo-*` component class (e.g. `grep -rl igloo-dashboard repos/igloo-pwa/dist/assets/*.css`).

Run: `make screenshot CLIENT=pwa STATE=dashboard-running`
Expected: `1 passed`; open `.tmp/agent/dashboard-running.png` — dashboard is fully
styled (Inter font loaded, panels/borders present), identical to before. Confirm no
font 404 in the run output.

- [ ] **Step 7: Commit (inside submodule).**

```bash
git -C repos/igloo-pwa add tailwind.config.js postcss.config.js package.json package-lock.json vite.resolve.ts src/main.tsx src/index.css
git -C repos/igloo-pwa commit -m "Consume igloo-ui source CSS via shared Tailwind preset; drop dist alias"
```

---

### Task 3: igloo-home consumes source CSS via the preset

**Files:**
- Create: `repos/igloo-home/tailwind.config.js`, `repos/igloo-home/postcss.config.js`
- Modify: `repos/igloo-home/package.json` (devDeps)
- Modify: `repos/igloo-home/vite.config.ts` (delete the CSS→dist alias)
- Modify: `repos/igloo-home/src/main.tsx`, `repos/igloo-home/src/index.css`

**Interfaces:**
- Consumes: `igloo-ui/tailwind.preset` (Task 1).

- [ ] **Step 1: Add devDeps.**

```bash
npm --prefix repos/igloo-home install -D tailwindcss@^3.4.17 postcss@^8.4.47 autoprefixer@^10.4.20
```

- [ ] **Step 2: Create `repos/igloo-home/postcss.config.js`** (identical to Task 2 Step 2).

- [ ] **Step 3: Create `repos/igloo-home/tailwind.config.js`** (identical to Task 2 Step 3).

- [ ] **Step 4: Delete the CSS→dist alias** in `repos/igloo-home/vite.config.ts` —
  remove the `{ find: /^igloo-ui\/styles\.css$/, replacement: …'../igloo-ui/dist/styles.css' }`
  alias object from the `resolve.alias` array.

- [ ] **Step 5: Rewrite the CSS entry.** In `repos/igloo-home/src/main.tsx`, delete
  line 3 `import 'igloo-ui/styles.css';`. Set `repos/igloo-home/src/index.css`
  (currently empty) to exactly:

```css
@import "../../igloo-ui/src/styles.css";
```

- [ ] **Step 6: Verify build + render.**

Run: `npm --prefix repos/igloo-home run build`
Expected: build succeeds.

Run: `make screenshot CLIENT=home STATE=dashboard-running`
Expected: `1 passed`; `.tmp/agent/home-dashboard-signer.png` is fully styled (Inter
loaded, AppHeader + tabs styled). No font 404 in output.

- [ ] **Step 7: Commit (inside submodule).**

```bash
git -C repos/igloo-home add tailwind.config.js postcss.config.js package.json package-lock.json vite.config.ts src/main.tsx src/index.css
git -C repos/igloo-home commit -m "Consume igloo-ui source CSS via shared Tailwind preset; drop dist alias"
```

---

### Task 4: igloo-chrome adopts the preset + source CSS; delete dead theme

**Files:**
- Modify: `repos/igloo-chrome/tailwind.config.ts` (preset; delete dead shadcn theme)
- Modify: `repos/igloo-chrome/scripts/build.mjs` (inline source styles, not dist)
- Modify: `repos/igloo-chrome/src/index.css`
- Modify: `repos/igloo-chrome/package.json` (ensure autoprefixer devDep)

**Interfaces:**
- Consumes: `igloo-ui/tailwind.preset` (Task 1).

- [ ] **Step 1: Confirm the shadcn theme is dead before deleting it.**

Run: `grep -rnE '\b(bg|text|border|ring)-(background|foreground|border|input|ring|primary|secondary|destructive|muted|accent|popover|card)\b|animate-accordion|container\b' repos/igloo-chrome/src`
Expected: no matches (verified 2026-06-19 for the color classes; confirm accordion/
container too). If any match appears, STOP and keep only the matched tokens in the
config rather than deleting wholesale.

- [ ] **Step 2: Replace `repos/igloo-chrome/tailwind.config.ts`** with the
  preset-based config (deletes the dead shadcn theme block):

```ts
import type { Config } from 'tailwindcss';
import iglooPreset from 'igloo-ui/tailwind.preset';

const config: Config = {
  presets: [iglooPreset as Config],
  darkMode: ['class'],
  content: ['./src/**/*.{ts,tsx}', '../igloo-ui/src/**/*.{ts,tsx}'],
};

export default config;
```

- [ ] **Step 3: Point chrome's CSS build at igloo-ui SOURCE styles.** In
  `repos/igloo-chrome/scripts/build.mjs`, change the inline-replacement source from
  the prebuilt dist to source:

```js
  const bundledInput = input.replace(
    /@import\s+["']igloo-ui\/styles\.css["'];?/g,
    await fs.readFile(path.join(rootDir, '../igloo-ui/src/styles.css'), 'utf8')
  );
```

  (Was `node_modules/igloo-ui/dist/styles.css`.) Confirm `src/index.css` keeps
  `@import "igloo-ui/styles.css";` — the build inlines it.

- [ ] **Step 4: Ensure autoprefixer is installed** (postcss.config references it):

```bash
npm --prefix repos/igloo-chrome install -D autoprefixer@^10.4.20
```

- [ ] **Step 5: Verify build + render.**

Run: `make igloo-chrome-build`
Expected: build succeeds; `repos/igloo-chrome/dist/index.css` is non-empty and
contains `igloo-` classes (`grep -c igloo- repos/igloo-chrome/dist/index.css` > 0).

Run: `make screenshot CLIENT=chrome STATE=dashboard-running`
Expected: `1 passed`; `.tmp/agent/chrome-dashboard-running.png` fully styled,
palette intact (blue/gray/cyan badges render).

- [ ] **Step 6: Commit (inside submodule).**

```bash
git -C repos/igloo-chrome add tailwind.config.ts scripts/build.mjs package.json package-lock.json
git -C repos/igloo-chrome commit -m "Adopt shared igloo-ui Tailwind preset + source CSS; delete dead shadcn theme"
```

---

### Task 5: Delete igloo-ui's prebuilt `dist` path (now that no client needs it)

**Files:**
- Modify: `repos/igloo-ui/package.json` (repoint to src; drop dist build + files)
- Delete: `repos/igloo-ui/scripts/build.mjs`, `repos/igloo-ui/dist/`

**Interfaces:**
- Produces: `igloo-ui` resolvable from source via `package.json` (for any
  non-aliased resolver, e.g. vitest), with no `dist`.

- [ ] **Step 1: Repoint `package.json` at source and drop the dist build.** Set:

```json
  "main": "./src/index.ts",
  "module": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "types": "./src/index.ts",
      "import": "./src/index.ts"
    },
    "./styles.css": "./src/styles.css",
    "./tailwind.preset": "./tailwind.preset.js"
  },
  "files": [
    "src",
    "tailwind.preset.js",
    "README.md"
  ],
```

  In `scripts`, **delete** the `build` line entirely (keep `test`).

- [ ] **Step 2: Delete the dist builder + any committed dist.**

```bash
git -C repos/igloo-ui rm -r --ignore-unmatch dist scripts/build.mjs
rm -rf repos/igloo-ui/dist
```

  (If `scripts/` has no other files, remove the dir.)

- [ ] **Step 3: Verify every client still builds + renders against source-only igloo-ui.**

Run: `make igloo-pwa-build && make igloo-home-build && make igloo-chrome-build`
Expected: all succeed (none reference `igloo-ui/dist`).

Run: `grep -rn "igloo-ui/dist" repos/igloo-pwa repos/igloo-home repos/igloo-chrome --include=*.ts --include=*.tsx --include=*.mjs --include=*.js`
Expected: **no matches** (the dist path is fully gone from consumers).

Run: `npm --prefix repos/igloo-ui run test`
Expected: igloo-ui unit tests pass (resolving its own source).

- [ ] **Step 4: Commit (inside submodule).**

```bash
git -C repos/igloo-ui add -A
git -C repos/igloo-ui commit -m "Delete prebuilt dist: consume igloo-ui as source-only (package exports -> src)"
```

---

### Task 6: Delete the Makefile band-aids

**Files:**
- Modify: `Makefile` (parent repo)

**Interfaces:**
- Consumes: nothing; this removes targets made obsolete by Tasks 1–5.

- [ ] **Step 1: Remove `igloo-ui-styles`** — delete it from the `.PHONY` list
  (line ~26) and delete its comment + recipe block (the `igloo-ui-styles:` target).

- [ ] **Step 2: Remove `igloo-ui-watch`** — delete it from `.PHONY`, delete its
  comment + recipe, and remove its `make help` line if listed.

- [ ] **Step 3: Restore the home dev targets** to have no prerequisite:

```make
igloo-home-dev:
	@npm --prefix "$(IGLOO_HOME_DIR)" run dev

igloo-home-tauri-dev:
	@npm --prefix "$(IGLOO_HOME_DIR)" run tauri -- dev
```

- [ ] **Step 4: Verify.**

Run: `grep -n "igloo-ui-styles\|igloo-ui-watch" Makefile`
Expected: **no matches.**

Run: `make help >/dev/null && make -n igloo-home-tauri-dev`
Expected: help parses; the dry-run shows **only** `npm … run tauri -- dev` (no
tailwind prerequisite).

- [ ] **Step 5: Commit (parent repo).**

```bash
git add Makefile
git commit -m "Delete igloo-ui-styles/igloo-ui-watch band-aids (superseded by all-source CSS, ADR-014 P0)"
```

---

### Task 7: Full-workspace verification

**Files:** none (verification only).

- [ ] **Step 1: Run the canonical gate.**

Run: `make verify`
Expected: exit 0; `.tmp/agent/verify.json` shows pass (guards + typecheck + `@fast`).

- [ ] **Step 2: Edit-a-style smoke test (proves the footgun is gone).** Append a
  visible rule to `repos/igloo-ui/src/styles.css` (e.g. a temporary
  `.igloo-shell-alert { outline: 2px solid red; }`), run
  `make screenshot CLIENT=home STATE=dashboard-running`, confirm the change appears
  **without** any `igloo-ui` build step, then revert the edit.
Expected: the outline shows in `.tmp/agent/home-dashboard-signer.png`; reverting
restores it. (Before P0 this required rebuilding `igloo-ui/dist`.)

- [ ] **Step 3: Confirm no dangling references.**

Run: `grep -rn "igloo-ui/dist\|igloo-ui-styles\|igloo-ui-watch" Makefile repos/igloo-pwa repos/igloo-home repos/igloo-chrome --include=*.ts --include=*.tsx --include=*.js --include=*.mjs --include=Makefile 2>/dev/null`
Expected: **no matches.**

---

### Task 8: Atomic landing — bump submodule pointers

**Files:** parent repo pointer commit.

- [ ] **Step 1: Confirm all four submodules are committed and clean.**

Run: `for r in igloo-ui igloo-pwa igloo-home igloo-chrome; do echo "$r:"; git -C repos/$r status --short; done`
Expected: all clean (Tasks 1–5 committed inside each).

- [ ] **Step 2: Bump all moved pointers in one parent commit.**

Run: `make bump-pointers MSG="Adopt shared-UI consumption contract (ADR-014 P0): all-source CSS + Tailwind preset; drop igloo-ui dist"`
Expected: one parent commit recording the igloo-ui/pwa/home/chrome pointer moves.

- [ ] **Step 3: Final gate after the bump.**

Run: `make verify`
Expected: exit 0.

- [ ] **Step 4: Mark the BACKLOG P0 item done.** In `dev/BACKLOG.md`, check off the
  P0 "Consumption contract + Tailwind preset, atomic hard cut" item with a
  `**DONE (2026-06-19)**` prefix and commit.

```bash
git add dev/BACKLOG.md
git commit -m "BACKLOG: mark ADR-014 P0 (consumption contract) done"
```

---

## Self-Review

**Spec coverage (ADR-014 a + b, P0 scope):**
- (a) one consumption contract, all-source JS+CSS, single shared resolution per
  client → Tasks 2/3/4 (clients) + Task 5 (igloo-ui exports→src). ✓
- (b) shared Tailwind preset; delete prebuilt dist + Makefile band-aids → Task 1
  (preset), Tasks 2–4 (adopt), Task 5 (delete dist), Task 6 (Makefile). ✓
- Hard cut / no-compat: dist deleted (Task 5), dead chrome theme deleted (Task 4),
  band-aids deleted (Task 6); no aliases retained. ✓
- Atomic landing across 4 repos → Task 8. ✓
- P1/P2 items (visual seam, nav/Checkbox/Alert, adapters, DesktopAppShell) are
  **out of scope** for this plan by design (separate plans).

**Placeholder scan:** none — every config/file step shows the exact content; every
verify step has an exact command + expected result.

**Type/name consistency:** the preset's default export is consumed identically as
`igloo-ui/tailwind.preset` in Tasks 2/3/4; the client CSS entry path
`../../igloo-ui/src/styles.css` is identical across clients; `igloo-ui/styles.css`
export resolves to `./src/styles.css` after Task 5 (chrome inlines the source file
directly, so it is unaffected by the export change).

**Ordering safety:** the prebuilt dist is deleted (Task 5) only after all three
clients stop consuming it (Tasks 2–4), so no intermediate state is broken. Task 1 is
additive (dist still builds), so un-migrated clients keep working between Tasks 1–4.
