# Tasks: census-lint spoke (#11364)

Plan: `knowledge-base/project/plans/2026-10-28-content-census-lint-spoke-plan.md`

## Phase 1 — Draft + image (soleur:content-writer, inline)

- [x] 1.1 Write the founder sentence in working notes; draft per the plan's Draft Spec
- [x] 1.2 Write `plugins/soleur/docs/blog/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` (1,973 body words, FAQ + parity FAQPage JSON-LD, hub link once, closing PR #11278 URL, waitlist CTA)
- [x] 1.3 Generate `plugins/soleur/docs/images/blog/og-alarm-passed-every-rehearsal-never-rings.png` with PIL from `/tmp` (1200×630, `#1a1a1a` + gold, textless, metadata-clean); committed the PNG only

## Phase 2 — Site wiring

- [x] 2.1 Append the redirect pair last in `local.blog_redirect_pairs` (`apps/web-platform/infra/seo-bulk-redirects.tf`), `=` column-aligned
- [x] 2.2 Append one facts-only retro-link sentence to the hub's census paragraph (`2026-11-19-first-we-made-green-mean-something.md`)
- [x] 2.3 Append the Pillar-2 row to `knowledge-base/marketing/content-strategy.md` after the hub row

## Phase 3 — Distribution + calendar

- [x] 3.1 Write `knowledge-base/marketing/distribution-content/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` (`status: draft` → `validate-tweet-draft.sh` rc 0 → flipped to `status: scheduled`; parse-equivalence PASS)
- [x] 3.2 Regenerate `knowledge-base/marketing/campaign-calendar.md` (scripted regen; also picked up two files the publisher flipped to `published` today)

## Phase 4 — Verification (soleur:marketing:fact-checker, inline)

- [x] 4.1 Fact-check every pin — independent `claude -p` fact-checker spawn: 33 claims, 30 PASS, 2 FAIL + 1 UNSOURCED all remediated (census scope wording, `instanceof Error` exemption nuance, scoped generalization); distribution variants covered
- [x] 4.2 `blog-jargon-scan.sh` rc 0 (pre- and post-remediation) + read-through
- [x] 4.3 `npm run docs:build` clean (spoke page renders); `bun test` the four content suites green (192/192); `bash scripts/validate-blog-links.sh` green
- [x] 4.4 Mutation sanity: PNG deleted → AC5 size check reds while seo-aeo-drift-guard stays green (documented blind spot); redirect dropped → `validate-blog-links.sh` reds; both restored
- [x] 4.5 `grep -rn 2026-12-03` date-coherence sweep — exactly the five sanctioned sites, no stale variants

## Phase 5 — Ship

- [ ] 5.1 PR body line 1: merge-mutates-production answer; `Closes #11364`; disclose that hub + spoke go live at merge, social wave Dec 3
