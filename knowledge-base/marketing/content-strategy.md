---
last_updated: 2026-04-03
last_reviewed: 2026-04-28
review_cadence: weekly
owner: CMO
depends_on:
  - knowledge-base/marketing/brand-guide.md
  - knowledge-base/marketing/marketing-strategy.md
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-plan.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-seo-audit.md
---

# Soleur Content Strategy

## Purpose

This document defines what content Soleur needs, why, in what order, and how it connects to the marketing strategy. It synthesizes findings from the content audit (2026-03-17), AEO audit (2026-03-17), SEO audit (2026-03-17), keyword research (2026-03-17), and competitive intelligence (2026-03-12).

> **[2026-03-22 Business Validation Review]** The delivery pivot (users reject CLI/plugin, want web/mobile) has three implications for content strategy: (1) Content targeting "Claude Code plugin" users as the primary audience must broaden to "solo founders using AI tools" -- the beachhead is the problem, not the tool. (2) Pillar 3 keyword "Claude Code plugins" is still valid for SEO capture but is no longer the primary ICP entry point. (3) The "Built with Soleur" case study angle strengthens -- showing Soleur building itself demonstrates the product regardless of delivery surface. No content gaps are invalidated; several gain urgency (Gap 5 Polsia comparison becomes delivery-parity, Gap 9 price justification must account for platform costs).

---

## Content Gap Analysis

Twelve content gaps block Soleur's organic discovery and category authority. Ranked by strategic impact. Gaps marked `[COMPLETED]` are addressed; their history is preserved for institutional context.

### Gap 1: Cross-Domain Compounding Narrative (Critical) [UPDATED 2026-03-20]

**What is missing:** The "Why Most Agentic Engineering Tools Plateau" blog post (SAP 4.8/5.0) partially addresses this gap by explaining compound knowledge. However, no dedicated article exists that explains the compounding knowledge base as Soleur's core differentiator in depth. The homepage mentions "knowledge compounds" as a tagline but never elaborates.

**Why it matters:** Tanka explicitly claims "memory compounding" as their moat. Anthropic will eventually add persistence to Cowork. The first platform to own this narrative in public content establishes the standard. That platform should be Soleur, which built the architecture.

**Content needed:**

- Pillar article: "What Is Knowledge Compounding in AI Development?"
- Homepage section expansion explaining the knowledge flow (brand guide informs marketing, competitive analysis shapes pricing, legal audit references privacy policy)
- "Built with Soleur" case study demonstrating compounding over 420+ PRs

### Gap 2: CaaS Category Definition (Critical) [COMPLETED 2026-03-10]

**Status:** Published as "What Is Company-as-a-Service?" (promoted 2026-04-21 from `/blog/what-is-company-as-a-service/` to `/company-as-a-service/`; 301 via pageRedirects). SAP score 5.0/5.0 (best on site). FAQ JSON-LD present. 10+ external citations (BLS, TechCrunch, CNBC, VentureBeat, Inc.com, Fortune). Internal linking from homepage badge active.

**Original gap:** Soleur coined "Company-as-a-Service" and used it as a tagline but had no page defining the term. Zero competition for this exact term made category creation the highest-leverage content play.

**Content delivered:**

- ~~Pillar article: "What Is Company-as-a-Service?"~~ Published
- ~~FAQ schema on the article~~ FAQPage JSON-LD with 5 questions
- ~~Internal linking from homepage badge~~ Active

### Gap 3: IDE Positioning (High) [UPDATED 2026-03-20] **[2026-03-22: REFRAME]**

**What is missing:** Three comparison articles now address the "and" positioning directly: Soleur vs. Cowork (2026-03-16), Soleur vs. Cursor (2026-03-19), Soleur vs. Notion Custom Agents (2026-03-17). The remaining gap is a standalone position paper articulating why an agent platform is fundamentally different from an AI organization -- the conceptual argument, not a product comparison.

**Why it matters:** Individual comparisons address specific competitors. The position paper captures the category-level argument that applies to all competitors and emerging entrants. **[2026-03-22]** The "IDE Positioning" label is now misleading -- Soleur's delivery surface is shifting from IDE to web platform. The position paper should frame the distinction as "agent platform vs. AI organization" without anchoring to any specific delivery surface. Existing comparison articles remain valid -- they compare capabilities, not form factors.

**Content remaining:**

- ~~Comparison article: "Soleur vs. Alternatives"~~ Addressed by 3 individual comparisons
- ~~Individual comparison pages (Cowork, Cursor, Notion)~~ All published
- Position paper: "Agent Platform vs. AI Organization" (audit P2 priority)

### Gap 4: Engineering-in-Context Value Proposition (High) [UPDATED 2026-03-29]

**What is missing:** "Why Most Agentic Engineering Tools Plateau" (SAP 4.8/5.0) partially covers this gap by explaining compound knowledge and the brainstorm-plan-implement-review-compound lifecycle. The remaining gap is a dedicated article targeting the trending search query "vibe coding vs agentic engineering" (audit P2-1, score 18/20) -- the highest-priority new content identified by the 2026-03-17 growth audit.

**What is covered:** The repo connection feature (PR #1257) makes the engineering-in-context value proposition concrete. Two content pieces published:

- Product update: "Your AI Team Now Works From Your Actual Codebase" -- announces repo connection, explains compound knowledge in practice
- Technical deep-dive: "Credential Helper Isolation: Secure Git Auth in Sandboxed Environments" -- targets developer/security audience

**Why it matters:** "Agentic engineering" is now mainstream (IBM, The New Stack, Addy Osmani all publishing). "Vibe coding vs agentic engineering" is a trending comparison query. No authoritative comparison exists that positions Soleur.

**Content remaining:**

- ~~Pillar article: "Agentic Engineering: Beyond Vibe Coding"~~ Renamed to "Vibe Coding vs Agentic Engineering: What Solo Founders Need to Know" to better target search query
- Connection to Every.to's compound engineering methodology
- Comparison table: vibe coding vs. agentic engineering vs. compound engineering

### Gap 5: Autopilot vs. Decision-Maker Positioning Against Polsia (Critical) [NEW 2026-03-09, UPDATED 2026-03-20]

**What is missing:** Polsia has accelerated to $1.5M ARR with 2,000+ autonomously managed companies. Pricing at $29-59/month. The "Soleur vs Polsia" comparison (audit P2-3, score 16/20) is the next priority comparison article. A standalone position paper on autonomy vs. founder-in-the-loop is still needed.

**Why it matters:** Polsia's growth validates the CaaS market thesis aggressively. Solo founders evaluating both platforms need content that frames the trade-off clearly. Without it, Polsia's "AI runs your company while you sleep" narrative goes unchallenged.

**Content needed:**

- Pillar article: "Autopilot vs. Decision-Maker: Two Models for AI Company Operation"
- Comparison page: "Soleur vs. Polsia" (audit P2-3, score 16/20) **[2026-03-22: PRIORITY ELEVATED -- Polsia delivers via web dashboard, which is now Soleur's target delivery surface. The comparison shifts from "terminal vs. cloud" to "founder-controlled vs. autonomous" since the delivery format is no longer a differentiator.]**
- Blog post: "Why Human Judgment Compounds Better Than Full Autonomy"

### Gap 6: Cursor Agent Platform Positioning (Critical) [COMPLETED 2026-03-19]

**Status:** Published as "Soleur vs Cursor (2026): Full AI Organization vs Code-Only Assistant" (`/blog/2026-03-19-soleur-vs-cursor/`). Addresses Automations, Marketplace, and the engineering-platform vs. company-platform distinction.

**Original gap:** Cursor shipped Automations (March 5, 2026) with always-on agents and 30+ marketplace plugins. The "I already use Cursor" objection needed an answer that acknowledged Cursor's expanded surface.

**Content delivered:**

- ~~Updated comparison page: "Soleur vs. Cursor"~~ Published 2026-03-19
- Blog post: "Why an Agent Platform Is Not an AI Organization" -- folded into Gap 3 remaining work
- ~~Update to IDE Positioning gap (Gap 3)~~ Done (Gap 3 updated 2026-03-20)

### Gap 7: Microsoft Copilot Cowork + Anthropic Partnership Narrative (Medium) [NEW 2026-03-12, UPDATED 2026-03-20]

**What is missing:** Microsoft launched Copilot Cowork (March 9, 2026) powered by Anthropic Claude, bringing agentic task execution into Outlook, Teams, and Excel as part of a new E7 Frontier Suite. This extends Anthropic's technology into the 400M+ Microsoft 365 user base. No content addresses this development or frames Soleur's positioning relative to the enterprise-targeted normalization of agentic business automation.

**Why it matters:** Even though Copilot Cowork targets enterprises (not solo founders), it validates and commoditizes the "agentic business automation" category at massive scale. Founders will increasingly expect AI to handle business tasks autonomously. The content opportunity is framing Soleur as the founder-controlled, local-first, open-source alternative to enterprise-locked cloud automation.

**Content needed:**

- Blog post: "Enterprise Agentic Automation vs. Founder-Controlled AI Organizations" (P3 -- deprioritized; the Cowork comparison article partially addresses the Anthropic partnership context)
- ~~Update to Cowork comparison page~~ Cowork comparison published 2026-03-16, includes partnership context

### Gap 8: Paperclip Orchestration Layer Differentiation (Medium) [NEW 2026-03-12]

**What is missing:** Paperclip (14.6k GitHub stars, MIT-licensed) provides open-source orchestration for zero-human companies: org charts, budgets, governance, heartbeat scheduling, multi-company support. It is infrastructure-layer and agent-runtime-agnostic (supports Claude, Cursor, Codex, etc.). The upcoming Clipmart feature (pre-built company templates) could lower the barrier to "zero-human company" creation. No content explains Soleur's relationship to Paperclip (complementary layers: orchestration vs. domain intelligence).

**Why it matters:** Developers discovering Paperclip will ask whether it replaces Soleur. The answer is no -- Paperclip provides the organizational scaffolding, Soleur provides the domain-specific agents, skills, and compounding knowledge. Articulating this complementary positioning could turn Paperclip's distribution into a channel for Soleur.

**Content needed:**

- Blog post: "Orchestration vs. Intelligence: How Paperclip and Soleur Complement Each Other"
- Potential integration documentation: using Soleur agents within Paperclip's org chart framework

### Gap 9: Price Justification Framework (Medium)

**What is missing:** When pricing launches, founders will compare the price to individual tools ($15-25/month for Cursor, Devin, Windsurf). No content frames the cost against the replacement stack: brand agency ($5-15k), lawyer ($300-500/hour), marketing tools ($50-200/month), product management tools ($10-30/month), combined. Without this framing, the price appears to compete with coding tools rather than replacing an entire team.

**Why it matters:** Devin dropped from $500 to $20/month. The market expects AI coding tools to cost $15-25/month. Soleur's premium must be justified by non-engineering value.

**Content needed:**

- Blog post: "The Real Cost of Running a Solo Company" (cost analysis)
- Pricing page with replacement-stack framing when pricing launches
- Testimonials from validation participants on non-engineering domain value

### Gap 10: Listicle Presence (Critical) [NEW 2026-03-20]

**What is missing:** Soleur appears on **zero** third-party listicles for "best AI agents," "solo founder tools," or "AI agent platforms." This is the single largest discoverability gap identified by the 2026-03-17 growth audit (OS-1). 89% of site traffic is direct -- organic search discovery is near-zero.

**Why it matters:** Listicle presence drives both direct traffic and backlink authority. Competitors appear on multiple lists (Arahi, Lindy, Make). Without listicle presence, even perfect on-page SEO produces minimal traffic.

**Content needed:**

- Listicle outreach to: TLDL, Entrepreneur.com, Taskade, o-mega.ai, AIMultiple
- Product Hunt launch
- Hacker News submission strategy
- GitHub Awesome List submissions
- Create own listicle: "Best Claude Code Plugins for Solo Founders (2026)" to capture the SERP and include Soleur

### Gap 11: About/Founder Page (High) [NEW 2026-03-20]

**What is missing:** No About page exists. Blog posts credit "Jean Jikig" but link only to the homepage. Both the AEO audit (C5) and SEO audit (recommendation 9) flag this as a significant E-E-A-T gap. AI models assessing authority need founder credentials, social profiles, and operating company details.

**Why it matters:** Solo-founder positioning requires a visible, credible founder. Without an About page, the expertise signal caps how much trust content earns from both search engines and AI models.

**Content needed:**

- About/Founder page with credentials, social profiles (GitHub, X, LinkedIn, Bluesky), and operating company details (Jikigai, France)
- `SameAs` addition to Organization JSON-LD schema in `base.njk`

### Gap 12: External Citations on Non-Blog Pages (High) [NEW 2026-03-20]

**What is missing:** 12 of 15 pages have zero external citations. The AEO audit (C1) identified a stark binary split: blog pillar content is citation-rich (5.0/5.0), everything else has none (1.0/5.0). Catalog pages (Agents, Skills, Vision, Community, Getting Started) contain no authoritative external references.

**Why it matters:** AI models weight source citations heavily for citability (+30-40% per Princeton GEO research). Pages without citations are functionally invisible to AI engines regardless of their content quality.

**Content needed:**

- Add 1-2 authoritative external citations per catalog page (Agents, Skills, Vision, Getting Started, Community)
- Add definition paragraphs with citations to Agents page ("Agentic engineering is...") and Skills page ("In Soleur, a skill is...")

### Gap 13: Command Center Launch Narrative (Critical) [NEW 2026-03-27]

**What is missing:** The web platform shipped a fundamental UX paradigm shift: from "choose a department leader" (8-card grid) to "command center" (auto-routed multi-leader chat). Alongside this, 20 Architecture Decision Records and C4 diagrams were captured. No content announces this shift, explains the product design thinking, or documents the technical architecture. The homepage, meta tags, and all marketing copy still reference the old "choose a domain leader" interaction model.

**Why it matters:** The "command center" framing is Soleur's strongest positioning upgrade to date. "Experts come to you" is more visceral than "visit separate offices." No competitor auto-routes to the right expert based on conversation context. The paradigm shift itself is content-worthy.

**Content needed:**

- Blog post: "From Department Offices to Command Center" (narrative, build-in-public) -- explains why the UX changed, what the founder gains, how auto-routing works. Hero content for the launch announcement.
- Blog post: "One Chat, 8 Departments: How We Built Domain Routing with Claude Haiku" (technical deep-dive) -- assessment questions as classification, multi-leader streaming architecture, Map-based stream multiplexing. Targets developer audience.
- Blog post: "Why We Wrote 20 Architecture Decision Records for an AI Platform" (thought leadership) -- positions Soleur as engineering-serious. The "Cost Impacts" section in the ADR template is a differentiator.
- Distribution: X thread + LinkedIn + Discord announcement linking to the narrative blog post.
- Website copy updates: dashboard, meta tags, brand guide (critical tier completed in PR).

---

## Content Pillars

All content maps to one of four pillars. Each pillar targets a specific audience segment and search intent.

### Pillar 1: Category Definition

**Audience:** Founders and thought leaders exploring the future of work and AI organizations.
**Search intent:** Informational.
**Keywords:** company as a service, CaaS platform, agentic company, full-stack AI organization, agentic era.
**Voice:** Maximum ambition, declarative. Brand guide "Marketing / Hero" tone.

| Piece | Type | Words | Priority | Status |
|-------|------|-------|----------|--------|
| What Is Company-as-a-Service? | Pillar explainer | 2,500-3,000 | P1 | **PUBLISHED** (SAP 5.0/5.0) |
| One-Person Billion-Dollar Company: The Complete Guide | Thought leadership | 2,500-3,500 | P2 | Month 2 |
| Autopilot vs. Decision-Maker: Two Models for AI Company Operation | Position paper | 2,000-2,500 | P2 | Month 2 |
| Company-as-a-Service vs SaaS: How CaaS Changes Everything | Comparison | 2,000-2,500 | P3 | Month 3 |
| The Agentic Company Glossary | Reference | 2,000-3,000 | P3 | Month 3+ |

### Pillar 2: Methodology

**Audience:** Technical builders looking for structured AI development workflows.
**Search intent:** Informational.
**Keywords:** agentic engineering, compound engineering, vibe coding vs agentic engineering, AI coding workflow, knowledge compounding.
**Voice:** Confident, concrete. Brand guide "Product announcements" tone.

| Piece | Type | Words | Priority | Status |
|-------|------|-------|----------|--------|
| Why Most Agentic Engineering Tools Plateau | Pillar explainer | ~3,000 | P1 | **PUBLISHED** (SAP 4.8/5.0). Partially addresses Gaps 1 and 4. |
| How We Used AI-Generated Personas to Improve Interview Questions by 93% | Methodology | 2,000-3,000 | P1 | Month 1 (Mar 27-Apr 2). Issue #1176. Source: synthetic research sprint. Angle: practitioner methodology, not product demo. Hook: 52%→93% rich response rate over 3 rounds. New content type for Pillar 2 (research methodology). |
| Vibe Coding vs Agentic Engineering: What Solo Founders Need to Know | Comparison | 2,000-2,500 | P1 | Month 1. Renamed from "Agentic Engineering: Beyond Vibe Coding" to target search query. Audit P2-1, score 18/20. |
| Knowledge Compounding in AI Development | Concept explainer | 1,500-2,000 | P2 | Month 2-3. Addresses Gap 1. |
| Compound Engineering: How Every Project Makes the Next One Easier | Concept explainer | 1,500-2,000 | P3 | Month 3+. Audit P3-4. |
| One Chat, 8 Departments: How We Built Domain Routing with Claude Haiku | Technical deep-dive | 2,000-2,500 | P1 | Month 1. Gap 13. Multi-leader streaming, assessment question classification, Map-based multiplexing. |
| Why We Wrote 20 Architecture Decision Records for an AI Platform | Thought leadership | 1,500-2,000 | P2 | Month 2. Gap 13. ADR template with Cost Impacts, C4 diagrams, architecture-as-code skill. |
| 53 Issues in 3 Days: When Agentic Code Review Defaults Compound Silently | Post-mortem / case study | 1,500-2,000 | P1 | Month 2 (scheduled after PR #2375 bakes 3-5 days). Issue #2399. Hook: "Our code-review agents filed 53 GitHub issues in 3 days. The bug wasn't the agents — it was one default in our skill definitions." Lesson: audit the defaults, not the agents. Target channels: blog primary, X/Twitter thread, HN submission Tue-Thu. |
| When Plan-Time Review Misses What Run-Time Review Catches: A One-Time-Schedule Story | Post-mortem / case study | 1,500-2,000 | P2 | Month 2 (after PR #3067 bakes 5-7 days, dogfood completes). Issue #3108. Hook: "A 3-reviewer plan-time pass approved a one-time scheduling feature with 4 defenses. The 11-agent run-time review found a 5th defense was load-bearing — comment-mutability between authoring and fire." Lesson: `Brand-survival = single-user incident` requires `user-impact-reviewer` in the panel; "no inline prompts" and "runtime content integrity" are independent invariants. Companion: `soleur:schedule --once` ships the D1-D5 defense stack. Target channels: blog primary, X/Twitter thread, Discord, LinkedIn. |

### Pillar 3: Competitive Positioning

**Audience:** Founders evaluating tools, comparing options.
**Search intent:** Commercial investigation.
**Keywords:** Claude Code plugins, AI agent comparison, Soleur vs CrewAI, best AI coding agents 2026, solopreneur AI stack. **[2026-03-22: "Claude Code plugins" remains a valid SEO capture keyword but is no longer the primary ICP discovery path. Add "AI company platform", "AI business operations" as keywords when the web platform launches.]**
**Voice:** Direct, honest, data-driven. No FUD. Acknowledge competitor strengths.

| Piece | Type | Words | Priority | Status |
|-------|------|-------|----------|--------|
| Soleur vs. Anthropic Cowork | Comparison page | ~2,500 | P1 | **PUBLISHED** (2026-03-16). FAQ JSON-LD present. |
| Soleur vs. Cursor (2026) | Comparison page | ~2,000 | P1 | **PUBLISHED** (2026-03-19). Addresses Automations + Marketplace. |
| Soleur vs. Notion Custom Agents | Comparison page | ~2,000 | P1 | **PUBLISHED** (2026-03-17). |
| AI Agents for Solo Founders: The Definitive Guide (2026) | Pillar guide | 3,000-4,000 | P1 | Month 1-2. Audit P2-2, score 18/20. Captures "solopreneur AI tools 2026" high-volume keyword. |
| Soleur vs. Polsia | Comparison page | 1,500-2,000 | P2 | Month 2. Audit P2-3, score 16/20. |
| Best Claude Code Plugins for Solo Founders (2026) | Listicle | 2,000-2,500 | P2 | Month 3. Audit P3-2. |
| Agent Platform vs. AI Organization | Position paper | 1,500-2,000 | P2 | Month 2-3. Remaining Gap 3 work. |
| Orchestration vs. Intelligence: Paperclip and Soleur | Blog post | 1,200-1,500 | P3 | Month 3+. Gap 8. |

### Pillar 4: Proof and Tutorials

**Audience:** Founders ready to try the product or needing evidence it works.
**Search intent:** Transactional / commercial.
**Keywords:** how to build SaaS with AI, solo founder workflow, built with Soleur.
**Voice:** Clear, precise. Brand guide "Technical docs" tone.

| Piece | Type | Words | Priority | Status |
|-------|------|-------|----------|--------|
| Case Study: Business Validation | Case study | ~1,500 | P1 | **PUBLISHED** (2026-03-10). Lacks FAQ section (P1 fix). |
| Case Study: Legal Document Generation | Case study | ~1,500 | P1 | **PUBLISHED** (2026-03-10). Lacks FAQ section (P1 fix). |
| Case Study: Operations Management | Case study | ~1,500 | P1 | **PUBLISHED** (2026-03-10). Lacks FAQ section (P1 fix). |
| Case Study: Brand Guide Creation | Case study | ~1,500 | P1 | **PUBLISHED** (2026-03-10). Lacks FAQ section (P1 fix). |
| Case Study: Competitive Intelligence | Case study | ~1,500 | P1 | **PUBLISHED** (2026-03-10). Lacks FAQ section (P1 fix). |
| About/Founder Page | Authority page | 500-800 | P1 | Month 1. Gap 11. Low effort, high E-E-A-T impact. |
| From Department Offices to Command Center | Build-in-public narrative | 1,500-2,000 | P1 | Month 1. Gap 13. Hero content for command center launch. Explains UX paradigm shift, auto-routing, multi-leader threading. Link target for social distribution. |
| PWA Installability Milestone Announcement | Distribution (social) | N/A | P1 | **DRAFT** (2026-03-29). Social announcement for PWA shipping (PR #1256). Reinforces "accessible anywhere" positioning. Draft at `distribution-content/2026-03-29-pwa-installability-milestone.md`. |
| How to Build a SaaS as a Solo Founder | Tutorial | 2,500-3,000 | P3 | Month 3+. |

---

## Publishing Cadence

**Perpetual cadence: 2 posts per week (Tuesday + Thursday), staggered across platforms.**

This cadence is not tied to any campaign. It runs indefinitely. The `scheduled-content-generator.yml` workflow (Tue/Thu 10:00 UTC) generates articles from the SEO refresh queue or via growth plan discovery. The `scheduled-content-publisher.yml` workflow (daily 14:00 UTC) publishes any distribution content file with `publish_date == today` and `status: scheduled`. The `scheduled-campaign-calendar.yml` workflow (Mondays 16:00 UTC) refreshes this calendar and flags overdue items.

**Distribution channels per post:** Discord, X/Twitter, Bluesky, LinkedIn Company. Additional platforms (IndieHackers, Reddit, HN) are selective per content type.

**Content sources (in priority order):**

1. Manually planned articles from the quarterly calendar below
2. Auto-generated articles from `knowledge-base/marketing/seo-refresh-queue.md`
3. Growth plan discovery (fallback when queue is exhausted)

**Overdue handling:** If a distribution content file's `publish_date` has passed without publication, the campaign calendar workflow flags it. Overdue items are rescheduled to the next available Tue/Thu slot.

---

## Rolling Quarterly Content Calendar (March - June 2026)

This calendar complements the perpetual cadence above. It defines what to write and when. Assumes 8-12 hours per week for content. Capacity constraint: one founder.

### Month 1 (March 20 - April 20, 2026): Technical Fixes + First New Article

| Week | Task | Hours | Output |
|------|------|-------|--------|
| Mar 20-26 | P1 technical fixes: FAQ JSON-LD on agents page + "Why Tools Plateau", FAQ sections on 5 case studies, remove "plugin" from meta descriptions, Vision page H1 rewrite, add `updated` frontmatter to blog posts, add "open source" + "solopreneur" to homepage | 6-8 | All P1 technical fixes deployed |
| Mar 27-Apr 2 | Write "How We Used AI-Generated Personas to Improve Interview Questions by 93%" methodology article (issue #1176). Distribute: Substack comment on Ivelin's article, LinkedIn, X thread. | 6-8 | Blog post + social distribution |
| Apr 3-6 | Write "From Department Offices to Command Center" narrative (Gap 13). Distribute: X thread, LinkedIn, Discord announcement. | 6-8 | Launch blog post + social distribution |
| Apr 7 (Tue) | **Distribute** "Vibe Coding vs Agentic Engineering" across all channels (rescheduled from Mar 24). Write "One Chat, 8 Departments: Domain Routing with Claude Haiku" technical deep-dive (Gap 13). | 6-8 | Vibe Coding social posts live + technical blog post |
| Apr 10 (Thu) | **Distribute** PWA Installability Milestone across all channels (rescheduled from Mar 29). Write "Vibe Coding vs Agentic Engineering" article body if not yet complete (audit P2-1, score 18/20). | 6-8 | PWA social posts live + article draft |
| Apr 14-20 | Add external citations to 5+ catalog pages (Gap 12). Add FAQ sections to Skills, Getting Started, Community pages. | 4-6 | AEO score improvement |
| Apr 21-27 | Write About/Founder page (Gap 11). Review analytics. | 4-6 | E-E-A-T improvements |

### Month 2 (April 28 - May 25, 2026): Pillar Content + Comparisons

| Week | Task | Hours | Output |
|------|------|-------|--------|
| Apr 28-May 4 | Write "AI Agents for Solo Founders: The Definitive Guide" (audit P2-2, score 18/20) | 8-10 | Pillar article draft |
| May 5-11 | Publish AI Agents guide. Begin "Soleur vs Polsia" comparison (audit P2-3). | 6-8 | 1 pillar + 1 comparison draft |
| May 12-18 | Publish Soleur vs Polsia. Write "Why We Wrote 20 ADRs" (Gap 13, P2). | 6-8 | Comparison live + ADR thought leadership |
| May 19-25 | Write "One-Person Billion-Dollar Company" (high social distribution potential). Distribution + analytics review. | 6-8 | Draft + status check |
| Apr 20-22 (post-PR #2375 bake) | Draft "53 Issues in 3 Days" post-mortem (Issue #2399, Pillar 2). Cite 3-5 days of Phase 5.5 gate evidence. | 3-4 | Blog draft + X thread + HN submission plan |
| May 12-15 (post-PR #3067 bake + dogfood) | Draft "When Plan-Time Review Misses What Run-Time Review Catches" post-mortem (Issue #3108, Pillar 2). Cite the D1→D5 defense expansion and the user-impact-reviewer-only catch. Companion announcement: `soleur:schedule --once` is GA. | 3-4 | Blog draft + announcement post + X thread + LinkedIn |

### Month 3 (May 21 - June 20, 2026): Long-Tail + Off-Site

| Week | Task | Hours | Output |
|------|------|-------|--------|
| May 21-27 | Publish "One-Person Billion-Dollar Company". Begin off-site listicle outreach (Gap 10). | 4-6 | Article live + outreach started |
| May 28-Jun 3 | Write "Best Claude Code Plugins for Solo Founders" (audit P3-2). Continue outreach. | 6-8 | Listicle article draft |
| Jun 4-10 | Write "Company-as-a-Service vs SaaS" (audit P3-3). | 6-8 | Draft |
| Jun 11-17 | Add page-specific OG images for pillar blog posts. Publish remaining drafts. | 4-6 | OG images + articles live |
| Jun 18-20 | Full SEO/AEO re-audit. Compare against 2026-03-17 baselines. Plan next quarter. | 3-4 | Q2 audit report |

---

## Content Quality Standards

All content must pass these checks before publication:

### Brand Voice

- [ ] No prohibited terms: "AI-powered", "leverage AI", "just/simply", "assistant/copilot", startup jargon ("disrupt", "synergy")
- [ ] Declarative voice, no hedging ("might", "could", "potentially")
- [ ] Founder framed as decision-maker, system as executor
- [ ] Concrete numbers when available (60+ agents, 60+ skills, 420+ PRs)
- [ ] Short, punchy sentences in marketing copy
- [ ] Never called a "plugin" or "tool" (exception: literal CLI commands and technical docs) **[2026-03-22: This rule gains even more force under the delivery pivot. The product is a platform, not a plugin. "Plugin" should only appear in historical context or when referring to the Claude Code plugin specifically as one access surface.]**

### SEO

- [ ] Primary keyword in H1
- [ ] Primary keyword in first 150 words
- [ ] Secondary keywords in H2s
- [ ] Internal links to at least 2 other pages using keyword-rich anchor text
- [ ] Meta title under 60 characters with primary keyword
- [ ] Meta description under 160 characters with primary keyword and CTA
- [ ] JSON-LD Article schema with author, datePublished, dateModified
- [ ] OG image, OG title, OG description

### AEO (AI Engine Optimization)

- [ ] FAQ section with 3-5 questions in conversational format
- [ ] FAQ schema markup (JSON-LD FAQPage)
- [ ] Machine-readable summary in first paragraph (what, who, why)
- [ ] Definitions use "is" format ("Company-as-a-Service is...")
- [ ] Article can be meaningfully excerpted by an AI agent from the first 3 paragraphs alone
- [ ] `updated` frontmatter field set if content has been revised since initial publication
- [ ] Visible "Last Updated" date displayed to users (if `updated` is set)
- [ ] At least 1 external citation on every page (including catalog pages)

### Structure

- [ ] Outline reviewed before drafting
- [ ] H2/H3 hierarchy is logical and scannable
- [ ] Each section can stand alone (AI agents extract sections, not full pages)
- [ ] CTA present (not aggressive -- "Start building" or "See the agents")
- [ ] Word count within target range for piece type

---

## Content Repurposing Strategy

Each pillar article generates derivative content for multiple channels. This maximizes reach per hour of writing.

| Source Article | X/Twitter Thread | Discord Post | IndieHackers Update | HN Submission |
|---------------|-----------------|-------------|-------------------|--------------|
| What Is CaaS? | 7-tweet thread defining the category | Channel post with key points | "What we mean by Company-as-a-Service" | Submit article directly |
| Billion-Dollar Solo Company | Quote thread (Amodei, Altman predictions + Soleur's take) | Discussion prompt: "When does the first solo unicorn happen?" | Building update with thesis link | Submit article directly |
| Autopilot vs. Decision-Maker | Thread: "Two philosophies for AI company operation. One removes you. One amplifies you." | Discussion: "Would you let AI run your company autonomously?" | Position post with Polsia comparison | Submit article directly |
| Agentic Engineering | Before/after thread (vibe coding vs. agentic engineering) | Workflow screenshot + explanation | Technical deep dive post | Submit article directly |

---

## UTM Conventions

All article URLs distributed via social-distribute use platform-specific UTM parameters. Plausible reads these natively from URL query strings — no analytics configuration needed. UTM-tagged traffic appears in the Sources > Campaigns report.

### Parameter Table

| Platform | `utm_source` | `utm_medium` | `utm_campaign` |
|----------|-------------|-------------|----------------|
| Discord | `discord` | `community` | `<article-slug>` |
| X/Twitter | `x` | `social` | `<article-slug>` |
| IndieHackers | `indiehackers` | `community` | `<article-slug>` |
| Hacker News | `hackernews` | `community` | `<article-slug>` |
| LinkedIn | `linkedin` | `social` | `<article-slug>` |
| Bluesky | `bluesky` | `social` | `<article-slug>` |
| Reddit | `reddit` | — | — |

### Rules

- **Slug derivation:** Strip `/blog/` prefix and trailing `/` from the article URL path. Example: `/blog/caas-pillar/` → `caas-pillar`.
- **Reddit exception:** Minimal UTMs (`utm_source=reddit` only). Long marketing-looking URLs risk irreversible domain reputation damage on Reddit's spam filters.
- **Sanitization:** UTM values must contain only `a-z`, `0-9`, hyphens, and underscores.
- **Injection point:** UTM parameters are appended at generation time by the social-distribute skill, not at publish time by content-publisher.sh. This ensures all platforms (including manual channels) get tracked URLs.

---

## Measurement

### Per-Article Metrics (tracked in Plausible)

- Pageviews (first 7 days, first 30 days)
- Time on page (proxy for engagement)
- Scroll depth (if available via Plausible events)
- Referral source breakdown (organic, social, direct)
- Internal navigation (where do readers go after the article?)

### Aggregate Content Metrics (monthly review)

- Total organic visitors from content pages
- Keyword rankings for target terms (manual check using incognito search)
- AEO citations (search "company as a service" in Perplexity, ChatGPT, Google AI Overview -- does Soleur appear?)
- Content-to-install conversion (if trackable)

---

_Updated: 2026-05-03 (added Issue #3108: schedule --once + multi-agent-review D5 narrative). Previously: 2026-03-22 (business validation delivery pivot annotation). Sources: content-plan.md (2026-03-17), content-audit.md (2026-03-17), aeo-audit.md (2026-03-17), seo-audit.md (2026-03-17), competitive-intelligence.md (2026-03-22), brand-guide.md (2026-03-22), business-validation.md (2026-03-22)._
