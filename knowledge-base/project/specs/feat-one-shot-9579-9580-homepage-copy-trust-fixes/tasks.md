# Tasks: homepage copy and trust fixes (#9579) and land the CLO audit (#9580)

Plan: `knowledge-base/project/plans/2026-10-06-fix-homepage-copy-and-trust-fixes-plan.md`
Issues: Closes #9579, Closes #9580. Draft PR: #9584. Follow-ups filed: #9588 to #9593.

## Phase 0: Prerequisites (before any copy edit)

- 0.1 Pull the 28-day Plausible baseline (visitors to `/`, `Waitlist Signup` with `location=homepage-hero`); record it as a comment on #9588.
- 0.2 Create the Plausible goal `Hero Self-host Click` (Sites API, else Playwright on the dashboard; login or 2FA is the only hand-off).
- 0.3 Verify Buttondown double opt-in is enabled; gates both the privacy line (D5) and the success text (D7); freeze all copy after this step.
- 0.4 Confirm the Playwright MCP server is reachable (it failed to connect late in planning); fact-check the final quote block with `soleur:marketing:fact-checker`.
- 0.5 Verify the `plausible-event-name=Hero+Self-host+Click` class fires under the site's script and CSP.

## Phase 1: RED tests (`plugins/soleur/test/seo-aeo-drift-guard.test.ts`)

- 1.1 Guard 1: hosted-claims copy guard (sentence scan, JSON-LD twins, floors on pages and hosted sentences scanned).
- 1.2 Guard 2: computed-counts guard; re-pin Test 16 (homepage moves to computed counts; pricing and about stay on the soft floor); hero compare href assertion.
- 1.3 Guard 3: attribution guard (no `subjectOf`, no "As seen in", no removed quote, all built pages).
- 1.4 Run the suite and confirm each new assertion fails for the intended reason.

## Phase 2: GREEN copy and markup

- 2.1 `index.njk`: hero (plan line, primary CTA with tagged event, hosted card, privacy line visible with `newsletter-privacy`, compare link), counts, FAQ and JSON-LD twins, quote section, Discord line, competitor sentences (`starts? fresh every session`, three strings).
- 2.2 `page-freshness.njk`: `summaryCounts: computed` opt-in; set only on the homepage.
- 2.3 `pricing.njk`: remove "Pro, Max,", FAQ answers, claude note, privacy line (visible and JSON-LD).
- 2.4 `getting-started.njk`: byte/compute claims, prerequisite line, `scroll-margin-top`, "cloud platform" to "hosted version" (visible and JSON-LD).
- 2.5 `base.njk`: remove `subjectOf`; footer non-affiliation line; success strings (D7, gated); inline new above-the-fold selectors (names `landing-hero-*`/`hero-waitlist-form-*`), update the "Selectors covered" comment, check the gzipped budget; add `index.njk` to `check-critical-css-coverage.mjs` `TEMPLATE_ROOTS`; recompute the CSP hash LAST and run `validate-csp.sh` right away.
- 2.6 `company-as-a-service.njk` line 136 wording.
- 2.7 `site.json` `statsLastVerified` set after comparing `stats.js` output with the rendered homepage.
- 2.8 `style.css`: plan line, hosted label, privacy-line contrast scoped to `.hero-waitlist-form .newsletter-privacy`, `.hero-cta` wrap at 768px (widen the `btn-primary` rule to `btn-secondary`), quote paragraph styles; delete dead `.landing-press-strip` and `.press-outlet*` rules.
- 2.9 `screenshot-gate.mjs`: two inline-only assertions for `/` (privacy line below submit; no overflow at 390px via a second browser context).
- 2.10 Bump `last_updated` and `date` on the four edited pages.

## Phase 3: Governing documents and audit

- 3.1 `brand-guide.md`: dated Numbers carve-out; dated, test-scoped CTA carve-out with review date and revert trigger.
- 3.2 `roadmap.md`: Phase 4 row pointing at #9588.
- 3.3 Commit the #9580 audit unchanged.

## Phase 4: Verify

- 4.1 `SOLEUR_DOCS_OFFLINE=1 npm run docs:build`; `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts`.
- 4.2 `validate-seo.sh _site`, `validate-csp.sh _site`, `check-critical-css-coverage.mjs`, `check-stylesheet-swap.mjs`, `screenshot-gate.mjs` against a local server; `marketing-content-drift.test.ts` stays green.
- 4.3 Playwright screenshots at 1440, 768, 390, 320 (absolute paths), contrast check, grep sweeps from the acceptance criteria.

## Phase 5: Sign-off and ship

- 5.1 Submit diff and before/after string table to `soleur:legal:clo` (ship Phase 5.5 gate); resubmit if any string changes afterwards.
- 5.2 PR body: `Closes #9579`, `Closes #9580`, Legal section, `## Changelog`, `semver:patch`; render `decision-challenges.md` into it.
- 5.3 Post-merge: one Playwright click on the install button, confirm `Hero Self-host Click` in the Plausible Stats API.
