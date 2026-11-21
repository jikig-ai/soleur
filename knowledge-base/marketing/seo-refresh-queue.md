---
last_updated: 2026-11-01
last_reviewed: 2026-09-15
review_cadence: monthly
owner: CMO
depends_on:
  - knowledge-base/product/competitive-intelligence.md
  - knowledge-base/marketing/content-strategy.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-03-17-seo-audit.md
---

# SEO Refresh Queue

This document tracks pages that need SEO updates, new pages that should be created for search visibility, and pages that need monitoring for competitive changes. Reviewed monthly.

> **[2026-06-02 Review note]** Competitor monitoring rows reconciled to `knowledge-base/product/competitive-intelligence.md` (2026-05-30 scan): **Polsia** ARR revised down ($1.5M → $450K+), 500+ companies, pricing now $49 base + 20% rev-share; **Paperclip** crossed 30,000+ stars and is now built on Claude Code; **Notion** Custom Agents beta ended May 3, credit pricing live since May 4. The comparison-page action items (P2 Paperclip, Notion update) remain open — copy on those pages should be refreshed against these figures.

> **[2026-09-15 Growth execution review]** Verified all Priority 1 stale-page items (§1.1–1.7) directly against live page source (`plugins/soleur/docs/index.njk`, `pages/agents.njk`, `pages/skills.njk`, `pages/getting-started.njk`, `pages/vision.njk`, `llms.txt.njk`, `blog/why-most-agentic-tools-plateau.md`). Every listed fix (FAQ + JSON-LD, meta description rewrites, keyword additions, citations, `updated` frontmatter) is present in the rendered source. Section headers previously read `[PARTIALLY DONE]`/`[NEW]` despite every row already showing **Done** — corrected to `[DONE]` to match actual state. No keyword-injection or meta-rewrite work was applied this run because none was outstanding.

---

## Priority 1: Stale Pages (Update Immediately)

Pages that exist on soleur.ai but have SEO deficiencies identified in the content audit (2026-02-19).

### 1.1 Homepage (soleur.ai/) [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 targets no searchable query | "Build a Billion-Dollar Company. Alone." | Keep as brand statement but add keyword-rich H2 or subtitle | Low | **Done** -- keyword-rich H2 added |
| Zero target keywords in body copy | Keywords added to H2s and body paragraphs | — | — | **Done** |
| Badge is only instance of "Company-as-a-Service" | Now in H2 and body text | — | — | **Done** |
| No FAQ schema | 6 FAQ items with FAQPage JSON-LD | — | — | **Done** |
| No internal links with keyword-rich anchor text | CTAs updated | — | — | **Done** |
| "Plugin" in meta description and FAQ texts | Meta description and 3 FAQ answers use "plugin" | Remove "plugin" per brand guide. Rewrite meta to: "Soleur is the open-source company-as-a-service platform..." | Low | **Done -- meta rewritten 2026-04-01** |
| Missing "open source" and "solopreneur" | Not present on homepage | Add to hero section or body text | Low | **Done -- "solopreneur" added to meta and FAQ answer 2026-04-01** |

**Remaining effort:** None -- verified complete 2026-09-15.

### 1.2 Agents Page (soleur.ai/pages/agents.html) [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 is bare "Agents" | Now "Soleur AI Agents" | — | — | **Done** |
| No introductory prose | Intro paragraph added | — | — | **Done** |
| No FAQ section | 3 FAQ items exist but no JSON-LD FAQPage schema | Add FAQPage JSON-LD to match existing HTML FAQ | Low | **Done -- FAQPage JSON-LD present** |
| Missing "open source AI agents" keyword | Not mentioned | Add note that agents are open source and inspectable | Low | **Done -- added to intro prose 2026-04-01** |
| No definition of "agentic engineering" | Term used without definition | Add one-sentence definition near first usage | Low | **Done -- definition present in intro** |

**Remaining effort:** None -- verified complete 2026-09-15.

### 1.3 Skills Page (soleur.ai/pages/skills.html) [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 is bare "Skills" | Now "Agentic Engineering Skills" | — | — | **Done** |
| No introductory prose | Lifecycle explanation added | — | — | **Done** |
| No FAQ section | Absent | Add FAQ with JSON-LD: "What is a skill in Soleur?", "How do skills differ from agents?" | Low | **Done -- FAQ + JSON-LD present** |
| Missing "AI workflow automation" keyword | Not present | Add commercially-searched term naturally | Low | **Done -- added to intro prose 2026-04-01** |

**Remaining effort:** None -- verified complete 2026-09-15.

### 1.4 Getting Started Page (soleur.ai/pages/getting-started.html) [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| No "What is Soleur?" context | Context paragraph added | — | — | **Done** |
| "Plugin" in meta description | "Install the Soleur Claude Code plugin..." | Rewrite meta to: "Get started with Soleur in one command..." | Low | **Done -- meta already correct** |
| No FAQ section | Absent | Add FAQ: installation, pricing, prerequisites | Low | **Done -- FAQ + JSON-LD present** |

**Remaining effort:** None -- verified complete 2026-09-15.

### 1.5 llms.txt [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| Generic description | Rewritten with platform positioning | — | — | **Done** |
| Agent/skill counts outdated | Updated to current counts | — | — | **Done** |

### 1.6 Vision Page (soleur.ai/pages/vision.html) [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 is "Vision" -- zero keyword value | Single generic word | Rewrite to "The Soleur Vision: Building the Company-as-a-Service Platform" | Low | **Done -- H1 is "The Soleur Vision: Company-as-a-Service for the Solo Founder"** |
| Uses "synthetic labor," "soloentrepreneurs" | Not in brand guide vocabulary | Align with brand voice | Low | **Done -- "synthetic labor" replaced with "AI agent swarms" 2026-04-01** |
| No FAQ section | Absent | Add FAQ: roadmap, model-agnostic, CaaS | Low | **Done -- FAQ + JSON-LD present** |
| No external citations | Zero | Add 1-2 authoritative citations | Low | **Done -- Dario Amodei citation added 2026-04-01** |

**Combined effort:** None -- verified complete 2026-09-15.

### 1.7 Blog Posts -- dateModified Signals [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| No `updated` frontmatter on any blog post | `dateModified` always equals `datePublished` in BlogPosting JSON-LD | Add `updated` field to blog posts that have been revised | Low | **Done -- `updated: 2026-04-01` added to Why Tools Plateau post** |
| No visible "Last Updated" display | Only `datePublished` shown | Add conditional "Last Updated" display to `blog-post.njk` template | Low | **Done -- conditional Last Updated added to blog-post.njk 2026-04-01** |
| "Why Tools Plateau" FAQ missing JSON-LD | 3 FAQ items formatted as H3 headings, no FAQPage schema | Convert to `<details>/<summary>` + add JSON-LD | Low | **Done -- converted to details/summary + FAQPage JSON-LD added 2026-04-01** |

**Combined effort:** None -- verified complete 2026-09-15.

---

## Priority 2: New Pages (Create in Phase 1-2)

Pages that do not exist but should, based on keyword research and competitive positioning needs.

### 2.1 Comparison Pages

| Page | Target Keywords | Search Intent | Priority | Status |
|------|----------------|---------------|----------|--------|
| **Soleur vs. Anthropic Cowork** | soleur vs cowork, AI agent platform comparison | Commercial | P1 | **PUBLISHED** (2026-03-16). FAQ JSON-LD present. generated_date: 2026-05-21 |
| **Soleur vs. Notion Custom Agents** | soleur vs notion ai, company as a service vs notion | Commercial | P1 | **PUBLISHED** (2026-03-17). generated_date: 2026-06-05 |
| **Soleur vs. Cursor** | soleur vs cursor, cursor automations vs soleur | Commercial | P1 | **PUBLISHED** (2026-03-19). Addresses Automations + Marketplace. |
| **Soleur vs. Polsia** | soleur vs polsia, autonomous AI company, autopilot vs decision-maker | Commercial | P1 | **PUBLISHED** (2026-03-26). FAQ JSON-LD present. generated_date: 2026-03-26 |
| **Soleur vs. Paperclip** | soleur vs paperclip, AI company orchestration, zero-human company, company orchestration open source | Commercial | **P2** (new) | Paperclip at **74,282 GitHub stars** (verified 2026-07-20 via the GitHub API; prior scans read 30,000+ then 53k+); now built on Claude Code. Infrastructure-layer orchestration vs. domain intelligence. Complementary positioning opportunity. Clipmart upcoming. generated_date: 2026-03-31 (page corrected 2026-07-20) |
| **Soleur vs. Devin** | soleur vs devin, AI software engineer vs AI organization, autonomous coding comparison | Commercial | P2 | Devin at $20/month is the price anchor for autonomous agents. Differentiation: engineering-only vs. 8-domain organization. generated_date: 2026-04-21 |
| **Soleur vs. Tanka** | soleur vs tanka, AI co-founder comparison, memory AI platform comparison | Commercial | P3 | Tanka claims memory compounding. Need to differentiate: communication-scoped memory vs. cross-domain business memory. generated_date: 2026-05-05 |
| **Soleur vs. CrewAI** | soleur vs crewai, AI agent framework vs AI organization, multi-agent comparison | Commercial | P3 | Different categories (framework vs. product) but searchers compare them. Honest positioning: CrewAI is for building custom agents, Soleur is a ready-made organization. generated_date: 2026-05-07 |
| **Agent Platform vs. AI Organization** | AI agent platform vs AI organization, build AI company with agents, AI agent framework for founders | Informational | P2 | Position paper (Gap 3 remaining work, content-strategy.md). Selected as the top P1 pick by the 2026-09-24 growth-plan run, but article generation could not complete: the cron sandbox denies Write access to `plugins/soleur/docs/blog/` ("sensitive file"). No article was written. Not annotated generated_date -- still open. Tracked in [issue #8715](https://github.com/jikig-ai/soleur/issues/8715). |
| **Best Claude Code Plugins 2026** | best claude code plugins, top claude code plugins 2026, claude code extensions | Commercial | P2 | High-intent keyword cluster. Soleur should either appear in or create the definitive list. generated_date: 2026-04-30 |

### 2.2 Pillar Content Pages

| Page | Target Keywords | Search Intent | Priority | Status |
|------|----------------|---------------|----------|--------|
| **What Is Company-as-a-Service?** | company as a service, CaaS platform | Informational | P1 | **PUBLISHED** (SAP 5.0/5.0) generated_date: 2026-05-12 |
| **Why Most Agentic Tools Plateau** | agentic engineering, compound knowledge | Informational | P1 | **PUBLISHED** (SAP 4.8/5.0) |
| **Vibe Coding vs Agentic Engineering** | vibe coding vs agentic engineering, agentic coding | Informational | P1 | Month 1. Audit P2-1, score 18/20. generated_date: 2026-03-24 |
| **AI Agents for Solo Founders: The Definitive Guide** | AI agents for solo founders, solopreneur AI tools 2026 | Commercial | P1 | Month 1-2. Audit P2-2, score 18/20. generated_date: 2026-03-24 |
| **One-Person Billion-Dollar Company** | one person billion dollar company, solo founder AI | Informational | P2 | Month 2. generated_date: 2026-04-21 |
| **Knowledge Compounding in AI Development** | knowledge compounding AI, compound engineering | Informational | P2 | Month 2-3. generated_date: 2026-04-23 |

### 2.3 Infrastructure Pages

| Page | Purpose | Priority | Status |
|------|---------|----------|--------|
| **Blog index** (/blog/) | Blog listing page | P0 | **DONE** |
| **About/Founder page** | E-E-A-T authority page with credentials, social links, company details | P1 | NEW -- Gap 11. Month 1. |
| **FAQ sections on all pages** | Structured FAQ content for AI engine consumability. Target: 15/15 pages (currently 3/15). | P1 | In progress (3/15 done) |
| **Page-specific OG images** | Unique social share images per blog post for improved CTR | P2 | NEW -- from 2026-03-17 SEO audit. Month 3. |

---

## Priority 3: Monitoring (Check Monthly)

Pages and keywords to watch for competitive changes. No action needed unless triggers fire.

### 3.1 Competitor Content Monitoring

| Competitor | What to Watch | Trigger for Action | Current Status (2026-06-02) |
|------------|--------------|-------------------|----------------|
| **Anthropic Cowork** | Blog posts, plugin announcements, CaaS positioning, Microsoft Copilot Cowork expansion | Anthropic uses "Company-as-a-Service" or equivalent framing, adds persistent memory, or Copilot Cowork expands beyond M365 workflows | No CaaS framing detected. Microsoft Copilot Cowork launched Mar 9 (Research Preview). Engineering plugins live. |
| **Cursor** | Marketplace business-domain plugins, automation memory expansion, multi-domain features | Cursor marketplace gets marketing/legal/finance plugins, or automation memory becomes cross-domain | **STALE: Requires immediate update.** Automations + 30+ marketplace plugins launched Mar 5. Now an agent platform, not just an IDE. Built-in automation memory that learns from past runs. |
| **Polsia** | Domain expansion, knowledge base, revenue share changes, ARR trajectory | Polsia adds legal/finance/product domains, implements cross-domain knowledge base, or drops revenue share | **Updated 2026-07-20.** Verifiable signal: **raised $30M at a $250M valuation** (Sound Ventures lead, True Ventures participating, May 2026). $49/mo base + 20% rev-share. **All revenue/customer counts are vendor-reported and contradictory across sources — do not cite any as fact.** Third-party reports range from ~$689K run-rate (Feb 2026 Mixergy) to ~$10M ARR / 7,600 customers; prior scans of this row carried $1.5M, then a revised-down $450K+ / 500+ companies. The spread itself is the finding. |
| **Paperclip** | Clipmart launch, knowledge layer, Claude Code adapter, funding | Clipmart ships with curated company templates, Paperclip adds knowledge layer | **Updated 2026-07-20: 74,282 GitHub stars** (verified via the GitHub API; canonical repo **`paperclipai/paperclip`** — the `agencyenterprise/paperclip-ai` ambiguity is RESOLVED, that repo has 6 stars). Prior scans of this row read 30,000+ then 53k+. Now built on Claude Code. v0.3.0 with Cursor/OpenCode/Pi adapters. Clipmart upcoming. |
| **Notion** | Custom Agents updates, engineering agent announcements, solo-founder positioning, post-beta pricing | Notion adds engineering agents or positions Custom Agents for solo founders | Custom Agents launched Feb 24. MiniMax M2.5 support (Mar 3, 10x cheaper). **Beta ended May 3; credit pricing live since May 4** ($10/1,000 credits). |
| **Tanka** | Agent Store expansion, engineering agents, pricing announcements | Tanka adds engineering agents or launches paid pricing | Agent Store planned. Fundraising agent launched. Pricing: free <50 users, $299/mo 50+. |
| **SoloCEO** | Product launch, execution capabilities, pricing | SoloCEO moves from advisory to operational execution | Limited public information. Advisory-only. |
| **OpenAI Codex** | Domain expansion beyond security, Codex platform business agents | Codex adds marketing/legal/finance agents alongside Codex Security | **NEW entrant.** Codex Security launched Mar 6 (first non-coding domain agent). GPT-5.4 with computer-use. |

### 3.2 Keyword Ranking Monitoring

Check these keywords monthly (incognito Google search + Perplexity/ChatGPT query).

| Keyword | Current Ranking | Target | Page |
|---------|----------------|--------|------|
| company as a service | Not ranking | Page 1 | /articles/what-is-company-as-a-service |
| agentic engineering | Not ranking | Page 1-2 | /articles/agentic-engineering |
| one person billion dollar company | Not ranking | Page 1-2 | /articles/billion-dollar-solo-company |
| solo founder AI tools | Not ranking | Page 1-2 | /articles/solopreneur-ai-stack |
| claude code plugins | Not ranking | Page 1-2 | /articles/best-claude-code-plugins |
| soleur | Position 1 (branded) | Maintain | / |
| knowledge compounding AI | Not ranking | Page 1 | /articles/knowledge-compounding |
| soleur vs polsia | Not ranking | Page 1 | /articles/soleur-vs-polsia |
| soleur vs cursor | Not ranking | Page 1 | /articles/soleur-vs-cursor |
| soleur vs paperclip | Not ranking | Page 1 | /articles/soleur-vs-paperclip |
| autopilot vs decision maker AI | Not ranking | Page 1 | /articles/autopilot-vs-decision-maker |
| AI agent platform vs AI organization | Not ranking | Page 1 | /articles/agent-platform-vs-ai-organization |

### 3.3 AEO Citation Monitoring

Monthly check: query these terms in Perplexity, ChatGPT (with search), and Google AI Overview. Track whether Soleur is cited.

| Query | Current Citation | Target |
|-------|-----------------|--------|
| "What is company as a service?" | Not cited | Cited as authority |
| "Best AI platforms for solo founders" | Not cited | Cited in top 5 |
| "What is agentic engineering?" | Not cited | Cited as implementation example |
| "AI tools for one-person companies" | Not cited | Cited |

---

## Refresh Schedule

| Frequency | Action |
|-----------|--------|
| Weekly | Check Plausible for traffic to content pages. Note referral sources. |
| Monthly | Check keyword rankings (incognito search). Check AEO citations. Review competitor content. Update this document. |
| Quarterly | Full SEO audit of all pages. Update keyword targets. Reassess comparison page priorities based on competitive shifts. |

---

## Stale Comparison Pages Flagged for Regeneration (2026-03-12)

Based on competitive intelligence scan of 2026-03-12, the following comparison pages are stale or need creation due to material competitor changes:

| Page | Status | Reason | Priority |
|------|--------|--------|----------|
| **Soleur vs. Cursor** | Stale (if exists) / Create | Cursor shipped Automations (event-driven agents), 30+ marketplace plugins, cloud agents with computer use, built-in automation memory. March 5, 2026. The "Cursor is engineering-only" framing is no longer sufficient -- Cursor is now an agent platform. | P1 |
| **Soleur vs. Polsia** | ~~Create~~ **SUPERSEDED** | generated_date: 2026-07-20. ~~Polsia at $450K+ ARR (revised down from $1.5M), 500+ managed companies.~~ **This row's figures are superseded by the 2026-06-08 block below** (Polsia raised $30M at a $250M valuation, May 2026; all ARR/customer counts are contradictory and unverified). Comparison page published 2026-03-26 and corrected 2026-07-20. Do not regenerate from this row. | P1 |
| **Soleur vs. Anthropic Cowork** | Stale (if exists) / Create | Microsoft Copilot Cowork launched March 9 powered by Anthropic Claude. Dual distribution surface (Anthropic direct + Microsoft 365). Must address the Microsoft partnership and expanded enterprise connectors. | P1 |
| **Soleur vs. Paperclip** | ~~Create~~ **SUPERSEDED** | generated_date: 2026-07-20. ~~Paperclip at 30,000+ GitHub stars (crossed in three weeks)~~ — superseded by the 2026-06-08 block below (74,282 stars verified 2026-07-20). Page published 2026-03-31 and corrected 2026-07-20. Do not regenerate from this row. | P2 |
| **Soleur vs. Notion Custom Agents** | Stale (if exists) / Update | Notion added MiniMax M2.5 support (10x cheaper, March 3). Beta ended May 3; credit pricing ($10/1,000 credits) live since May 4. Update with credit-based pricing analysis. | P2 |
| **Soleur vs. OpenAI Codex** | Create | GPT-5.4 with native computer-use (March 5). Codex Security agent launched (March 6) -- first domain expansion beyond coding. If OpenAI adds more domain agents, Codex becomes a Tier 0 threat. | P3 |
| **Soleur vs. Replit Agent** | Update (if exists) | Agent 4 launched. Parallel agents, ChatGPT integration, $400M Series D at $9B valuation. $20-100/month tiered. | P3 |

---

_Updated: 2026-06-02. Sources: content-audit.md (2026-03-17), aeo-audit.md (2026-03-17), seo-audit.md (2026-03-17), content-plan.md (2026-03-17), competitive-intelligence.md (2026-05-30). Priority 1 items completed in biweekly growth execution 2026-04-01; competitor rows reconciled 2026-06-02._

## Stale Comparison Pages Flagged for Regeneration (2026-06-08)

Flagged by the full six-tier competitive-intelligence scan (`competitive-intelligence.md`, 2026-06-08). These comparison/pillar pages carry figures now contradicted by the latest scan and should be regenerated or corrected.

| Page | Status | Reason | Priority |
|------|--------|--------|----------|
| **Soleur vs. Polsia** | **DONE (2026-07-20)** | generated_date: 2026-07-20. **Trajectory reversed.** Page copy and any prior "$450K ARR / shrinking" framing are wrong: Polsia **raised $30M at a $250M valuation (May 2026)**; newer reports claim ~$10M ARR / 7,600 customers / 85% retention (all unverified). Do not imply Polsia is shrinking. Keep $49 base + 20% rev-share. **Corrected 2026-07-20:** the published page cited vendor-reported ARR/customer figures as fact in both rendered copy and FAQ JSON-LD; it now leads with the funding round and attributes all revenue/customer counts. | P1 |
| **Soleur vs. NanoCorp** | **Create** | NanoCorp (`nanocorp.so`, Phospho/YC) is a Tier 3 autonomous-CaaS competitor with no comparison page. Differentiators: founder-in-the-loop, 8 domains vs. narrow GTM engine, **ads "Coming Soon" not live**, $30/mo + 20% withdrawal fee. Target: "soleur vs nanocorp", "autonomous AI company", "nanocorp alternative". Flag self-reported ARR as unverified/contradictory. | P2 |
| **Soleur vs. Notion Custom Agents** | Stale — Update | **Paywall completed:** Custom Agents now **Business/Enterprise-only**, $10/1,000 credits (free beta ended May 3). Add the "founders priced out of free/Plus Notion agents" angle — Soleur's ICP eviction window. | P2 |
| **Soleur vs. Paperclip** | **DONE (2026-07-20)** | generated_date: 2026-07-20. ~~Stars **30k → 53k+ in first 6 weeks**~~ → **74,282 stars, verified 2026-07-20 via the GitHub API**. **Canonical repo RESOLVED: `paperclipai/paperclip`** (74,282 stars) — `agencyenterprise/paperclip-ai` has 6 stars and is not the project. The published page was corrected 2026-07-20 to `74,000+` (soft floor; the exact count drifts fast). Complementary-not-substitute framing holds. Do not regenerate from this row. | P2 |
| **Soleur vs. Cursor** | Stale — Update | **Composer 2.5 (May 18)**: frontier-quality at ~1/10 cost/token. Six-tier pricing (Hobby/Pro/Pro+/Ultra/Teams/Enterprise). Refresh benchmarks + pricing; keep "engineering-only vs. 8-domain organization." | P3 |
| **Soleur vs. OpenAI Codex** | Create / Update | Codex is now a Tier 0 threat with **Sites** (deploy websites/apps), multi-agent, memory, 90+ plugins, scheduled tasks; $100/mo Pro 5x. If a page exists, it must move from "engineering-only." | P3 |
| **Soleur vs. Tanka** | Stale — Update | Tanka **open-sourced EverMemOS**. Sharpen differentiation: open memory-engine ≠ Soleur's git-tracked, founder-readable, lifecycle-tied cross-domain KB. | P3 |
| **Soleur vs. CrewAI** | Stale — Update | Add scale/funding context: 47.8k stars, 27M+ PyPI downloads, ~2B executions, $18M Series A. Honest "framework vs. ready-made organization" framing holds. | P3 |
| **Best Claude Code Plugins 2026** | Stale — Update | Official marketplace grew 101 → **186 plugins** (June 7). `alirezarezvani/claude-skills` now **337 skills / 5,200+ stars / 12+ tools**. Ensure Soleur's positioning vs. the largest skill library is current. | P3 |

### New monitoring rows (add to §3.1 at next full edit)

- **OpenAI Codex** — now Tier 0 (Sites, multi-agent, memory, 90+ plugins). Trigger: deeper business-domain agents.
- **GitHub Copilot** — metered "AI Credits" billing (June 1), 10–50x agentic-bill backlash. Trigger: pricing-pain content opportunity; monitor sentiment.
- **alirezarezvani/claude-skills** — 337 skills, 12+ tools, Solo Founder persona. Trigger: featured in official Anthropic marketplace.
- **NanoCorp** — Phospho/YC autonomous CaaS. Trigger: ships ads (currently "Coming Soon"), adds engineering/legal/finance domains, or publishes verified ARR.

_Flagged: 2026-06-08. Source: competitive-intelligence.md (2026-06-08, full six-tier scan)._

---

## Auto-Discovered Topics

Topics discovered via `/soleur:growth plan` when the queue was exhausted.

| Topic | Keywords | Source | Generated Date |
|-------|----------|--------|----------------|
| How to Run Every Business Department with AI Agents: A Solo Founder's Playbook | how to run company with AI agents, AI agents for every department, solo founder AI agents, delegate to AI agents, AI organization platform, context engineering solo founder | growth plan (auto-discovered) | 2026-05-14 |

---

## Stale Comparison Pages Flagged for Regeneration (2026-11-01)

Downstream sync from the 2026-11-01 scheduled CI scan (Tiers 0 and 3). **That scan could not do web research** (the cron containment hook denied `WebSearch`/`WebFetch`), so the CI index has **no new web facts this run**. Every flag below compares live page source under `plugins/soleur/docs/` with facts the index already held. Nothing here was re-verified on 2026-11-01.

> **Regeneration gate.** Tier 0 facts date from the **2026-06-08** scan. Tier 3 facts date from each competitor's own intake (2026-06-08 full scan; Cofounder 2026-06-14 / 2026-07-22; Multica 2026-07-04; Paperclip stars 2026-07-20; Sutra 2026-10-06; HumanLayer 2026-10-24). **For any row tagged `time-sensitive`, hold regeneration until the next unblocked scan, or run it together with that scan.** Those rows cover prices, credits, promos, star counts, funding and release names. Rows tagged `structural` fix framing or taxonomy errors that do not depend on fresh numbers, so they can go ahead now. Every CI shard is `publishable: internal`. Public copy must cite primary sources directly, never the shard.

### A. Existing pages: stale-check inventory

| # | Page (source) | Last date in source | Competitor claim on page | Current index position (fact date) | Verdict | Class | Priority |
|---|---|---|---|---|---|---|---|
| A1 | Soleur vs. Notion Custom Agents (`blog/2026-03-17-soleur-vs-notion-custom-agents.md`) | date 2026-03-17, no `updated` | "currently in free beta through May 3, 2026"; comparison table says "Current availability: Free beta (Business and Enterprise plans)"; the FAQ and JSON-LD still use future tense ("From May 4…") | Free exploration ended May 3. Since May 4 agents run on credits at $10/1,000 and are **Business/Enterprise-only; Free and Plus excluded** (2026-06-08) | **STALE, contradicted.** The page presents a lapsed beta as current, in body copy, the table and FAQ JSON-LD. The 2026-06-08 "paywall + ICP eviction" item is still unactioned. The page's "$20/seat Business plan" figure is not in the index, so re-verify it before republishing | Structural (tense and availability fix); the price figures are time-sensitive | **P1** |
| A2 | Soleur vs. Cursor (`blog/2026-03-19-soleur-vs-cursor.md`) | date 2026-03-19, no `updated` | Framed around March Automations; pricing list Hobby / Pro $20 / Pro+ $60 / Ultra $200 / Teams $40; "$2B+ ARR" (Feb 2026, TechCrunch); no Composer model mentioned | Composer 2.5 (May 18) at about 1/10 the cost per token; six tiers including Enterprise and a Teams Premium seat at $120 (2026-06-08). **The index itself flags "Composer 2.5 as latest" as unconfirmed since June** | **STALE.** The 2026-06-08 P3 item is still open. The engineering-only versus 8-domain framing still holds | Time-sensitive (model names, pricing) | P3; wait for the unblocked scan |
| A3 | Compare: Soleur vs. Cursor (`pages/compare-soleur-vs-cursor.njk`) | `last_updated: 2026-10-22` | Qualitative only ("scoped to software engineering"); no prices or model names found | Consistent | **OK.** No action. Add a link to and from A2 when A2 is regenerated (see C) | — | — |
| A4 | Soleur vs. Anthropic Cowork (`blog/2026-03-16-soleur-vs-anthropic-cowork.md`) | `updated: 2026-05-21` | "10 plugin categories" (HR, Design, Engineering, Ops, Finance [IB/ER/PE/WM], Brand Voice); "15+" enterprise connectors; Copilot Cowork add-on $30/user, M365 E7 $99/user | The Feb 24 expansion shipped **13 MCP connectors** plus industry plugins for HR, IB, ER, design, engineering, ops, PE and WM. Convergence risk is **Critical, with 7+ of 8 Soleur domains facing first-party competition**; engineering-lifecycle orchestration is the last gap (2026-06-08) | **STALE, partly contradicted.** The connector count (15+ vs. 13) and the category taxonomy disagree with the index. The page also understates convergence ("covers the same territory… on paper"). The Microsoft pricing is not in the index, so re-verify it | Structural (convergence framing); the connector counts and M365 pricing are time-sensitive | P2 |
| A5 | Soleur vs. Polsia (`blog/2026-03-26-soleur-vs-polsia.md`) | `updated: 2026-07-20` | Leads with the $30M at $250M raise (May 2026); ARR attributed and marked contradictory; $49/mo plus 20% rev-share | Matches the index (Polsia shard, 2026-06-08 / 2026-07-20) | **OK as of 2026-07-20, not re-verified.** The "ARR claims contradictory" point is an open item for the next scan. Regenerate only if that scan changes the funding, pricing or rev-share figures | Time-sensitive | Monitor |
| A6 | Soleur vs. Paperclip (`blog/2026-03-31-soleur-vs-paperclip.md`) | `updated: 2026-07-20` | "74,000+ GitHub stars", canonical `paperclipai/paperclip`; v0.3.0 adapters; "Clipmart upcoming"; the FAQ and JSON-LD call Paperclip and Soleur "the two most prominent self-hosted platforms" | 74,282 stars at 2026-07-20 (GitHub API); canonical repo resolved (Recommendations P3). **Index inconsistency:** the Tier 3 overlap-matrix Paperclip row still reads "53k+" and "Org/repo ambiguity to track". That row is out of date, so the page is right and the row is wrong | **OK as of 2026-07-20, not re-verified.** The star count is about 3.5 months old and the index says it is "climbing". Clipmart status was never re-checked | Time-sensitive (stars, Clipmart) | P3; refresh at the next scan. **Do not regenerate from the Tier 3 matrix row** (53k / ambiguity); use the 2026-07-20 GitHub API figure or a fresh pull |
| A7 | Soleur vs. Tanka (`blog/2026-05-05-soleur-vs-tanka.md`) | date 2026-05-05, no `updated` | EverMemOS described as Tanka technology with no open-source status; pricing Free (<50) / Plus $29 / Pro $199 / "$299/month for teams of 50+"; Agent Store "planned" | **EverMemOS is now fully open source**; pricing listed as Free (<50 members) / Plus $29 / Pro $199, with no $299 tier (2026-06-08) | **STALE.** The 2026-06-08 item is still open. The $299 team tier does not appear in the index, so verify it or remove it | Structural (open-source framing); pricing is time-sensitive | P3 |
| A8 | Soleur vs. CrewAI (`blog/2026-05-07-soleur-vs-crewai.md`) | date 2026-05-07, no `updated` | "over 45,000 GitHub stars"; no funding or scale context | 47.8k stars (Apr 2026), 27M+ PyPI, about 2B executions, $18M Series A (2026-06-08) | **STALE, understated.** The 2026-06-08 item is still open | Time-sensitive (stars) | P3 |
| A9 | Best Claude Code Plugins 2026 (`blog/2026-04-30-best-claude-code-plugins-2026.md`) | date 2026-04-30, no `updated` | Official marketplace "100+" in body and FAQ JSON-LD; "4,200+ skills / 770+ MCP servers" (Apr 2026); `alirezarezvani/claude-skills` not mentioned | Official marketplace at **186** (Jun 7, 2026); ecosystem at 20,300+ skills, 2,500+ marketplaces, 9,900+ MCP servers; alirezarezvani at 337 skills and 5,200+ stars (2026-06-08). **The index flags the 186 count as unconfirmed since June** | **STALE, understated by about 2x to 10x.** The 2026-06-08 item is still open | Time-sensitive | P2; pair with the next scan |
| A10 | Skill Libraries vs. Workflow Plugins (`blog/2026-05-15-skill-libraries-vs-workflow-plugins.md`) | date 2026-05-15, no `updated` | Describes alirezarezvani/claude-skills as covering "common developer needs (research workflows, data wrangling, documentation generation, project scaffolding)" | 9 domains (engineering, marketing, product, compliance, C-level, research, biz-ops, finance, productivity), an explicit Solo Founder persona, cross-domain orchestration, 12+ tools; **Critical, closest structural match** (2026-06-08) | **STALE, contradicted.** The page casts the closest structural competitor as a developer-only catalog, which understates it on the exact axes Soleur claims as moats | Structural (scope framing); the counts are time-sensitive | **P2** |
| A11 | What Is Company-as-a-Service? pillar (`pages/company-as-a-service.njk`) | — | Lovable "reached $200 million in ARR" (TechCrunch, Nov 2025); $330M raise at $6.6B | $400M annualized revenue (Feb 2026); $330M Series B at $6.6B (2026-06-08) | **STALE, understated.** The ARR figure is two data points old | Time-sensitive | P3 |
| A12 | Compare: Soleur vs. Devin (`pages/compare-soleur-vs-devin.njk`) and blog (`blog/2026-04-21-soleur-vs-devin.md`) | `last_updated: 2026-10-22` (compare) | Devin 2 at $20/mo entry | Devin has no row in the index. The only coverage is that Windsurf 2.0 embedded Devin (April 2026) | **Cannot assess; no index coverage.** Add Devin/Cognition to the next scan's Tier 0 or 5 scope if this page is kept | — | Monitor |

### B. Missing high-value pages

| # | Proposed page | URL patterns | Index basis | Gate before creation | Priority |
|---|---|---|---|---|---|
| B1 | **Soleur vs. Cofounder** (+ "Cofounder alternatives") | `/blog/soleur-vs-cofounder/`, `/blog/cofounder-alternatives/` | Tier 3, **Critical, closest product match**: $8.7M USV seed; HITL gates; multi-department breadth; no rev-share plus ownership graduation; Pro $20/mo, Team $50/mo "coming soon" (source-verified 2026-07-22) | **Needs primary-source re-verification before publishing.** The Cofounder shard is `publishable: internal`, and it states that a **bare department count must not be cited as verified** (11 functional areas on the landing page vs. "8" in the index row, with legal absent). "No revenue share" is also graded, not flat fact. The open scan item (has Team $50 launched?) must be resolved first. Write against the 3 moats the shard says hold: a git-tracked verbatim KB in the founder's repo, the named-artifact lifecycle, and founder-owned repos from day one. **Do not** lead with founder-in-the-loop or breadth, which Cofounder neutralizes. The positioning rewrite (#6827, NG2) should land first or alongside | **P1** (highest-overlap competitor with no page) |
| B2 | **Soleur vs. NanoCorp** (+ "NanoCorp alternative") | `/blog/soleur-vs-nanocorp/` | Tier 3 High: Phospho Inc./YC; 20% withdrawal fee; ads "Coming Soon"; contradictory ARR (2026-06-08) | Still open from 2026-06-08. **Time-sensitive:** the ads status and ARR are open scan items. Re-verify against nanocorp.so; cite no ARR figure as fact | P2; pair with the next scan |
| B3 | **Soleur vs. OpenAI Codex** | `/blog/soleur-vs-openai-codex/` | Tier 0 **Critical**: Sites, multi-agent, memory, 90+ plugins, scheduled tasks, Pro promo expired May 31 (2026-06-08) | Still open from 2026-06-08. **Time-sensitive:** the index flags Codex Sites "preview" status as unconfirmed since June | P2; wait for the unblocked scan |
| B4 | **Soleur vs. GitHub Copilot** (metered-billing angle) | `/blog/soleur-vs-github-copilot/` | Tier 0 High: AI Credits since June 1, 10–50x agentic-bill backlash (2026-06-08) | **Do not draft from current index data.** The "promo credits ($30/user Business, $70/user Enterprise) through Aug 2026" line has **lapsed on its stated terms**, and all billing figures are 5 months old. Use only after a fresh scan. Brand note: the message is "predictable + you own your memory", not "free" (CI Rec P1 #3) | P3; blocked on the scan |
| B5 | Soleur vs. Multica / Soleur vs. HumanLayer | — | Tier 3 Medium–High and Medium; both are opposite-ICP design donors (shards `publishable: internal`) | **Not recommended.** Different ICP (engineering teams), so search intent from Soleur's ICP is low. Revisit only on demand signals | Not queued |
| — | Sutra | — | Internal-only watch entry | **Excluded: no public comparison page** (index New Entrants #12) | Never |
| — | Omnigent | — | Tier 4 watch-only | **Excluded.** Do not claim "runs on", "compatible with" or "supports" Omnigent on any page | Never |

### C. Internal linking requirements for regenerated and new pages

| Page | Must link to (≥2 in-set + product) |
|---|---|
| A1 Notion | A4 Cowork, B1 Cofounder (once published), `/pricing/` |
| A2 Cursor (blog) | A3 compare-cursor, A12 Devin, `/pricing/` |
| A4 Cowork | A9 Best Plugins, A1 Notion, `/company-as-a-service/` |
| A7 Tanka | B1 Cofounder (memory contrast), A5 Polsia, `/pricing/` |
| A8 CrewAI | A6 Paperclip, A10 Skill Libraries, `/company-as-a-service/` |
| A9 Best Plugins | A10 Skill Libraries, A4 Cowork, `/getting-started/` |
| A10 Skill Libraries | A9 Best Plugins, A8 CrewAI, `/getting-started/` |
| B1 Cofounder | A5 Polsia, B2 NanoCorp, A6 Paperclip, `/pricing/` |
| B2 NanoCorp | A5 Polsia, B1 Cofounder, `/pricing/` |
| B3 Codex / B4 Copilot | A2 Cursor, A3 compare-cursor, `/pricing/` |

### D. Section 3.1 monitoring rows: carry-forward and corrections (apply at the next full edit)

- **Paperclip:** the 74,282 / `paperclipai/paperclip` row (2026-07-20) stands. Flag back to CI that the Tier 3 overlap-matrix Paperclip row still carries the superseded "53k+ / ambiguity" text.
- **Cursor:** the "STALE: Requires immediate update" text in 3.1 is about the March Automations framing. The blog page now needs the Composer 2.5 and pricing refresh (A2), which is time-sensitive.
- **GitHub Copilot** (added 2026-06-08 under "New monitoring rows"): the promo-credit window "through Aug 2026" has **expired on its stated terms**. Do not cite it as live.
- **Add:** a **Cofounder** row. Trigger for action: Team $50/mo tier launches, a legal department is added, or rev-share changes.
- **Add:** a **Devin/Cognition** scope request to CI, since two live pages (A12) have no index coverage.

_Flagged: 2026-11-01. Source: competitive-intelligence.md (2026-11-01 index, blocked scan; no new web facts) plus the per-competitor shards. Facts are dated to their intakes and were not re-verified on 2026-11-01. Comparison pages were not edited._
