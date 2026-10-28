# Tasks: census-lint spoke (#11364)

Plan: `knowledge-base/project/plans/2026-10-28-content-census-lint-spoke-plan.md`

## Phase 1 — Draft + image (soleur:content-writer, inline)

- 1.1 Write the founder sentence in working notes; draft per the plan's Draft Spec
- 1.2 Write `plugins/soleur/docs/blog/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` (1,500–2,000 words, FAQ + parity FAQPage JSON-LD, hub link once, closing PR #11278 URL, waitlist CTA)
- 1.3 Generate `plugins/soleur/docs/images/blog/og-alarm-passed-every-rehearsal-never-rings.png` with PIL from `/tmp` (1200×630, `#1a1a1a` + gold, textless, metadata-clean); commit the PNG only

## Phase 2 — Site wiring

- 2.1 Append the redirect pair last in `local.blog_redirect_pairs` (`apps/web-platform/infra/seo-bulk-redirects.tf`), `=` column-aligned
- 2.2 Append one facts-only retro-link sentence to the hub's census paragraph (`2026-11-19-first-we-made-green-mean-something.md`)
- 2.3 Append the Pillar-2 row to `knowledge-base/marketing/content-strategy.md` after the hub row

## Phase 3 — Distribution + calendar

- 3.1 Write `knowledge-base/marketing/distribution-content/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` (`status: draft` → `validate-tweet-draft.sh` → flip to `status: scheduled` last)
- 3.2 Regenerate `knowledge-base/marketing/campaign-calendar.md` (soleur:campaign-calendar, headless)

## Phase 4 — Verification (soleur:marketing:fact-checker, inline)

- 4.1 Fact-check every pin (esp. the sourced-or-scoped generalization sentence and per-case attribution); also fact-check distribution variants
- 4.2 `blog-jargon-scan.sh` rc 0 + read-through
- 4.3 `npm run docs:build`; `bun test` the four content suites; `bash scripts/validate-blog-links.sh`
- 4.4 Mutation sanity: delete PNG (AC5 reds), drop redirect (link validator reds)
- 4.5 `grep -rn 2026-12-03` date-coherence sweep (AC10)

## Phase 5 — Ship

- 5.1 PR body line 1: merge-mutates-production answer; `Closes #11364`; disclose that hub + spoke go live at merge, social wave Dec 3
