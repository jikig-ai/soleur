---
last_updated: 2026-03-22
last_reviewed: 2026-03-22
review_cadence: quarterly
owner: CMO
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/product/business-validation.md
  - knowledge-base/marketing/content-strategy.md
  - knowledge-base/product/pricing-strategy.md
---

# Soleur Marketing Strategy

## Executive Summary

Soleur is the Company-as-a-Service platform -- 60+ agents, 60+ skills, 3 commands -- built for solo founders who refuse to accept that scale requires headcount. The product is mature (420+ merged PRs, daily dogfooding across 8 domains). The marketing is not.

**Current state:** Strong brand identity, growing content foundation. Content score 6/10 (8 blog posts, 3 comparison articles, 5 case studies). AEO 6.8/10 (68/100, Grade C+) -- blog content scores 80%, catalog pages 40%. Blog infrastructure live (Eleventy collection, templates, JSON-LD, sitemap). 89% direct traffic -- organic search discovery still near-zero. Zero third-party listicle appearances.

**Strategic imperative:** The business validation verdict is PIVOT -- pause feature development and source 10 solo founders for problem interviews. Marketing exists to support that pivot, not to generate vanity traffic. Every marketing action must serve one of two goals: (1) find and recruit validation participants, or (2) establish category authority for "Company-as-a-Service" before competitors define the term differently.

> **[2026-03-22 Business Validation Review -- Executive Summary Update]** The pivot is now two-dimensional: thesis validated (problem resonates with 5+ founders), delivery invalidated (CLI plugin rejected in favor of web/mobile access). The strategic imperative gains a third goal: (3) position Soleur as a platform, not a plugin, across all marketing surfaces. Channel strategy, ICP, and product-led distribution assumptions require revision. The category authority goal is more urgent -- founders confirmed the pain but expect a standalone product, and competitors like Polsia already deliver via web.

**Competitive context:** The window is narrowing. Anthropic Cowork now covers 6+ domains with first-party plugins. Notion 3.3 shipped Custom Agents. Tanka claims memory compounding. The differentiation axis is not domain coverage -- it is cross-domain orchestration with compounding institutional memory. Marketing must make this moat visible and understood.

**Constraint:** One founder building the product. Marketing capacity is measured in hours per week, not headcount. Every initiative must be high-leverage, compounding, and executable without a team.

---

## Current State Assessment

### What Exists and Works

| Area | Status | Assessment |
|------|--------|------------|
| Brand guide | Complete, reviewed 2026-03-02 | Solar Forge identity is strong and differentiated. Voice is clear. Prohibited terms list exists. |
| Visual identity | Implemented on soleur.ai | Dark mode, gold accents, Cormorant Garamond headlines, sharp corners. Consistent and distinctive. |
| Technical SEO | Strong foundation | JSON-LD (WebSite, WebPage, SoftwareApplication, BlogPosting, FAQPage), OG tags, Twitter cards, canonical URLs, sitemap, llms.txt, Atom feed all present. |
| Blog infrastructure | Live | Eleventy blog collection with templates, JSON-LD Article schema, sitemap inclusion, OG/Twitter meta per post. 8 posts published. |
| Content marketing | 8 posts published | 3 pillar articles (CaaS, Why Tools Plateau, Cowork comparison), 5 case studies, 3 comparison articles (Cowork, Cursor, Notion). AEO score 68/100 (C+). |
| Analytics | Plausible live, CI-automated | Weekly snapshots automated via CI. WoW growth tracking active. 28 visitors/week (2026-03-16). |
| Community channels | Discord + GitHub active | Builder-to-builder engagement. Discord webhook for automated content distribution. |
| Competitive intelligence | Living document, reviewed 2026-03-12 | 16+ competitors across Tiers 0-3. Moats identified. Convergence risks tracked. Battlecards for top 4. |
| Content plan | 7+ pieces executed | 3 pillar articles, 5 case studies, 3 comparison pages published. Content strategy updated 2026-03-20 with quarterly calendar. |

### What Is Broken or Missing

| Area | Status | Priority |
|------|--------|----------|
| Listicle presence | Zero appearances on third-party "best AI agent" lists. Single largest discoverability gap. | Critical |
| AEO on catalog pages | Blog scores 80%, catalog pages 40%. 12/15 pages have zero external citations. 9/15 pages lack FAQ sections. | Critical |
| About/Founder page | Does not exist. E-E-A-T gap flagged by both AEO and SEO audits. | High |
| dateModified signals | No blog post has `updated` frontmatter. Google freshness assessment blocked. | High |
| Social proof (external) | 5 case studies published but no testimonials from external users. | High |
| User validation | 1-2 informal conversations. Need 10+ problem interviews. | High |
| Brand term compliance | "Plugin" still appears in homepage hero subtitle, FAQ texts, llms.txt, Getting Started meta description. | High |
| Pricing | Undecided. Vision page mentions "success tax" but no committed model. | Medium |
| Email / newsletter | Does not exist. No way to capture or nurture leads. | Medium |
| Page-specific OG images | Single generic OG image on all pages. Low social sharing CTR. | Medium |
| Analytics insights | Plausible tracks visits. Weekly snapshots automated via CI. No funnels or conversion metrics yet. | Medium |

---

## Strategic Positioning

### Positioning Statement

For **solo founders building real companies** who are frustrated that AI helps with code but not with the other 70% of running a business, **Soleur** is the **Company-as-a-Service platform** that provides a full AI organization -- 60+ agents across engineering, marketing, legal, operations, product, finance, sales, and support -- with compounding institutional memory. Unlike **Anthropic Cowork Plugins** (stateless, siloed per domain), **Cursor** (engineering-only), or **Notion Custom Agents** (workspace-scoped, no engineering), Soleur orchestrates workflows across every business domain while every decision the founder makes teaches the system, making the 100th session dramatically more productive than the first.

> **[2026-03-22 Business Validation Review]** This positioning statement holds at the message level but requires one delivery-related adjustment. The statement currently implies no delivery mechanism, which is correct -- it focuses on value, not form factor. However, when expanded for specific channels, the positioning must explicitly state web/mobile accessibility. The differentiator against Cowork and Notion should shift from "terminal-first" to "founder-controlled with compounding memory" since the delivery surface is no longer a distinguishing axis once Soleur also ships as a web product.

### Three Validated Moats

These are the structural advantages that competitors cannot replicate by shipping features. All marketing messaging must ladder up to at least one.

1. **Compounding knowledge base.** Cross-domain institutional memory that persists across sessions. The brand guide informs marketing content. The competitive analysis shapes product positioning. The legal audit references the privacy policy. No competitor -- not Cowork, not Notion, not Tanka -- has this across business domains within a terminal-first workflow. **[2026-03-22]** The moat itself is validated by user research -- founders described cross-domain pain unprompted. The "terminal-first workflow" qualifier should be removed in the next rewrite; the compounding knowledge base moat is delivery-agnostic.

2. **Cross-domain coherence.** 60+ agents share context across 8 domains. A decision in product strategy propagates to engineering planning, marketing copy, and legal review. Competitors are either deep in one domain (Cursor, Devin) or broad but stateless across many (Cowork).

3. **Workflow orchestration depth.** The brainstorm-plan-implement-review-compound lifecycle is not a feature -- it is the architecture. Each stage feeds the next with full domain context. Cowork plugins execute individual tasks. Soleur orchestrates business operations.

### Messaging Hierarchy

| Level | Message | Supporting Proof |
|-------|---------|-----------------|
| H1 (Hero) | "Build a Billion-Dollar Company. Alone." | Amodei's 2026 prediction. Soleur's thesis: this is an engineering problem, not science fiction. |
| H2 (Value Prop) | "The Company-as-a-Service Platform" | 60+ agents. 60+ skills. 8 domains. Every department from strategy to shipping. |
| H3 (Differentiator) | "Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, remembers, and self-improves." | Cross-domain coherence. Compounding knowledge base. Workflow orchestration. |
| H3 (Proof Point) | "Every decision teaches the system. Every project starts faster than the last." | Knowledge compounding across sessions. The 100th session is dramatically more productive than the 1st. |
| H3 (Social Proof) | "Designed, built, and shipped by Soleur -- using Soleur." | 420+ merged PRs. Daily dogfooding across all 8 domains. The platform runs itself. |

### Key Objections and Responses

| Objection | Response |
|-----------|----------|
| "Cowork has plugins for those domains." | Cowork plugins are stateless and siloed. They execute individual tasks. Soleur orchestrates workflows across domains with compounding memory. The brand guide informing marketing content informing sales battlecards -- that cross-domain flow does not exist in Cowork. |
| "I already use Cursor/Copilot for engineering." | Soleur is not replacing your IDE. Engineering agents connect engineering work to business context -- brand guide, competitive intelligence, legal review. The value is in the connection, not the duplication. |
| "Why not use separate best-of-breed tools?" | You can. Solo founders do. And every month they start from scratch because the marketing tool does not know about the brand guide, the legal tool does not know about the privacy policy, and the product tool does not know about the competitive landscape. Soleur's knowledge base makes the integration the product. |
| "One person built this. Can I trust it?" | Soleur is open source (Apache-2.0). Inspect every agent, every skill, every line. The platform is designed, built, and shipped using itself -- 420+ PRs of dogfooding across all 8 domains. |
| "What about pricing?" | Currently free and open source. Pricing model under active validation (see pricing-strategy.md). The core will remain open. |

---

## Target Audience

### Ideal Customer Profile

**Firmographics:**

- Solo founders or very small teams (1-3 people)
- Building SaaS products, developer tools, creative businesses, or consulting-turned-product companies
- Pre-revenue through early revenue stage
- Uses AI tools for some business tasks (ChatGPT, Notion AI, etc.) but lacks cross-domain integration
- Technical background is helpful but not required -- the web platform serves both technical and non-technical founders

**Psychographics:**

- Think in terms of businesses, not just products
- Frustrated that AI handles code but not the other 70% of running a company
- Refuse to accept that scale requires headcount
- Already patching together 5+ tools for different business functions
- Value control and transparency (prefer open source, local-first)
- Ambitious -- building toward a real company, not a side project

### Beachhead Segment (Validation Phase)

For the PIVOT validation, narrow to:

- **AI-tool-active solo founders** who use AI for some business tasks but lack an integrated, cross-domain solution
- **IndieHackers / solopreneur community members** actively building products
- **Founders frustrated by context loss** -- using ChatGPT for marketing, a separate tool for legal, another for ops, with no shared memory between them

### Channels to Reach Them

| Channel | Density | Effort | Priority |
|---------|---------|--------|----------|
| Website (app.soleur.ai) | High | Medium | P1 -- primary discovery surface for all founders |
| LinkedIn (personal + company) | Medium | Medium | P1 -- reaches non-technical founders directly |
| X/Twitter solopreneur network | Medium | Medium | P1 -- amplification and thought leadership |
| IndieHackers | Medium | Medium | P2 -- active solopreneur community |
| Claude Code Discord | High | Low | P2 -- technical builders (beachhead) |
| GitHub (issue engagement, plugin discovery) | Medium | Low | P2 -- technical discovery surface |
| Hacker News | High (when triggered) | Low (organic) | P3 -- submit articles, not product launches |
| Reddit (r/ClaudeAI, r/SaaS, r/solopreneur) | Medium | Low | P3 -- respond to relevant threads |

---

## Channel Strategy

### Principle: Organic Before Paid

No paid acquisition until organic channels prove the thesis. The validation phase requires conversations, not impressions. Paid media is a scaling mechanism for proven channels, not a discovery mechanism for unvalidated products.

### Channel 1: Content (Owned)

**Goal:** Establish category authority for "Company-as-a-Service" and capture informational search traffic.

**Priority actions:**

1. Build blog infrastructure (Eleventy collection, article layout, JSON-LD Article schema)
2. Publish category-defining pillar: "What Is Company-as-a-Service?"
3. Publish thought leadership: "The Billion-Dollar Solo Company"
4. Publish methodology piece: "Agentic Engineering: Beyond Vibe Coding"
5. Add "What is Soleur?" paragraph to Getting Started page (single highest-impact low-effort action)
6. Rewrite homepage H1 and hero to include target keywords

**Full content strategy:** See `knowledge-base/marketing/content-strategy.md`.

### Channel 2: Community (Earned)

**Goal:** Build trust with solo founders through direct engagement, recruit validation participants.

**Priority actions:**

1. Active participation in Claude Code Discord -- answer questions, share Soleur workflows, recruit beta testers
2. GitHub engagement -- respond to issues, contribute to related projects, signal competence
3. IndieHackers -- share transparent building updates (revenue: $0, users: 1, agents: 61)
4. X/Twitter -- share insights from building, not product announcements. Thread format: "Here is what I learned building an AI organization for solo founders."

**Tone:** Builder-to-builder. Direct, collaborative, bold (per brand guide Discord channel notes). Share the process, not the product. Demonstrate competence through contribution.

### Channel 3: SEO / AEO (Organic Search)

**Goal:** Capture informational and commercial search traffic for target keywords.

**Priority actions:**

1. Fix keyword vacuum on existing pages (zero target keywords in body copy today)
2. Publish pillar content targeting "company as a service", "agentic engineering", "solo founder AI"
3. Add FAQ schemas to all pages for AI engine consumability
4. Rewrite llms.txt with target keywords and platform positioning
5. Build comparison pages: "Soleur vs Cowork", "Soleur vs Notion Custom Agents"

**Full SEO queue:** See `knowledge-base/marketing/seo-refresh-queue.md`.

### Channel 4: Product-Led (Native)

**Goal:** Let the product itself be the distribution mechanism.

**Priority actions:**

1. Optimize Claude Code plugin registry listing (description, keywords, categories)
2. Ensure `claude plugin install soleur` experience is clean and immediate
3. Build onboarding flow that demonstrates cross-domain value in the first 10 minutes
4. Create "Built with Soleur" showcase starting with soleur.ai itself

---

## Content Strategy Summary

Full details in `knowledge-base/marketing/content-strategy.md` (updated 2026-03-20). Key points:

### Content Gaps (Top 5 by Current Priority)

1. **Listicle presence** (Critical) -- Soleur appears on zero third-party listicles. Single largest discoverability gap. [NEW 2026-03-20]
2. **Cross-domain compounding narrative** (Critical) -- Partially addressed in "Why Tools Plateau" blog post. Dedicated pillar still needed.
3. **Autopilot vs. Decision-Maker** (Critical) -- Polsia at $1.5M ARR. Comparison page and position paper needed.
4. **About/Founder page** (High) -- No About page. E-E-A-T gap. [NEW 2026-03-20]
5. **External citations on catalog pages** (High) -- 12/15 pages have zero citations. [NEW 2026-03-20]

Completed: CaaS category definition (Gap 2), Cursor positioning (Gap 6). See `content-strategy.md` for full 12-gap analysis.

### Pillar Content (Next Priorities)

| # | Title | Type | Status |
|---|-------|------|--------|
| 1 | "What Is Company-as-a-Service?" | Pillar explainer | **PUBLISHED** (SAP 5.0/5.0) |
| 2 | "Why Most Agentic Tools Plateau" | Pillar explainer | **PUBLISHED** (SAP 4.8/5.0) |
| 3 | "Vibe Coding vs Agentic Engineering" | Comparison | Month 1 (audit P2-1, score 18/20) |
| 4 | "AI Agents for Solo Founders" | Pillar guide | Month 1-2 (audit P2-2, score 18/20) |
| 5 | "Soleur vs Polsia" | Comparison | Month 2 (audit P2-3, score 16/20) |

### Blog Infrastructure

~~Prerequisite: build blog infrastructure.~~ **COMPLETE.** Eleventy blog collection live with article templates, JSON-LD BlogPosting schema, automatic sitemap inclusion, OG/Twitter meta, Atom feed.

---

## Phased Execution Plan

### Phase 0: Foundation (Weeks 1-2) -- "Fix the Basics" [COMPLETE as of 2026-03-10]

**Goal:** Establish the minimum infrastructure for content and validation outreach.

| Action | Owner | Effort | Deliverable | Status |
|--------|-------|--------|-------------|--------|
| Build blog infrastructure in Eleventy | Founder | 4-6 hours | Articles section with proper templates, schema, sitemap | **Done** |
| Fix keyword vacuum on existing 5 pages | Founder | 2-3 hours | Target keywords present in H1s, H2s, body copy on all pages | **Done** |
| Rewrite llms.txt with platform positioning | Founder | 30 min | Updated llms.txt with target keywords | **Done** |
| Add "What is Soleur?" paragraph to Getting Started | Founder | 30 min | Context paragraph before install command | **Done** |
| Add FAQ schema to homepage | Founder | 1 hour | Structured data for AI engine consumability | **Done** (6 FAQs with JSON-LD) |
| Draft validation outreach message | Founder | 1 hour | Template for recruiting problem interview participants | **Done** |

**Success criteria:** ~~Blog infrastructure live. All existing pages contain target keywords. llms.txt updated.~~ All met.

### Phase 1: Category Creation (Weeks 3-4) -- "Define the Category" [IN PROGRESS as of 2026-03-20]

**Goal:** Publish the category-defining content and begin validation outreach.

| Action | Owner | Effort | Deliverable | Status |
|--------|-------|--------|-------------|--------|
| Publish "What Is Company-as-a-Service?" | Founder | 6-8 hours | Pillar article live with full SEO | **Done** (SAP 5.0/5.0) |
| Publish "Why Most Agentic Tools Plateau" | Founder | 6-8 hours | Methodology article live | **Done** (SAP 4.8/5.0) |
| Publish Cowork comparison | Founder | 4-6 hours | Comparison page live | **Done** (2026-03-16) |
| Begin validation outreach (target: 10 founders) | Founder | 5-10 hours | Messages sent to Claude Code Discord, GitHub, IndieHackers | In progress |
| Share articles on X/Twitter, IndieHackers, HN | Founder | 2 hours | Distribution across channels | In progress (Discord automated) |

**Success criteria:** ~~2 pillar articles published.~~ 3 published. Outreach to 10+ potential validation participants: in progress.

### Phase 2: Validation + Positioning (Weeks 5-8) -- "Talk to Founders" [PARTIALLY STARTED as of 2026-03-20]

**Goal:** Conduct problem interviews while building competitive positioning content.

| Action | Owner | Effort | Deliverable | Status |
|--------|-------|--------|-------------|--------|
| Conduct 5-10 problem interviews (no demo) | Founder | 10-15 hours | Interview notes, pattern analysis | Not started |
| Publish "Vibe Coding vs Agentic Engineering" | Founder | 6-8 hours | Methodology article live | Month 1 priority (audit P2-1) |
| Publish 3 comparison pages (Cursor, Notion, Polsia) | Founder | 12-18 hours | Comparison pages live | 2 of 3 done (Cursor, Notion). Polsia: Month 2. |
| Guided onboarding with top 5 interviewees | Founder | 10-15 hours | Onboarding sessions, domain usage data | Not started |
| Document analytics insights from Plausible | Founder | 2 hours | Traffic sources, page engagement, conversion paths | CI-automated weekly snapshots active |

**Success criteria:** 5+ problem interviews complete. 3+ founders using Soleur on real projects. 4+ articles published (3 published as of 2026-03-20).

### Phase 3: Proof + Scale (Weeks 9-16) -- "Build Evidence" [EARLY PROGRESS as of 2026-03-20]

**Goal:** Convert validation into social proof and expand content.

| Action | Owner | Effort | Deliverable | Status |
|--------|-------|--------|-------------|--------|
| Publish "Knowledge Compounding" explainer | Founder | 4-6 hours | Concept pillar article live | Not started (Month 2-3) |
| Write case studies | Founder | 4-6 hours | Case studies from real usage | **Done** -- 5 case studies published (2026-03-10) |
| Collect testimonials from validation participants | Founder | 2 hours | 3-5 testimonials for site | Not started |
| Publish agentic company glossary | Founder | 4-6 hours | SEO-rich reference page | Not started |
| Decide pricing model based on validation data | Founder | N/A | Pricing decision informed by user behavior | Not started |
| Add testimonials and social proof to site | Founder | 2 hours | Updated homepage and Getting Started | Not started |

**Success criteria:** Social proof exists. Pricing model decided. 6+ articles published (8 published as of 2026-03-20). ~~First case study live.~~ 5 case studies live.

### Phase 4: Growth (Weeks 17+) -- "Scale What Works"

**Goal:** Double down on channels and content types that proved effective.

| Action | Trigger | Deliverable |
|--------|---------|-------------|
| Launch pricing / paid tier | 50+ active users, 3+ willingness-to-pay signals | Pricing page, onboarding flow |
| Evaluate paid acquisition | Organic channels producing consistent traffic | Test Google Ads on high-intent keywords |
| Build email/newsletter | 100+ site visitors/week | Capture mechanism, nurture sequence |
| Expand comparison content | New competitors emerge or existing ones shift | Updated battlecards, new comparison pages |
| Create video content | Articles prove which topics resonate | YouTube walkthroughs of highest-performing article topics |

**Success criteria:** Revenue model live. Consistent organic traffic growth. Community growing.

---

## KPIs and Success Metrics

### Validation Phase (Weeks 1-8)

| Metric | Target | Current (2026-03-20) | Source |
|--------|--------|---------------------|--------|
| Problem interviews conducted | 10+ | 1-2 | Manual tracking |
| Founders who independently describe multi-domain pain | 5+ of 10 | — | Interview analysis |
| Founders using Soleur on real projects (2+ domains) | 5+ | — | GitHub/Discord observation |
| Founders expressing willingness to pay | 3+ of 10 | — | Interview/follow-up |
| Pillar articles published | 4+ | 3 (CaaS, Why Tools Plateau, Cowork) | soleur.ai/blog/ |
| Content score | — | 6/10 | Growth audit |
| AEO score | — | 6.8/10 (68/100, C+) | AEO audit |

### Growth Phase (Weeks 9-16)

| Metric | Target | Source |
|--------|--------|--------|
| Monthly organic visitors | 500+ | Plausible |
| Article pageviews | 100+ per article | Plausible |
| Plugin installs | 50+ total | Claude Code registry (if available) |
| Testimonials collected | 3-5 | Validation participants |
| Case studies published | 1+ | soleur.ai |
| AEO citation rate | Soleur mentioned in 2+ AI search results for target queries | Manual audit |

### Scale Phase (Weeks 17+)

| Metric | Target | Source |
|--------|--------|--------|
| Monthly organic visitors | 2,000+ | Plausible |
| Weekly active users | 20+ | Analytics/GitHub |
| Conversion rate (visit to install) | 5%+ | Plausible + install tracking |
| Revenue | Any | Payment processor |
| Content pieces published | 2+ per month | soleur.ai |
| Community members (Discord) | 100+ | Discord metrics |

### Week-over-Week Growth Targets

Growth targets apply to **unique visitors only** -- other metrics are monitored directionally. Phase transitions are time-based. The founder assesses target adherence during weekly review. After Phase 3 ends, review targets quarterly based on accumulated data.

| Phase | Period | WoW Target | Absolute Target |
|-------|--------|-----------|----------------|
| Phase 1: Content Traction | Weeks 1-4 (Mar 13 - Apr 10) | +15% WoW | 100/week by week 4 |
| Phase 2: Content Velocity | Weeks 5-8 (Apr 11 - May 9) | +10% WoW | 250/week by week 8 |
| Phase 3: Organic Growth | Weeks 9-16 (May 10 - Jul 4) | +7% WoW | 500/week by week 16 |

Weekly snapshots are generated automatically by CI (`scheduled-weekly-analytics.yml`) and committed to `knowledge-base/marketing/analytics/`. Each snapshot includes the current growth target phase and actual WoW change for comparison.

---

## Competitive Response Playbook

### If Anthropic Adds Persistent Memory to Cowork

**Threat level:** Existential. This eliminates the compounding knowledge base moat.

**Response:**

1. Accelerate content establishing Soleur as the original CaaS platform (category ownership)
2. Emphasize workflow orchestration depth (brainstorm-plan-implement-review-compound lifecycle)
3. Emphasize open-source transparency vs. proprietary platform lock-in
4. Pivot positioning to "the AI organization you own" vs. "the AI organization you rent"

### If Notion Ships Engineering Agents

**Threat level:** High. Notion has massive distribution (35M+ users) and would become the closest full-stack competitor.

**Response:**

1. Publish immediate comparison content: "Soleur vs. Notion Custom Agents"
2. Emphasize terminal-first workflow vs. workspace-first (different audiences)
3. Emphasize compounding knowledge base scoped to solo founder operations vs. team collaboration
4. Lean into engineering depth (Notion's agents will start shallow)

### If a Direct CaaS Competitor Emerges with Engineering + Business Domains

**Threat level:** High. First-mover advantage on CaaS category naming is time-limited.

**Response:**

1. Category authority content must already exist (Phase 1 deliverables)
2. "Built with Soleur" case studies demonstrate operational maturity
3. Open-source core means community can be a moat
4. 420+ PRs of compounding knowledge base demonstrate institutional depth no new entrant can replicate quickly

---

## What This Strategy Does NOT Include

1. **Paid advertising.** No paid acquisition until organic channels prove the thesis. Budget is zero.
2. **Hiring.** All execution is solo founder. No marketing team, no contractors, no agencies.
3. **Enterprise marketing.** Target is solo founders. Enterprise is a future segment after individual validation.
4. **Product features for marketing purposes.** The PIVOT verdict says pause features. Marketing works with the existing product.
5. **Revenue projections.** Pricing model is undecided. Revenue projections require validated pricing, which requires validated demand, which requires the interviews this strategy enables.

---

## Review Cadence

- **Weekly:** Check Plausible analytics. Note which content performs. Adjust distribution.
- **Biweekly:** Review validation pipeline. How many interviews done? What patterns emerge?
- **Monthly:** Review competitive intelligence for material changes. Update battlecards if needed.
- **Quarterly:** Full strategy review. Update this document. Re-assess positioning, channel mix, and priorities based on accumulated data.

Next review: 2026-06-03.

---

## Cascade Documents

This strategy is supported by detailed specialist documents:

| Document | Path | Contents |
|----------|------|----------|
| Content Strategy | `knowledge-base/marketing/content-strategy.md` | Content gaps (12), pillar definitions, quarterly calendar (Mar-Jun 2026), execution priorities |
| Pricing Strategy | `knowledge-base/product/pricing-strategy.md` | Competitive pricing matrix, recommended model, value metric analysis |
| SEO Refresh Queue | `knowledge-base/marketing/seo-refresh-queue.md` | Stale pages, new pages needed, monitoring list |
| Battlecard: Anthropic Cowork | `knowledge-base/sales/battlecards/tier-0-anthropic-cowork.md` | Talk tracks, differentiators, objection handling |
| Battlecard: Cursor | `knowledge-base/sales/battlecards/tier-0-cursor.md` | Talk tracks, differentiators, objection handling |
| Battlecard: Notion AI | `knowledge-base/sales/battlecards/tier-3-notion-ai.md` | Talk tracks, differentiators, objection handling |
| Battlecard: Tanka | `knowledge-base/sales/battlecards/tier-3-tanka.md` | Talk tracks, differentiators, objection handling |

---

_Updated: 2026-03-20. Source documents: brand-guide.md (2026-02-21), competitive-intelligence.md (2026-03-12), business-validation.md (2026-02-25), content-plan.md (2026-03-17), content-audit.md (2026-03-17), aeo-audit.md (2026-03-17), seo-audit.md (2026-03-17)._
