# SEO/AEO/GEO Content Plan Alignment Brainstorm

**Date:** 2026-03-20
**Issue:** #661 (Growth Audit 2026-03-17)
**Participants:** Founder, CMO (domain assessment)

---

## What We're Building

A layered update to two living strategy documents -- `content-strategy.md` and `marketing-strategy.md` -- that reconciles the 2026-03-17 growth audit findings with existing strategy, producing a rolling quarterly content calendar (March-June 2026) with clear execution priorities.

### Deliverables

1. **Updated `content-strategy.md`**: Mark completed gaps, update remaining gaps with fresh audit data, add new gaps from the audit, replace stale 4-week calendar with rolling quarterly calendar
2. **Updated `marketing-strategy.md`**: Refresh current state assessment with actual metrics, update phased plan to reflect progress
3. **Execution plan**: Concrete file changes for P1 technical SEO/AEO fixes, article briefs for highest-priority new content

---

## Why This Approach

### Approach chosen: Layered Update (A)

- Preserves institutional context and the evolution history of content gaps
- Both strategy docs stay as separate concerns (marketing-strategy.md is strategic, content-strategy.md is tactical)
- Incremental updates are easier to review than clean rewrites
- The quarterly calendar provides a longer planning horizon than the audit's 6-week timeline

### Approaches rejected

- **Clean Rewrite (B):** Risks losing nuance from earlier competitive analysis (Paperclip, Copilot Cowork partnerships, Tanka memory compounding threat)
- **Unified Document (C):** Would create an unwieldy single doc. Current separation works well for different review cadences

---

## Key Decisions

### 1. Gap Status Updates

Based on comparing the original content strategy (2026-03-12) against what now exists:

| Gap | Original Status | Current Status | Action |
|-----|----------------|----------------|--------|
| Gap 1: Cross-Domain Compounding | Critical, unaddressed | Partially addressed in "Why Tools Plateau" blog post | Update: narrow to dedicated pillar article |
| Gap 2: CaaS Category Definition | Critical, unaddressed | COMPLETED -- "What Is Company-as-a-Service?" article published | Mark complete |
| Gap 3: IDE Positioning | High, unaddressed | Partially addressed -- Cowork comparison exists, Cursor comparison exists | Update: note what's done, focus on "Agent Platform vs. AI Organization" positioning |
| Gap 4: Engineering-in-Context | High, unaddressed | Partially addressed in "Why Tools Plateau" | Update: "Vibe Coding vs Agentic Engineering" article is the priority execution |
| Gap 5: Autopilot vs Decision-Maker | Critical, unaddressed | Partially addressed in Polsia comparison | Update: narrow to dedicated "Soleur vs Polsia" comparison page |
| Gap 6: Cursor Agent Platform | Critical, unaddressed | COMPLETED -- "Soleur vs Cursor" comparison published | Mark complete |
| Gap 7: Copilot Cowork + Anthropic | High, unaddressed | Partially addressed in Cowork comparison | Update: note partnership context, lower priority |
| Gap 8: Paperclip Orchestration | Medium, unaddressed | Still unaddressed | Keep as-is |
| Gap 9: Price Justification | Medium, unaddressed | Still unaddressed | Keep as-is, align with pricing timeline |

### 2. New Gaps from 2026-03-17 Audit

| New Gap | Priority | Source |
|---------|----------|--------|
| Listicle presence (zero appearances on "best AI agent" lists) | Critical | Content plan OS-1 |
| About/Founder page (E-E-A-T gap) | High | AEO audit C5, SEO audit recommendation 9 |
| External citations on non-blog pages (12/15 pages have zero) | High | AEO audit C1 |

### 3. P1 Technical Fixes (from audit)

These are implementation-ready and should go into the execution plan:

- P1-1: Add JSON-LD FAQPage to agents page + "Why Tools Plateau" blog post
- P1-2: Add FAQ sections + JSON-LD to all 5 case studies
- P1-3: Remove "plugin" from homepage and getting-started meta descriptions
- P1-4: Rewrite Vision page H1
- P1-5: Add `updated` frontmatter and "Last Updated" display to blog posts
- P1-6: Add "open source" and "solopreneur" to homepage

### 4. Priority New Content (from audit + strategy alignment)

| Article | Content Strategy Pillar | Audit Priority | Quarter Position |
|---------|------------------------|----------------|-----------------|
| "Vibe Coding vs Agentic Engineering" | Pillar 2: Methodology | P2-1 (score: 18/20) | Month 1 |
| "AI Agents for Solo Founders: The Definitive Guide" | Pillar 3: Competitive | P2-2 (score: 18/20) | Month 1-2 |
| "Soleur vs Polsia" | Pillar 3: Competitive | P2-3 (score: 16/20) | Month 2 |
| About/Founder page | Pillar 4: Proof | AEO C5 | Month 1 (low effort) |

### 5. Marketing Strategy Updates

The "Current State Assessment" section is significantly stale. Key refreshes:

| Metric | Old Value (2026-03-13) | Current Value (2026-03-20) |
|--------|----------------------|--------------------------|
| Content marketing | "0% informational content. No blog." | 8 blog posts published (3 pillars + 5 case studies) |
| Blog infrastructure | "Does not exist" | Eleventy blog collection live with templates, JSON-LD, sitemap |
| AEO score | "1.6/10" | 68/100 (C+) per AEO audit |
| Comparison content | "No 'Soleur vs X' pages" | 3 comparison articles (Cowork, Cursor, Notion Custom Agents) |
| Case studies | "No case studies" | 5 case studies published |
| Keyword presence | "Zero target keywords in body copy" | Primary keywords present in blog content; catalog pages still weak |
| FAQ schemas | "Absent" | Present on homepage, CaaS article, Cowork comparison (3/15 pages) |
| Content plan | "Zero executed" | 7+ pieces from original plan executed |

---

## Open Questions

1. **Off-site strategy timing:** The audit flags zero listicle presence as critical. Outreach to TLDL, Entrepreneur, Taskade etc. requires a different workflow than on-site content. Should this be a separate brainstorm/plan, or integrated into the quarterly calendar?

2. **Content velocity:** With one founder, how many new articles per month is realistic? The audit suggests 4 new articles in 5 weeks. The original strategy budgeted 8-12 hours/week for content.

3. **Campaign calendar alignment:** The existing campaign-calendar.md tracks distribution of published content. Should the updated content-strategy.md reference the campaign calendar, or should the calendar be updated as part of this same pass?

---

## Capability Gaps

None identified. All work is document updates and content creation -- capabilities that exist in the current tooling (growth-strategist for keyword research, content-writer for articles, seo-aeo-analyst for audits).
