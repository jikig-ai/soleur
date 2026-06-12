---
feature: loop-engineering-positioning
issue: 5088
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-12-feat-loop-engineering-positioning-blog-plan.md
---

# Tasks: Loop Engineering Positioning Blog (#5088)

## Phase 0 — Verify source material first
- [x] 0.1 WebFetch Osmani essay; capture verbatim "loop engineering" definition + June-2026 provenance + URL
- [x] 0.2 Locate Cherny + Steinberger endorsement quotes; confirm each verbatim-sourceable with a URL
- [x] 0.3 For any non-verbatim-sourceable quote, plan attributed-summary form (not quotation)
- [x] 0.4 Record sourced quote set + URLs in PR scratch

## Phase 1 — Draft (content-writer)
- [x] 1.1 Invoke content-writer with the brief: title "Loop Engineering for Your Whole Company, Not Just Your Codebase" (operator-confirmed hook — retain)
- [x] 1.2 Honest-hedge 6-element mapping: claim worktrees/skills/MCP-connectors/external-memory company-wide; automations + maker/checker as "proven in engineering, extending outward" (declarative, no hedge words)
- [x] 1.3 Distinguish 4 git-committed MCP servers from runtime-available; block 4 = "MCP connectors" (never "plugin" for Soleur)
- [x] 1.4 Credit-and-extend wall: attributed section separated from Soleur claims/CTAs + non-affiliation disclaimer
- [x] 1.5 Voice: technical register, soft floors ("60+ agents/skills"), avoid forbidden words; no "open source" self-claim
- [x] 1.6 FAQPage (2+ Qs incl. affiliation Q) using `jsonLdSafe` (not `dump`); cross-link FROM post to agentic-engineering page
- [x] 1.7 Output: `plugins/soleur/docs/blog/2026-06-12-loop-engineering-for-your-whole-company.md`

## Phase 2 — BLOCKING verbatim-quote gate (fact-checker)
- [x] 2.1 fact-checker on every named-person quote + the term definition: verbatim + sourced URL; record PASS

## Phase 3 — BLOCKING legal pass (legal-compliance-auditor, same frozen draft)
- [x] 3.1 No false-endorsement; wall intact; disclaimer present; no "open source" self-claim; record PASS

## Phase 4 — Build + content-drift gate
- [x] 4.1 `bun test plugins/soleur/test/marketing-content-drift.test.ts` green (Test 1/2/2b/2c/2c2)
- [x] 4.2 Eleventy build green (exercised by 4.1 beforeAll) + `seo-aeo-drift-guard` ≥1 post
- [x] 4.3 Manual: no Soleur-subject hedge words / "plugin" / "open source"; disclaimer string present

## Phase 5 — Social distribution draft (social-distribute)
- [x] 5.1 Invoke social-distribute → `knowledge-base/marketing/distribution-content/<slug>.md`, status: draft, channels set, timeliness flagged

## Ship
- [ ] PR body: `Closes #5088`; reference #5212 (stays OPEN); no "open source" self-claim in PR body
- [ ] Post-merge (operator): set `publish_date` + flip `status: scheduled` to publish within the news window
