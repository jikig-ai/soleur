---
feature: chore-blog-source-available
issue: 5043
date: 2026-06-08
lane: single-domain
brand_survival_threshold: brand-positioning-consistency
brainstorm: knowledge-base/project/brainstorms/2026-06-08-blog-source-available-positioning-brainstorm.md
---

# Spec: Soleur-subject "open source" → "source-available" in dated blog posts

## Problem Statement

Soleur is licensed under BSL 1.1 (source-available, NOT OSI-approved). PR #5036 corrected every
Soleur-subject "open source" claim on evergreen pages to "source-available (BSL 1.1)" and fixed
explicit Apache claims in blog bodies, but deliberately deferred the generic Soleur-subject "open
source" positioning in the **body** of ~11 dated blog comparison posts to a CMO call (#5043). The
result is (a) factually imprecise Soleur-subject "open source" claims persisting in
decision-grade surfaces (comparison tables, JSON-LD) and (b) a visible contradiction between blog
copy and the already-corrected evergreen pages.

CMO decision (2026-06-08, operator/brand-owner): **sweep Soleur-subject "open source" →
"source-available (BSL 1.1)"**, preserving the underlying auditability/transparency claim (true
under BSL).

## Goals

- G1: Every **Soleur-subject** "open source" / "open-source" claim in `plugins/soleur/docs/blog/*.md`
  reads "source-available (BSL 1.1)" (or compact "source-available" where table width requires),
  across narrative prose, comparison-table rows, frontmatter, AND JSON-LD structured data.
- G2: The auditability/transparency positioning is preserved (reword the *label*, keep the claim:
  "source-available and auditable: every agent prompt … is readable").
- G3: `marketing-content-drift.test.ts` Test 2c is extended to ban Soleur-subject "open source"
  phrasings in blog posts, locking the fix against regression. The #5043 deferral comments
  (L160-161, L190) are updated to reflect resolution.

## Non-Goals

- NG1: Do NOT touch **competitor/ecosystem** "open source" references — they are accurate and must
  stay verbatim: CrewAI (MIT), Paperclip (MIT), Spec Kit / GitHub spec-kit / OpenSpec, and Cowork's
  own free/open-source tier cells.
- NG2: No changes to evergreen pages (`pages/`, `*.njk`) — already handled by #5036.
- NG3: No license change, no LICENSE file edits, no new positioning beyond the
  open-source→source-available label correction.

## Functional Requirements

- FR1: Rewrite Soleur-subject hits in the 11 posts enumerated in the brainstorm's "Affected files"
  section. Each edit must verify the **subject** of the "open source" mention is Soleur before
  changing it.
- FR2: `2026-03-31-soleur-vs-paperclip.md` requires *separating* the two products rather than
  blanket-replacing: keep Paperclip as open-source (MIT); make Soleur source-available (BSL 1.1).
  This affects `seoTitle`, `description`, and the Q&A prose that frame "both open-source platforms".
- FR3: JSON-LD blocks (vs-cursor L142, vs-polsia L157/L160, vs-crewai L163) must be kept in sync
  with their narrative prose — these are AEO surfaces and must not contradict the visible copy.
- FR4: Extend `marketing-content-drift.test.ts` Test 2c with a Soleur-subject "open source"
  regex mirroring Test 2b's `open[- ]source (version|Company-as-a-Service|Claude Code platform|AI
  agents)|is open source|...` pattern, scoped to the blog walk. Verify it fails before the sweep and
  passes after (RED→GREEN).

## Technical Requirements

- TR1: Discriminate Soleur-subject from competitor-subject per-line (NG1). A blanket find-replace is
  incorrect and will produce false statements about competitors.
- TR2: Run the full `marketing-content-drift.test.ts` suite green after edits; specifically Test 2b
  (evergreen), Test 2c (blog Apache floor + new Soleur-subject ban).
- TR3: Build the Eleventy site (`plugins/soleur/docs`) to confirm no frontmatter/JSON-LD breakage
  from the edits.

## Acceptance Criteria

- AC1: `git grep -niE "soleur is (an )?open[- ]source" plugins/soleur/docs/blog/` returns zero hits.
- AC2: Competitor references intact: CrewAI/Paperclip/Spec-Kit "open source" mentions unchanged.
- AC3: `marketing-content-drift.test.ts` passes, with the new Test 2c assertion present and the
  #5043 deferral comments updated to "resolved (#5043)".
- AC4: Eleventy build succeeds.
