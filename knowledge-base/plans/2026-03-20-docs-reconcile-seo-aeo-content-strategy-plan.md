---
title: Reconcile SEO/AEO/GEO Audit into Content and Marketing Strategy
type: docs
date: 2026-03-20
---

# Reconcile SEO/AEO/GEO Audit into Content and Marketing Strategy

## Overview

Update `content-strategy.md` and `marketing-strategy.md` to reconcile with the 2026-03-17 growth audit findings. Both documents are significantly stale — the marketing strategy describes a pre-blog state that no longer exists (8 blog posts published, AEO score 68/100, 3 comparison articles live). The content strategy's 4-week calendar and gap analysis predate the audit's fresh keyword research and competitive data.

## Problem Statement / Motivation

The 2026-03-17 growth audit (#661) identified:
- **5 critical content issues** (FAQ JSON-LD gaps, "plugin" in meta descriptions, Vision page H1)
- **12 improvement issues** (missing keywords, cross-links, OG images)
- **AEO score: 68/100 (C+)** with a stark blog-vs-catalog split (blog 80%, catalog 40%)
- **Zero listicle presence** — Soleur appears on none of the major "best AI agent" lists
- **New content priorities** scored 16-18/20 (Vibe Coding article, AI Agents for Solo Founders pillar)

None of these findings are reflected in the strategy documents that drive execution. Without reconciliation, the content calendar and gap analysis cannot guide next steps.

## Proposed Solution

**Approach:** Layered update (chosen in brainstorm). Mark completed gaps, update remaining with audit data, add new gaps, replace stale calendar.

**Files to modify:**

| File | Path | Action |
|------|------|--------|
| Content Strategy | `knowledge-base/marketing/content-strategy.md` | Layered update: gaps, pillars, calendar, standards |
| Marketing Strategy | `knowledge-base/marketing/marketing-strategy.md` | Refresh: current state, phased plan, KPIs |
| SEO Refresh Queue | `knowledge-base/marketing/seo-refresh-queue.md` | Update: mark completed items, add audit findings |

### Phase 1: Update `content-strategy.md`

#### 1.1 Update frontmatter

**Note:** The existing files have stale `depends_on` paths pointing to `knowledge-base/overview/`. Fix these to match actual filesystem paths:

```yaml
last_updated: 2026-03-20
last_reviewed: 2026-03-20
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/marketing/marketing-strategy.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-plan.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-seo-audit.md
```

#### 1.2 Update Content Gap Analysis

Mark completed gaps and update remaining ones:

| Gap | Action | Detail |
|-----|--------|--------|
| Gap 1: Cross-Domain Compounding | **Update** | Partially addressed in "Why Tools Plateau" blog post. Narrow scope: dedicated pillar still needed for "Knowledge Compounding in AI Development" (P2, content plan priority). |
| Gap 2: CaaS Category Definition | **Mark COMPLETED** | "What Is Company-as-a-Service?" pillar article published. SAP score 5.0/5.0 (best on site). FAQ JSON-LD present. 10+ external citations. |
| Gap 3: IDE Positioning | **Update** | 3 comparison articles now exist (Cowork, Cursor, Notion Custom Agents). Narrow remaining work to "Agent Platform vs. AI Organization" positioning paper. |
| Gap 4: Engineering-in-Context | **Update** | "Why Tools Plateau" partially covers this. Audit priority P2-1 "Vibe Coding vs Agentic Engineering" (score: 18/20) is the execution target. Update gap to reference this specific article. |
| Gap 5: Autopilot vs Decision-Maker | **Update** | Soleur vs Polsia comparison article exists but a standalone position paper is still needed. Align with audit P2-3 "Soleur vs Polsia" (score: 16/20). |
| Gap 6: Cursor Agent Platform | **Mark COMPLETED** | "Soleur vs Cursor" comparison published 2026-03-19, addressing Automations + Marketplace. |
| Gap 7: Copilot Cowork + Anthropic | **Update** | Cowork comparison addresses this partially. Lower to P3. Note Microsoft partnership context for future update cycle. |
| Gap 8: Paperclip Orchestration | **Keep** | Still unaddressed. Keep as Medium priority. |
| Gap 9: Price Justification | **Keep** | Still unaddressed. Align timeline with pricing launch. |

Add 3 new gaps from audit findings:

| New Gap | Priority | Source | Detail |
|---------|----------|--------|--------|
| **Gap 10: Listicle Presence** | Critical | Audit OS-1 | Soleur appears on zero "best AI agent" or "solo founder tools" listicles. Target: TLDL, Entrepreneur, Taskade, o-mega.ai, AIMultiple. This is off-site strategy but must be tracked in content strategy. |
| **Gap 11: About/Founder Page** | High | Audit C5, SEO P3-9 | No About page exists. Significant E-E-A-T gap flagged by both AEO and SEO audits. Founder credentials and social links needed for expertise signals. |
| **Gap 12: External Citations on Non-Blog Pages** | High | Audit C1 | 12 of 15 pages have zero external citations. Stark binary split: blog is citation-rich, everything else has none. Add 1-2 authoritative citations per catalog page. |

#### 1.3 Update Content Pillars

Update the pillar tables to reflect what has been published vs. what remains:

**Pillar 1: Category Definition**

| Piece | Status | Notes |
|-------|--------|-------|
| What Is Company-as-a-Service? | **PUBLISHED** | SAP 5.0/5.0, FAQ JSON-LD present |
| The Billion-Dollar Solo Company | Not started | Rename to "One-Person Billion-Dollar Company: The Complete Guide" per audit keyword research |
| Autopilot vs. Decision-Maker | Not started | Audit confirms priority (P2-3, score 16/20) |
| Company-as-a-Service vs SaaS | Not started | Audit P3-3 |

**Pillar 2: Methodology**

| Piece | Status | Notes |
|-------|--------|-------|
| Why Most Agentic Tools Plateau | **PUBLISHED** | SAP 4.8/5.0. Missing FAQ JSON-LD (P1 fix). Partially addresses Gaps 1 and 4. |
| Vibe Coding vs Agentic Engineering | Not started | **Highest audit priority for new content** (P2-1, score 18/20). Renamed from "Agentic Engineering: Beyond Vibe Coding" to better target the search query "vibe coding vs agentic engineering". Same article, updated title. |
| Knowledge Compounding in AI Development | Not started | Addresses Gap 1 |
| Compound Engineering: How Every Project Makes the Next One Easier | Not started | Audit P3-4 |

**Pillar 3: Competitive Positioning**

| Piece | Status | Notes |
|-------|--------|-------|
| Soleur vs. Anthropic Cowork | **PUBLISHED** | FAQ JSON-LD present. May need "(2026)" in title per audit I9. |
| Soleur vs. Cursor | **PUBLISHED** | Published 2026-03-19. Addresses Automations + Marketplace. |
| Soleur vs. Notion Custom Agents | **PUBLISHED** | Published 2026-03-17. |
| AI Agents for Solo Founders: The Definitive Guide | Not started | **Highest audit priority for new pillar** (P2-2, score 18/20). Captures "solopreneur AI tools 2026" high-volume keyword. |
| Soleur vs. Polsia | Not started | Audit P2-3, score 16/20 |
| Best Claude Code Plugins for Solo Founders | Not started | Audit P3-2 |

**Pillar 4: Proof and Tutorials**

| Piece | Status | Notes |
|-------|--------|-------|
| 5 Case Studies | **PUBLISHED** | Business validation, legal docs, ops, brand guide, competitive intel. All lack FAQ sections (P1 fix). |
| About/Founder Page | Not started | Gap 11. Low effort, high E-E-A-T impact. |

#### 1.4 Replace Calendar with Rolling Quarterly Calendar

Replace the stale 4-week calendar with a rolling quarterly calendar:

**Month 1 (March 20 - April 20, 2026): Technical Fixes + First New Article**

| Week | Task | Hours | Output |
|------|------|-------|--------|
| Mar 20-26 | P1 technical fixes: FAQ JSON-LD on agents page + "Why Tools Plateau", FAQ sections on 5 case studies, remove "plugin" from meta descriptions, Vision page H1 rewrite, add `updated` frontmatter to blog posts, add "open source" + "solopreneur" to homepage | 6-8 | All P1 technical fixes deployed |
| Mar 27-Apr 2 | Write "Vibe Coding vs Agentic Engineering" article (audit P2-1, score 18/20) | 6-8 | Draft + publish |
| Apr 3-9 | Add external citations to 5+ catalog pages (Gap 12). Add FAQ sections to Skills, Getting Started, Community pages (audit P2-7). | 4-6 | AEO score improvement |
| Apr 10-16 | Write About/Founder page (Gap 11). Add definition paragraphs to Agents and Skills pages (audit P2-6). | 3-4 | E-E-A-T + AEO improvements |
| Apr 17-20 | Distribution: share Vibe Coding article on X, Discord, IndieHackers. Review analytics. | 2-3 | Distribution complete |

**Month 2 (April 21 - May 20, 2026): Pillar Content + Comparisons**

| Week | Task | Hours | Output |
|------|------|-------|--------|
| Apr 21-27 | Write "AI Agents for Solo Founders: The Definitive Guide" (audit P2-2, score 18/20) | 8-10 | Pillar article draft |
| Apr 28-May 4 | Publish AI Agents guide. Begin "Soleur vs Polsia" comparison (audit P2-3). | 6-8 | 1 pillar + 1 comparison draft |
| May 5-11 | Publish Soleur vs Polsia. Add internal cross-links between case studies (audit P2-8). | 4-6 | Comparison live, cross-links added |
| May 12-18 | Write "One-Person Billion-Dollar Company" (P3-1, high social distribution potential) | 6-8 | Draft |
| May 19-20 | Distribution + analytics review | 2 | Status check |

**Month 3 (May 21 - June 20, 2026): Long-Tail + Off-Site**

| Week | Task | Hours | Output |
|------|------|-------|--------|
| May 21-27 | Publish "One-Person Billion-Dollar Company". Begin off-site listicle outreach (Gap 10, audit OS-1). | 4-6 | Article live + outreach started |
| May 28-Jun 3 | Write "Best Claude Code Plugins for Solo Founders" (audit P3-2). Continue outreach. | 6-8 | Listicle article draft |
| Jun 4-10 | Write "Company-as-a-Service vs SaaS" (audit P3-3). | 6-8 | Draft |
| Jun 11-17 | Add page-specific OG images for pillar blog posts (audit P2-10). Publish remaining drafts. | 4-6 | OG images + articles live |
| Jun 18-20 | Full SEO/AEO re-audit. Compare against 2026-03-17 baselines. Plan next quarter. | 3-4 | Q2 audit report |

#### 1.5 Update Content Quality Standards

Add to the AEO checklist:

```markdown
- [ ] `updated` frontmatter field set if content has been revised since initial publication
- [ ] Visible "Last Updated" date displayed to users (if `updated` is set)
- [ ] At least 1 external citation on every page (including catalog pages)
```

#### 1.6 Update Sources

Add sources consulted footer referencing the 2026-03-17 audit reports.

### Phase 2: Update `marketing-strategy.md`

#### 2.1 Update frontmatter

**Note:** Fix stale `depends_on` paths (references `knowledge-base/overview/` which don't exist). Also fix 3 internal body text references to `knowledge-base/overview/content-strategy.md`.

```yaml
last_updated: 2026-03-20
last_reviewed: 2026-03-20
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/product/business-validation.md
  - knowledge-base/marketing/content-strategy.md
  - knowledge-base/product/pricing-strategy.md
```

**Warning:** `scripts/weekly-analytics.sh` reads growth target phases from marketing-strategy.md lines 335-339. If structural changes shift these lines, the weekly analytics CI workflow will break. After editing, verify the WoW growth target table position or update the script's line references.

#### 2.2 Refresh Executive Summary

Replace stale metrics:

| Line | Old | New |
|------|-----|-----|
| Content score | "Content score 2/10" | "Content score 6/10 (8 blog posts, 3 comparison articles, 5 case studies. Catalog pages still weak on AEO.)" |
| AEO | "AEO 1.6/10" | "AEO 6.8/10 (68/100, Grade C+). Blog content scores 80%, catalog pages 40%." |
| Blog infrastructure | "No blog infrastructure" | "Blog infrastructure live (Eleventy collection, templates, JSON-LD, sitemap)" |
| Comparison content | "No comparison content" (implied) | "3 comparison articles published (Cowork, Cursor, Notion Custom Agents)" |

#### 2.3 Refresh "What Exists and Works" table

Update rows:

| Area | Old Status | New Status |
|------|-----------|------------|
| Content plan | "Zero executed" | "7+ pieces executed: 3 pillar articles, 5 case studies, 3 comparison pages" |
| Content marketing | "0% informational content. No blog. No articles." | "8 blog posts published. 3 pillar articles. 5 case studies. Blog infrastructure complete." |
| AEO | "FAQ schemas absent" | "FAQ schemas on homepage, CaaS article, Cowork comparison (3/15 pages). AEO score 68/100." |

#### 2.4 Refresh "What Is Broken or Missing" table

Update rows:

| Area | Old Status | New Status/Priority |
|------|-----------|-----------|
| Content marketing | Critical | **Partially resolved.** Blog exists. 8 posts published. Remaining: catalog pages weak on AEO, no FAQ JSON-LD on most pages. |
| Keyword presence | Critical | **Partially resolved.** Keywords present in blog content. Catalog pages (agents, skills, vision, community) still weak. |
| Blog infrastructure | Critical | **RESOLVED.** Eleventy collection live. |
| Social proof | High | **Partially resolved.** 5 case studies published. Still need: testimonials from external users. |
| AEO | High | **Partially resolved.** FAQ schemas on 3 pages. Score 68/100. Gap: 12/15 pages lack FAQ. |
| Comparison content | Medium | **Partially resolved.** 3 comparisons published. Remaining: Polsia, Paperclip, best-of listicle. |

Add new broken/missing items:

| Area | Status | Priority |
|------|--------|----------|
| Listicle presence | Zero appearances on third-party "best AI agent" lists | Critical |
| About/Founder page | Does not exist. E-E-A-T gap. | High |
| dateModified signals | No blog post has `updated` frontmatter. Google freshness assessment blocked. | High |
| Page-specific OG images | Single generic OG image on all pages. Low social CTR. | Medium |

#### 2.5 Update Phased Execution Plan

| Phase | Old Status | New Status |
|-------|-----------|------------|
| Phase 0: Foundation | In progress | **COMPLETE.** Blog infrastructure built. Keywords added to pages. FAQ schema on homepage. llms.txt rewritten. |
| Phase 1: Category Creation | Not started | **IN PROGRESS.** CaaS pillar published. "Why Tools Plateau" published. Cowork comparison published. 3 of 4 actions complete. Remaining: validation outreach scaling. |
| Phase 2: Validation + Positioning | Not started | **PARTIALLY STARTED.** Cursor and Polsia comparisons published. Methodology article ("Vibe Coding vs Agentic Engineering") is next priority. |
| Phase 3: Proof + Scale | Not started | **EARLY PROGRESS.** 5 case studies published. Knowledge Compounding article still needed. |

#### 2.6 Update KPIs with Current Baselines

Add "Current (2026-03-20)" column to the Validation Phase metrics table:

| Metric | Target | Current (2026-03-20) |
|--------|--------|---------------------|
| Pillar articles published | 4+ | 3 (CaaS, Why Tools Plateau, Cowork comparison) |
| AEO citation rate | Cited in 2+ AI search results | Unknown (baseline not yet established) |
| Content score | N/A (was 2/10) | 6/10 |
| AEO score | N/A (was 1.6/10) | 6.8/10 (68/100, C+) |

#### 2.7 Update Content Strategy Summary Section

Update the "Content Gaps (Ranked)" list and "Pillar Content (Priority Order)" table to align with the updated content-strategy.md (Phase 1 changes). Reference the updated content-strategy.md rather than duplicating the full gap analysis.

### Phase 3: Update `seo-refresh-queue.md`

#### 3.1 Update frontmatter

**Note:** Fix stale `depends_on` paths (same issue as content-strategy.md):

```yaml
last_updated: 2026-03-20
last_reviewed: 2026-03-20
depends_on:
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/marketing/content-strategy.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-seo-audit.md
```

#### 3.2 Mark completed items

In Priority 1 (Stale Pages):
- Homepage FAQ schema: **DONE** (6 FAQ items with FAQPage JSON-LD)
- Agents page H1: **DONE** (now "Soleur AI Agents")
- Skills page H1: **DONE** (now "Agentic Engineering Skills")
- Getting Started "What is Soleur?" paragraph: **DONE**
- llms.txt rewrite: **DONE** (updated counts, platform positioning)

In Priority 2 (New Pages):
- Comparison pages created: Cowork, Cursor, Notion Custom Agents — **DONE**
- CaaS pillar article: **DONE**
- Articles index: **DONE**

#### 3.3 Add new items from audit

Add to Priority 1:
- FAQ JSON-LD on agents page (has FAQ content but no schema)
- FAQ JSON-LD on "Why Tools Plateau" (uses H3 headings, no schema)
- Remove "plugin" from homepage and getting-started meta descriptions
- Vision page H1 rewrite (currently "Vision" — zero keyword value)
- Add `updated` frontmatter to all blog posts
- Add "open source" and "solopreneur" to homepage

Add to Priority 2:
- FAQ sections on 5 case studies
- External citations on all non-blog pages
- About/Founder page
- Page-specific OG images for pillar blog posts
- Definition paragraphs on Agents and Skills pages

#### 3.4 Update competitor monitoring

Update Current Status column with 2026-03-17 data. Add entries for new competitor developments since 2026-03-12.

### Phase 4: Consistency Verification

After all three documents are updated:

- [ ] Verify `depends_on` chains reference correct file paths
- [ ] Cross-check quarterly calendar dates against campaign-calendar.md
- [ ] Confirm pillar table status in content-strategy.md matches what marketing-strategy.md references
- [ ] Verify no stale metrics remain in either document
- [ ] Run `grep -rn "0% informational\|No blog\|Zero executed\|1\.6/10\|Content score 2/10\|Does not exist.*Cannot publish" knowledge-base/marketing/` — should return zero matches

## Acceptance Criteria

- [ ] `content-strategy.md` has `last_updated: 2026-03-20` and references 2026-03-17 audit reports in `depends_on`
- [ ] Gaps 2 and 6 marked as COMPLETED with publication notes
- [ ] Remaining gaps updated with 2026-03-17 audit data (keyword volumes, scores)
- [ ] 3 new gaps added (listicle presence, About page, external citations)
- [ ] 4-week calendar replaced with rolling quarterly calendar (March-June 2026)
- [ ] Content pillar tables show published/not-started status for each piece
- [ ] AEO checklist updated with `updated` frontmatter and external citation requirements
- [ ] `marketing-strategy.md` has `last_updated: 2026-03-20`
- [ ] Executive summary metrics reflect current state (AEO 68/100, 8 blog posts, etc.)
- [ ] "What Exists" and "What Is Broken" tables updated
- [ ] Phased plan shows Phase 0 complete, Phase 1 in progress
- [ ] KPIs include current baseline values
- [ ] `seo-refresh-queue.md` has `last_updated: 2026-03-20` and corrected `depends_on` paths
- [ ] `seo-refresh-queue.md` marks completed items and adds audit findings
- [ ] AEO checklist in content-strategy.md updated with `updated` frontmatter and external citation requirements
- [ ] Sources footer in content-strategy.md references 2026-03-17 audit reports
- [ ] Completed gaps use `[COMPLETED YYYY-MM-DD]` inline tags matching existing `[NEW/UPDATED]` convention
- [ ] All `depends_on` paths across all 3 files point to actual filesystem locations (no `knowledge-base/overview/` references)
- [ ] No stale claims remain: grep for "0% informational", "No blog", "Zero executed", "1.6/10", "Content score 2/10", "Does not exist" returns zero matches
- [ ] `scripts/weekly-analytics.sh` growth target line references verified after marketing-strategy.md structural changes

## References

- Issue: #661 (Growth Audit 2026-03-17)
- PR: #966 (draft)
- Brainstorm: `knowledge-base/brainstorms/2026-03-20-seo-aeo-content-plan-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-seo-aeo-content-plan/spec.md`
- Audit reports:
  - `knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-plan.md`
  - `knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-audit.md`
  - `knowledge-base/marketing/audits/soleur-ai/2026-03-17-aeo-audit.md`
  - `knowledge-base/marketing/audits/soleur-ai/2026-03-17-seo-audit.md`
- Files to modify:
  - `knowledge-base/marketing/content-strategy.md`
  - `knowledge-base/marketing/marketing-strategy.md`
  - `knowledge-base/marketing/seo-refresh-queue.md`
