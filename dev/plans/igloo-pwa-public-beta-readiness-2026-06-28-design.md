# igloo-pwa Public Beta Readiness Design

_Status: Implemented 2026-06-28._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` Phase 1._

> **For agentic workers:** this is a small release-readiness slice. Keep the
> implementation centered on `repos/igloo-pwa` docs, repo-local validation, and
> audit classification. Do not perform live GitHub Pages or Cloudflare deploy
> operations in this slice.

## Problem

Phase 1 says the PWA is closest to public beta, but it still needs a final
repo-local readiness pass before operator-owned deploy work: verify the PWA C1
masking behavior on its own surface, confirm the license, make the deployment
instructions match the selected GitHub Pages plus Cloudflare topology, publish
usable end-user docs, and classify the npm audit result.

Grounding shows that `repos/igloo-pwa` already has a `LICENSE`,
`DEPLOYMENT.md`, and `docs/USER_GUIDE.md`. The remaining work is therefore a
focused refinement and verification pass, not a rewrite.

## Goal

Complete the five agent-doable Phase 1 PWA readiness tasks without widening
into live hosting, browser-store operations, or breaking dependency upgrades.

## Chosen Approach

Use a docs-and-validation hardening pass:

- prove C1 through the existing `RecoverPrivateKeyView` masking test;
- confirm the existing MIT `LICENSE` is present and current;
- refine README deployment wording so cross-origin isolation is delivered by
  the Cloudflare front layer rather than framed as a static-host hard
  requirement;
- link `DEPLOYMENT.md` and `docs/USER_GUIDE.md` from README and fill any small
  user-doc gaps;
- run `npm audit` for all deps and for production deps only, then fix only
  beta-relevant issues. A breaking Vite major upgrade remains deferred because
  the backlog already classifies the remaining esbuild advisory as dev-server
  only and not shipped in the static bundle.

## Alternatives Rejected

**Live deploy now.** Rejected because GitHub Pages and Cloudflare ownership are
operator tasks with external credentials and DNS state.

**Force all dev-dependency advisories to zero.** Rejected if the only remaining
path is a breaking Vite major upgrade already deferred in the backlog. The beta
gate requires zero production vulnerabilities and an explicit dev-only
classification.

**Rewrite existing docs.** Rejected because the current PWA docs already cover
the required topics; small corrections are lower-risk and easier to review.

## Scope

In scope:

1. PWA C1 masking verification.
2. MIT license confirmation.
3. README and deployment/user-doc refinements.
4. npm audit classification and beta-relevant fixes.
5. Parent release-plan/backlog updates if the audit result changes the status.

Out of scope:

- Live Pages publish, Cloudflare DNS/header changes, and live header checks.
- PWA Vite major upgrade unless audit shows a production vulnerability.
- Chrome Web Store, `frost2x`, or Home release-artifact work.

## Verification

Use focused checks first:

- `npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "reveals, masks, and clears the recovered private key"`
- `npm --prefix repos/igloo-pwa audit --omit=dev`
- `npm --prefix repos/igloo-pwa audit`
- `npm --prefix repos/igloo-pwa run test:unit:raw`
- `npm --prefix test run test:guards:docs`

## Done When

- PWA recovered-key masking is verified.
- License is confirmed present.
- README points beta operators/users to deployment and user docs.
- Deployment docs clearly describe GitHub Pages plus Cloudflare headers and no
  service worker.
- User docs cover install, first run, troubleshooting, and lost-share recovery.
- npm audit has zero production vulnerabilities, with any remaining dev-only
  vulnerability explicitly classified or fixed.

## Self-Review

Placeholder scan: no TBD/TODO placeholders.

Internal consistency: the design does not claim live deployment is complete.

Scope check: this is one repo-local release-readiness pass.

Ambiguity check: breaking dependency upgrades are conditional on production
audit impact, not dev-only advisories.
