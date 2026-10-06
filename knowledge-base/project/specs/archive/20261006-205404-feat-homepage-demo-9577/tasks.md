# Tasks: homepage fan-out demo (#9577)

Plan: knowledge-base/project/plans/2026-10-06-feat-homepage-fanout-demo-plan.md

## Phase 0 — Preconditions

- [x] 0.1 `git fetch origin main`; re-confirm `index.njk` section order and `ABOVE_FOLD_PREFIXES`
- [x] 0.2 Put the Option A copy decision in the PR body

## Phase 1 — Failing drift test (RED)

- [x] 1.1 Create `plugins/soleur/test/fanout-demo-drift.test.ts` (temp-dir build, `visible-text.ts` helpers, default export of the data file, `STATUS_LABELS` text parse)
- [x] 1.2 In-memory fixtures for the validator's throw and a `types.ts` variant with no `STATUS_LABELS`
- [x] 1.3 Run and record RED for the right reason

## Phase 2 — Build the section (GREEN)

- [x] 2.1 `plugins/soleur/lib/fanout-validate.js` and `plugins/soleur/docs/_data/fanoutDemo.js` (default export only)
- [x] 2.2 `index.njk`: the section and `id="departments"`
- [x] 2.3 `style.css`: section styles, `scroll-margin-top`, forced-colors, print, reduced-motion scroll fix
- [x] 2.4 `npm run docs:build`, the new suite, `check-critical-css-coverage.mjs`, `seo-aeo-drift-guard`, `marketing-content-drift`, `jsonld-escaping`

## Phase 3 — Visual and accessibility verification

- [x] 3.1 Screenshot gate (both 320 px passes) and renders at 1440, 390, 375, 360, 320
- [x] 3.2 Accessibility tree, forced-colors and contrast checks
- [x] 3.3 Link jump below the fixed header, instant under reduced motion, print preview, no hover styling

## Phase 4 — Review gates and pre-merge records

- [x] 4.1 CLO review of the built text (verdict PASS-WITH-EDITS 2026-10-06, edits applied in bae62205d5; verdict recorded in the spec amendment)
- [x] 4.2 Spec amendment is already recorded; mark wireframe PNGs 13–15 superseded
- [x] 4.3 Pre-merge bundled-change line in the `brand-guide.md` hero-CTA note
- [x] 4.4 Comment the attribution rule on #9588
- [ ] 4.5 `soleur:qa` browser pass

## Phase 5 — After deploy

- [ ] 5.1 Verify the live section, one `id="departments"`, no `plausible` markup on the link
- [ ] 5.2 Comment the ship date on #9588
- [ ] 5.3 Coordinate with #9620 before any hosted depiction
