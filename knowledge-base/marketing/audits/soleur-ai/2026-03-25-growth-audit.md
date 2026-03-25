# Growth Audit Report — 2026-03-25

**Site:** Soleur | **URL:** https://soleur.ai
**Date:** 2026-03-25 | **Auditor:** Automated (Claude Sonnet 4.6)
**Previous audit:** 2026-03-23 | **Audit type:** Weekly growth audit

---

## Executive Summary

Traffic reversed sharply in the week of 2026-03-23 (-64% WoW, 10 visitors vs. 28 the prior week), falling well below the Phase 1 target of +15% WoW. The prior week's spike was driven by new content and Discord distribution; the regression suggests one-time traffic events rather than durable organic growth. The "Vibe Coding vs Agentic Engineering" article was distributed on 2026-03-24 and has not yet had time to index or generate search traffic.

AEO score improved to 74/100 (from 68 on 2026-03-17), driven by FAQ additions to case studies and two new high-citation comparison posts. Blog content is strong (average 4.7/5.0 SAP); non-blog catalog pages remain weak (2.8/5.0). The fundamental growth blocker is unchanged: 80–90% of traffic is direct, organic search accounts for ~1 visitor/week, and Soleur has zero third-party listicle presence.

**Content velocity is on track.** The quarterly calendar's Week 1 priorities are substantially complete, and the highest-scored new article (Vibe Coding vs Agentic Engineering) was published on schedule.

---

## 1. Keyword Alignment Analysis

### Pillar 1: Category Definition

| Published Piece | Primary Keyword | Intent | Alignment |
|-----------------|-----------------|--------|-----------|
| What Is Company-as-a-Service? | "company as a service" | Informational | **Strong** — keyword in H1, first paragraph, FAQ, JSON-LD. No competition for this exact term. SAP 5.0. |

**Gap:** "One-Person Billion-Dollar Company" article not yet written. The Amodei/Altman predictions give this keyword cluster high social distribution potential but it remains unpublished.

**Competitor signal:** No competitor has published on "company as a service" as a category definition. The window to own this term remains open.

### Pillar 2: Methodology

| Published Piece | Primary Keyword | Intent | Alignment |
|-----------------|-----------------|--------|-----------|
| Why Most Agentic Engineering Tools Plateau | "agentic engineering", "compound knowledge" | Informational | **Strong** — SAP 4.8/5.0. Karpathy citations, GitHub Spec Kit star count, strong authority signals. |
| Vibe Coding vs Agentic Engineering (2026-03-24) | "vibe coding vs agentic engineering" | Informational | **Strong** — Title directly targets the trending query. Distribution content ready. Not yet indexed. |

**Gap:** "Knowledge Compounding in AI Development" article (Gap 1) still missing. Tanka claims "memory compounding" as their moat. Publishing the Soleur framing first matters.

**Competitor signal:** IBM, The New Stack, and Addy Osmani have published on agentic engineering. Soleur is competing in an increasingly crowded keyword space. The "vibe coding vs agentic engineering" framing is distinctive — no major competitor is using this exact angle.

### Pillar 3: Competitive Positioning

| Published Piece | Primary Keyword | Intent | Alignment |
|-----------------|-----------------|--------|-----------|
| Soleur vs. Anthropic Cowork | "soleur vs cowork", "AI agent platform comparison" | Commercial | **Strong** — FAQ JSON-LD present. Covers Microsoft Copilot Cowork partnership. |
| Soleur vs. Cursor (2026) | "soleur vs cursor", "cursor automations vs soleur" | Commercial | **Strong** — Addresses Automations + Marketplace. Pricing tables. Missing 2 source URLs (see AEO audit). |
| Soleur vs. Notion Custom Agents | "soleur vs notion ai" | Commercial | **Strong** — FAQ, pricing, user count. Missing 2 inline source URLs. |

**Gaps:** Soleur vs. Polsia (P2, Month 2) not started. Given Polsia's delivery pivot to web dashboard (same surface as Soleur's target), this comparison has become P1-equivalent. "Agent Platform vs. AI Organization" position paper also not written.

**Missing comparison:** No "Soleur vs. Paperclip" or "Soleur vs. OpenAI Codex" articles. Paperclip at 14.6k GitHub stars is capturing developer searches for AI company orchestration.

### Pillar 4: Proof and Tutorials

| Published Piece | Primary Keyword | Intent | Alignment |
|-----------------|-----------------|--------|-----------|
| Case Study: Business Validation | "build SaaS with AI", "solo founder workflow" | Transactional | **Moderate** — FAQ sections added. Still lacks external citations for market-rate claims. AEO score 3.3/5.0. |
| Case Study: Legal Document Generation | "legal document automation", "AI legal documents" | Transactional | **Moderate** — FAQ added. EUR 300–500/hour claim uncited. AEO score 3.2/5.0. |
| Case Study: Operations Management | "AI business operations", "AI ops management" | Transactional | **Moderate** — same issues as above. |
| Case Study: Brand Guide Creation | "AI brand guide", "brand strategy automation" | Transactional | **Moderate** — same. |
| Case Study: Competitive Intelligence | "AI competitive intelligence", "market research automation" | Transactional | **Moderate** — Mentions 30+ sources but does not link them. Partial source signal. |

**Critical gap:** About/Founder page (Gap 11) still missing. E-E-A-T signals cap the authority all case studies can earn. Blog posts credit "Jean Deruelle" (corrected in PR #1091) but link only to the homepage.

---

## 2. Search Intent Analysis

| Page | Target Intent | Actual Intent Match | Assessment |
|------|--------------|---------------------|------------|
| Homepage | Navigational + Transactional | Navigational — "Build a Billion-Dollar Company. Alone." is pure brand | **Acceptable** for homepage. H2s and body copy have been updated with keywords. |
| What Is CaaS? | Informational | Informational — exhaustive definition, statistics, FAQ | **Match** |
| Why Tools Plateau | Informational | Informational — methodology explanation, lifecycle | **Match** |
| Vibe Coding vs Agentic Engineering | Informational | Informational — structured comparison, clear winner framing | **Match** |
| Soleur vs. Cursor | Commercial investigation | Commercial — pricing table, feature matrix, clear CTA | **Match** |
| Soleur vs. Cowork | Commercial investigation | Commercial — same structure | **Match** |
| Soleur vs. Notion | Commercial investigation | Commercial — same structure | **Match** |
| Case Studies | Transactional | Informational/Proof — "here's what we built" narrative | **Partial mismatch** — case studies should include transactional CTA ("Try this yourself") at the end |
| Agents page | Commercial investigation | Informational catalog | **Mismatch** — searchers for "AI agents for solo founders" want evaluation help, not a raw list. Needs introductory positioning and a CTA. |
| Skills page | Commercial investigation | Informational catalog | **Mismatch** — same as Agents page. |

**Recommendation:** Add a brief "Who this is for" paragraph and a CTA to the Agents and Skills catalog pages. These pages rank for evaluation-intent queries but deliver a catalog experience.

---

## 3. Readability and Brand Voice Assessment

### Compliant Content

- **What Is CaaS?** — Exemplary brand voice. Declarative statements, concrete numbers, audacious framing. No prohibited terms.
- **Why Tools Plateau** — Strong brand voice. Technical precision without over-explanation.
- **Vibe Coding vs Agentic Engineering** (distribution content) — Voice is correct. Discord post is direct and builder-to-builder. X thread follows hook-first format. No hedging detected.
- **Comparison pages** — Direct, honest, data-driven. Correctly acknowledge competitor strengths without FUD.

### Issues Detected

1. **Homepage meta description** still contains "plugin" — prohibited in public-facing content per brand guide (exception for literal CLI commands only). Flagged in seo-refresh-queue.md since 2026-03-17 but not yet fixed.

2. **Getting Started meta description** — "Install the Soleur Claude Code plugin..." uses prohibited "plugin" framing. Flagged since 2026-03-17.

3. **Case studies** — Narrative is proof-focused (good) but CTAs are weak. "Try this yourself" or "Start building" language would align with the transactional intent of the pages and brand voice ("Build at scale" > "Try building at scale").

4. **Agents and Skills pages** — Catalog presentation without positioning. The brand voice requires leading with what becomes possible, not just listing the inventory.

5. **Agent count in brand guide positioning section** — Brand guide says "61 agents, 59 skills" (checked in `brand-guide.md:26`). The AEO audit noted the site was updated to "63 agents" as of the 2026-03-23 audit. The brand guide positioning section needs updating to reflect current counts.

---

## 4. Content Velocity Tracking

### Quarterly Calendar Status (2026-03-25)

| Week | Task | Status | Notes |
|------|------|--------|-------|
| Mar 20–26 | P1 technical fixes: FAQ JSON-LD, remove "plugin" from meta, Vision page H1, dateModified signals | **Partial** | FAQ JSON-LD on case studies: done. "Plugin" in meta descriptions: NOT done. Vision H1: status unknown. `updated` frontmatter: NOT done. |
| Mar 20–26 | Add "open source" + "solopreneur" to homepage | **Status unknown** | Not verifiable from local files. Needs site build check. |
| Mar 27–Apr 2 | Vibe Coding vs Agentic Engineering — write and publish | **On track** | Distribution content ready as of 2026-03-24. Article needs to be confirmed published at `/blog/vibe-coding-vs-agentic-engineering/`. |
| Apr 3–9 | External citations on 5+ catalog pages (Gap 12) | **Not started** | Scheduled for next week. |
| Apr 10–16 | About/Founder page (Gap 11) | **Not started** | Scheduled for Apr 10–16. |

**Velocity assessment:** 1 major piece published per week (Cowork: Mar 16, Notion: Mar 17, Cursor: Mar 19, Vibe Coding: Mar 24). This is at the high end of the planned 1/week cadence. Sustaining this rate will require the Apr 3–9 and Apr 10–16 weeks to deliver despite shifting from content creation to technical fixes.

### Published Content Count

| Pillar | Planned (Month 1) | Published |
|--------|-------------------|-----------|
| Category Definition | 1 | 1 ✓ |
| Methodology | 2 | 2 ✓ (Plateau + Vibe Coding) |
| Competitive Positioning | 3 | 3 ✓ (Cowork, Cursor, Notion) |
| Proof/Tutorials | 5 case studies + About page | 5 case studies ✓, About page ✗ |

---

## 5. Organic Discovery Gap

**Current state:** ~1 organic visitor/week from Google (10% of 10 = ~1). 80% direct. Discord and GitHub are the only distribution channels producing measurable results.

**Root causes:**

1. **No backlinks** — Zero third-party sites link to soleur.ai. Backlinks are the primary ranking signal. Without them, even perfectly optimized content will not rank.

2. **No listicle presence** — Soleur appears on zero "best AI agent tools," "solo founder AI stack," or "Claude Code plugins" lists. Competitors (Arahi, Lindy, Make) appear on multiple. This is the single largest off-page gap (Content Gap 10).

3. **Meta tags may not be rendering in production** — The 2026-03-23 SEO audit found OG tags and canonical URLs absent in fetched production HTML. If confirmed, social sharing produces generic previews, reducing CTR from all social distribution. This is a P0 technical issue that undermines every distribution effort.

4. **Domain authority near zero** — New domain (registered late 2025 based on earliest audit dates). Google's trust signals accumulate over time; content published today may take 3–6 months to rank.

5. **No Product Hunt listing** — Product Hunt drives initial discovery and backlinks for developer tools. Zero launches detected.

**Highest-leverage organic actions:**

1. **Verify meta tag rendering** (P0) — If OG tags are absent in production, fix immediately. Every social share is under-performing.
2. **Product Hunt launch** — Single highest-ROI off-page action. One successful launch can generate 50–200 backlinks and thousands of direct visitors.
3. **Submit to GitHub Awesome Lists** — "awesome-claude-code", "awesome-ai-agents", "awesome-solo-founder-tools". Passive backlink generation that compounds.
4. **Publish "Vibe Coding vs Agentic Engineering"** — If not yet live, publish immediately. Trending keyword. Karpathy's audience is actively searching this term.
5. **Listicle outreach** — Email TLDR Newsletter, Entrepreneur.com, AIMultiple with a one-paragraph pitch. These sites have existing SEO authority; a single mention delivers more ranking signal than 10 new blog posts.

---

## 6. Priority Action Items — Week of 2026-03-25

| Priority | Action | Impact | Effort | Owner |
|----------|--------|--------|--------|-------|
| **P0** | Verify OG/canonical tags render in production HTML (build locally, inspect `_site/index.html`) | HIGH — every social share is under-performing without this | 30 min | Founder |
| **P1** | Confirm "Vibe Coding vs Agentic Engineering" is live at `/blog/vibe-coding-vs-agentic-engineering/` and indexed | HIGH — highest-scored article in Month 1 calendar | 15 min | Founder |
| **P1** | Remove "plugin" from homepage and Getting Started meta descriptions (seo-refresh-queue.md items 1.1 + 1.4) | MEDIUM — brand compliance + SEO | 30 min | Founder |
| **P1** | Add "open source" and "solopreneur" keywords to homepage hero section if not done | MEDIUM — two high-volume keywords missing from highest-traffic page | 30 min | Founder |
| **P2** | Begin "AI Agents for Solo Founders: The Definitive Guide" outline | HIGH — audit P2-2, score 18/20, targets "solopreneur AI tools 2026" high-volume keyword | 2 hrs | Founder |

---

## 7. Competitive Landscape Update

No new material competitor developments detected since the 2026-03-23 audit. Monitoring continues:

- **Polsia** — $1.5M ARR, web dashboard delivery confirmed. "Soleur vs. Polsia" comparison urgency elevated given delivery surface parity.
- **Paperclip** — 14.6k GitHub stars. Clipmart feature (pre-built company templates) still pending. Complementary positioning opportunity remains unpublished.
- **Notion Custom Agents** — Post-beta pricing starts May 3, 2026 ($10/1,000 credits). Update to "Soleur vs. Notion" comparison needed before that date.
- **OpenAI Codex** — Codex Security agent (launched Mar 6) represents first non-coding domain expansion. If additional business domains are added, this becomes a Tier 1 threat.

---

## 8. AEO Score Projection

| Metric | 2026-02-19 | 2026-03-17 | 2026-03-23 | 2026-03-25 (est.) |
|--------|:----------:|:----------:|:----------:|:-----------------:|
| AEO Score | — | 68/100 | 74/100 | **74–76/100** |
| Blog SAP avg | — | ~4.5 | 4.7 | ~4.8 (Vibe Coding adds) |
| Non-blog SAP avg | — | ~2.0 | 2.8 | **2.8** (no changes yet) |
| Pages with external citations | ~4 | ~6 | ~8 | ~8 (no new pages) |
| Pages with FAQ JSON-LD | 1 | 3 | 8 | ~8 |

Projected improvement to 78+ requires completing Gap 12 (external citations on catalog pages). This is scheduled for Apr 3–9 and remains the next highest-impact AEO action.

---

## Open Issues Requiring Tracking

The following pre-existing issues do not have GitHub issues assigned. They should be filed before the next sprint:

1. Meta tags not rendering in production (P0 SEO bug) — SEO audit 2026-03-23, Issue #1
2. Feed.xml appearing in sitemap (P2 SEO issue) — SEO audit 2026-03-23, Issue #6
3. Case studies missing Atom feed entries (P1 SEO issue) — SEO audit 2026-03-23, Issue #5
4. Author URL pointing to homepage instead of About page (P1 E-E-A-T issue) — SEO audit 2026-03-23, Issue #3
5. "Plugin" in meta descriptions (P1 brand compliance) — seo-refresh-queue.md, unfixed since 2026-03-17

---

_Generated: 2026-03-25. Sources: analytics/2026-03-23-weekly-analytics.md, analytics/trend-summary.md, audits/soleur-ai/2026-03-23-aeo-audit.md, audits/soleur-ai/2026-03-23-seo-audit.md, content-strategy.md (2026-03-22), brand-guide.md (2026-03-22), seo-refresh-queue.md (2026-03-20), distribution-content/2026-03-24-vibe-coding-vs-agentic-engineering.md._
