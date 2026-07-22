---
last_updated: 2026-06-08
last_reviewed: 2026-06-08
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

---

## Priority 1: Stale Pages (Update Immediately)

Pages that exist on soleur.ai but have SEO deficiencies identified in the content audit (2026-02-19).

### 1.1 Homepage (soleur.ai/) [PARTIALLY DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 targets no searchable query | "Build a Billion-Dollar Company. Alone." | Keep as brand statement but add keyword-rich H2 or subtitle | Low | **Done** -- keyword-rich H2 added |
| Zero target keywords in body copy | Keywords added to H2s and body paragraphs | — | — | **Done** |
| Badge is only instance of "Company-as-a-Service" | Now in H2 and body text | — | — | **Done** |
| No FAQ schema | 6 FAQ items with FAQPage JSON-LD | — | — | **Done** |
| No internal links with keyword-rich anchor text | CTAs updated | — | — | **Done** |
| "Plugin" in meta description and FAQ texts | Meta description and 3 FAQ answers use "plugin" | Remove "plugin" per brand guide. Rewrite meta to: "Soleur is the open-source company-as-a-service platform..." | Low | **Done -- meta rewritten 2026-04-01** |
| Missing "open source" and "solopreneur" | Not present on homepage | Add to hero section or body text | Low | **Done -- "solopreneur" added to meta and FAQ answer 2026-04-01** |

**Remaining effort:** 1-2 hours (new items only).

### 1.2 Agents Page (soleur.ai/pages/agents.html) [PARTIALLY DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 is bare "Agents" | Now "Soleur AI Agents" | — | — | **Done** |
| No introductory prose | Intro paragraph added | — | — | **Done** |
| No FAQ section | 3 FAQ items exist but no JSON-LD FAQPage schema | Add FAQPage JSON-LD to match existing HTML FAQ | Low | **Done -- FAQPage JSON-LD present** |
| Missing "open source AI agents" keyword | Not mentioned | Add note that agents are open source and inspectable | Low | **Done -- added to intro prose 2026-04-01** |
| No definition of "agentic engineering" | Term used without definition | Add one-sentence definition near first usage | Low | **Done -- definition present in intro** |

**Remaining effort:** 1 hour (new items only).

### 1.3 Skills Page (soleur.ai/pages/skills.html) [PARTIALLY DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 is bare "Skills" | Now "Agentic Engineering Skills" | — | — | **Done** |
| No introductory prose | Lifecycle explanation added | — | — | **Done** |
| No FAQ section | Absent | Add FAQ with JSON-LD: "What is a skill in Soleur?", "How do skills differ from agents?" | Low | **Done -- FAQ + JSON-LD present** |
| Missing "AI workflow automation" keyword | Not present | Add commercially-searched term naturally | Low | **Done -- added to intro prose 2026-04-01** |

**Remaining effort:** 1 hour (new items only).

### 1.4 Getting Started Page (soleur.ai/pages/getting-started.html) [PARTIALLY DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| No "What is Soleur?" context | Context paragraph added | — | — | **Done** |
| "Plugin" in meta description | "Install the Soleur Claude Code plugin..." | Rewrite meta to: "Get started with Soleur in one command..." | Low | **Done -- meta already correct** |
| No FAQ section | Absent | Add FAQ: installation, pricing, prerequisites | Low | **Done -- FAQ + JSON-LD present** |

**Remaining effort:** 30 minutes (new items only).

### 1.5 llms.txt [DONE]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| Generic description | Rewritten with platform positioning | — | — | **Done** |
| Agent/skill counts outdated | Updated to current counts | — | — | **Done** |

### 1.6 Vision Page (soleur.ai/pages/vision.html) [NEW -- from 2026-03-17 audit]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| H1 is "Vision" -- zero keyword value | Single generic word | Rewrite to "The Soleur Vision: Building the Company-as-a-Service Platform" | Low | **Done -- H1 is "The Soleur Vision: Company-as-a-Service for the Solo Founder"** |
| Uses "synthetic labor," "soloentrepreneurs" | Not in brand guide vocabulary | Align with brand voice | Low | **Done -- "synthetic labor" replaced with "AI agent swarms" 2026-04-01** |
| No FAQ section | Absent | Add FAQ: roadmap, model-agnostic, CaaS | Low | **Done -- FAQ + JSON-LD present** |
| No external citations | Zero | Add 1-2 authoritative citations | Low | **Done -- Dario Amodei citation added 2026-04-01** |

**Combined effort:** 1-2 hours.

### 1.7 Blog Posts -- dateModified Signals [NEW -- from 2026-03-17 SEO audit]

| Issue | Current State | Action | Effort | Status |
|-------|--------------|--------|--------|--------|
| No `updated` frontmatter on any blog post | `dateModified` always equals `datePublished` in BlogPosting JSON-LD | Add `updated` field to blog posts that have been revised | Low | **Done -- `updated: 2026-04-01` added to Why Tools Plateau post** |
| No visible "Last Updated" display | Only `datePublished` shown | Add conditional "Last Updated" display to `blog-post.njk` template | Low | **Done -- conditional Last Updated added to blog-post.njk 2026-04-01** |
| "Why Tools Plateau" FAQ missing JSON-LD | 3 FAQ items formatted as H3 headings, no FAQPage schema | Convert to `<details>/<summary>` + add JSON-LD | Low | **Done -- converted to details/summary + FAQPage JSON-LD added 2026-04-01** |

**Combined effort:** 1-2 hours.

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
