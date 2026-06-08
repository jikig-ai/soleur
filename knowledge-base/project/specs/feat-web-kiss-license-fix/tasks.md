---
feature: web-kiss-license-fix
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-08-feat-soleur-ai-license-correction-kiss-declutter-plan.md
issue: 5038
defer_issue: 5043
---

# Tasks — soleur.ai license correction + KISS declutter

## Phase 0 — Verification (no edits)

- [x] 0.1 Re-run authoritative claim grep over `plugins/soleur/docs/` (incl. blog) — freeze the
  Soleur-subject claim site list.
- [x] 0.2 Grep asserting consumers: `git grep -inE "apache|open source|LICENSE-2\.0" -- 'plugins/soleur/test/**' '.github/workflows/**'`. Confirm `seo-aeo-drift-guard.test.ts:843-847` is the only license-asserting test; confirm `deploy-docs.yml` has no license gate; check seo-aeo Test 16.
- [x] 0.3 `ls node_modules/@11ty/eleventy/package.json` (worktree must have deps before any build).

## Phase 1 — Commit 1: license correction + regression guard

### Sweep (Soleur-subject claims → source-available BSL 1.1)
- [x] 1.1 `_includes/page-freshness.njk` — edit BOTH `:20` and `:22` meta `_summary` branches.
- [x] 1.2 `_includes/base.njk:103,106` — Offer schema framing.
- [x] 1.3 `index.njk:16,33,197,205` prose + `:253,269` JSON-LD twins; reconcile `:33`↔`:281` CTA wording.
- [x] 1.4 `pages/about.njk` — `:33,51,74` positioning; reframe `:81/:123` `<summary>`/`name` to
  "Is Soleur free to self-host?"; pin answer prose at `:82/:126` (and `index.njk:197/:253`):
  "Soleur is source-available under BSL 1.1 — free to self-host for individual and internal
  business use, fully inspectable on GitHub, and it converts to Apache-2.0 four years after each release."
- [x] 1.5 `pages/getting-started.njk` — `:32` definition lead (mandatory), `:19,47,50` copy, `:36`
  Apache link → `{{ site.github }}/blob/main/LICENSE`, FAQ prose `:163,167,171,175,187` + twins.
- [x] 1.6 `pages/pricing.njk:28,49,303,355`.
- [x] 1.7 `pages/community.njk:47` (keep `:104,147` ecosystem); `pages/legal.njk:23`.
- [x] 1.8 `pages/compare-soleur-vs-cursor.njk:32,78,83,119,129` + `compare-soleur-vs-devin.njk:36,82,87,129`.
- [x] 1.9 `pages/vision.njk:175`, `pages/agents.njk:31`, `pages/company-as-a-service.njk:192`.
- [x] 1.10 `blog/*.md` — explicit Apache claims only (per 0.1 grep). Leave generic body positioning (→ #5043).
- [x] 1.11 Verify each edited JSON-LD `<script type="application/ld+json">` block still parses as JSON.

### Coupled test + regression guard
- [x] 1.12 Update `seo-aeo-drift-guard.test.ts:843-847` Apache-host assertion → `github.com` (the LICENSE link).
- [x] 1.13 Add guard test case to `marketing-content-drift.test.ts`: (a) `walkSiteCopy` bans Soleur-subject
  Apache + "open source" phrasings, excludes `pages/legal/**`, present-tense-anchored; (b) separate
  `blog/**.md` Apache-only assertion; allowlist comment enumerates deferred blog files + links #5043.
- [x] 1.14 RED check: seed an "Apache-2.0 licensed" line → guard fails; remove → passes.
- [x] 1.15 Run closure grep AC (legal-excluded, present-tense) → zero; `bun test plugins/soleur/` green.
- [x] 1.16 Commit 1 (license + guard + coupled test). PR body `Ref #5038`.

## Phase 2 — Commit 2: KISS homepage declutter (`index.njk`)

- [x] 2.1 CUT `<section class="landing-cta-mid">` (`:108`).
- [x] 2.2 Hero `.hero-cta` (`:31-35`): drop `:32` See-Pricing CTA; keep reworded `:33` self-host link AND `:34` compare anchor. **Deviation:** the compare anchor was RESTORED — `seo-aeo-drift-guard.test.ts:986` enforces the #3996 AEO invariant that the hero links to `#soleur-vs-copilots`. Wireframe's "one link" intent yields to the tested AEO requirement.
- [x] 2.3 Final CTA (`:277-278`): keep form + `.newsletter-status` node + JS; replace `:278` H2 with a distinct closing line.
- [x] 2.4 Compress "This Is the Way" prose (`:59-60`) overlap with the Compare section.
- [x] 2.5 Do NOT touch the site-wide `newsletter-form.njk` include (segment-distinct; spec-flow defect).
- [x] 2.6 Build from repo root (`npm run docs:build`); run `check-critical-css-coverage.mjs` + `screenshot-gate.mjs`; re-inline into `base.njk:140-215` if any above-fold selector shifts.
- [x] 2.7 Wireframe parity eyeball; FAQ/Compare/stats unchanged.
- [x] 2.8 Commit 2 (declutter).

## Phase 3 — Ship

- [ ] 3.1 Push; mark PR #5036 ready; QA/review per lifecycle.
- [ ] 3.2 Post-merge: verify live soleur.ai (homepage + meta + a compare page) shows source-available, no Apache (WebFetch); `gh issue close 5038`.
