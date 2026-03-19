---
last_updated: 2026-03-12
last_reviewed: 2026-03-12
review_cadence: monthly
depends_on:
  - knowledge-base/overview/competitive-intelligence.md
  - knowledge-base/overview/content-strategy.md
  - knowledge-base/audits/soleur-ai/2026-02-19-content-audit.md
---

# SEO Refresh Queue

This document tracks pages that need SEO updates, new pages that should be created for search visibility, and pages that need monitoring for competitive changes. Reviewed monthly.

---

## Priority 1: Stale Pages (Update Immediately)

Pages that exist on soleur.ai but have SEO deficiencies identified in the content audit (2026-02-19).

### 1.1 Homepage (soleur.ai/)

| Issue | Current State | Action | Effort |
|-------|--------------|--------|--------|
| H1 targets no searchable query | "Build a Billion-Dollar Company. Alone." | Keep as brand statement but add keyword-rich H2 or subtitle containing "Company-as-a-Service" and "solo founders" | Low |
| Zero target keywords in body copy | "agentic company", "agentic engineering", "company as a service", "solo founder" all absent | Rewrite section labels, H2s, and body paragraphs to include target keywords naturally. See content-audit.md Section 4 for specific rewrites. | Low |
| Badge is only instance of "Company-as-a-Service" | Badge text, low SEO weight | Add "Company-as-a-Service" to at least one H2 and one body paragraph | Low |
| No FAQ schema | Absent | Add FAQ section with 3-5 questions. Add FAQPage JSON-LD schema. | Medium |
| No internal links with keyword-rich anchor text | CTAs say "Start Building", "Read the Docs" | Change to "See the 61 AI agents", "Start building your AI organization" | Low |

**Combined effort:** 3-4 hours.

### 1.2 Agents Page (soleur.ai/pages/agents.html)

| Issue | Current State | Action | Effort |
|-------|--------------|--------|--------|
| H1 is bare "Agents" | No modifier | Change to "AI Agents" or "AI Engineering Agents" | Low |
| No introductory prose | One-sentence hero | Add 2-3 paragraph intro explaining what agentic engineering means, why 61 agents across 8 domains, and how they share context | Low |
| No FAQ section | Absent | Add FAQ: "What are AI agents?", "How many agents does Soleur have?", "What domains do the agents cover?" | Low |

**Combined effort:** 1-2 hours.

### 1.3 Skills Page (soleur.ai/pages/skills.html)

| Issue | Current State | Action | Effort |
|-------|--------------|--------|--------|
| H1 is bare "Skills" | No modifier | Change to "Agentic Engineering Skills" or "AI Workflow Skills" | Low |
| No introductory prose | One-sentence hero | Add 2-3 paragraphs explaining the brainstorm-plan-implement-review-compound lifecycle | Low |

**Combined effort:** 1 hour.

### 1.4 Getting Started Page (soleur.ai/pages/getting-started.html)

| Issue | Current State | Action | Effort |
|-------|--------------|--------|--------|
| No "What is Soleur?" context | Jumps to install command | Add paragraph before install: "Soleur is a Company-as-a-Service platform for solo founders..." with all 5 target keywords | Low |
| "Claude Code" never mentioned | Assumed knowledge | Add one sentence: "Soleur runs as a Claude Code plugin..." (permitted per brand guide technical docs exception) | Low |

**Combined effort:** 30 minutes.

### 1.5 llms.txt

| Issue | Current State | Action | Effort |
|-------|--------------|--------|--------|
| Generic description | "Claude Code plugin providing 32 AI agents..." | Rewrite with platform positioning and target keywords (see content-audit.md Section 4.9) | Low |
| Agent/skill counts outdated | States 32 agents, 41 skills | Update to 61 agents, 56 skills, 3 commands | Low |

**Combined effort:** 15 minutes.

---

## Priority 2: New Pages (Create in Phase 1-2)

Pages that do not exist but should, based on keyword research and competitive positioning needs.

### 2.1 Comparison Pages

| Page | Target Keywords | Search Intent | Priority | Reason |
|------|----------------|---------------|----------|--------|
| **Soleur vs. Anthropic Cowork** | soleur vs cowork, claude code plugin vs cowork, AI agent platform comparison | Commercial | P1 | Cowork is the #1 competitive threat. Founders choosing between Soleur and free Cowork plugins need a clear comparison. | generated_date: 2026-03-16 |
| **Soleur vs. Notion Custom Agents** | soleur vs notion ai, AI agents for solo founders vs notion, company as a service vs notion | Commercial | P1 | Notion 3.3 Custom Agents (Feb 24, 2026) is the highest Tier 3 convergence risk. 35M+ Notion users may see Custom Agents as CaaS. | generated_date: 2026-03-17 |
| **Soleur vs. Cursor** | soleur vs cursor, AI coding agents comparison, claude code plugin vs cursor, cursor automations vs soleur | Commercial | **P1** (upgraded from P2) | Cursor shipped Automations + Marketplace (March 5, 2026). Now an agent platform, not just an IDE. "I already use Cursor" objection harder to answer. Must address automations, marketplace, and built-in memory. |
| **Soleur vs. Polsia** | soleur vs polsia, autonomous AI company, AI runs your company, autopilot vs decision-maker | Commercial | **P1** | Polsia at $1.5M ARR, 2,000+ companies. Most direct CaaS competitor. Philosophy split: autonomous vs. human-in-the-loop. Pricing comparison: $29-59 + revenue share vs. $49 flat. |
| **Soleur vs. Paperclip** | soleur vs paperclip, AI company orchestration, zero-human company, company orchestration open source | Commercial | **P2** (new) | Paperclip at 14.6k GitHub stars. Infrastructure-layer orchestration vs. domain intelligence. Complementary positioning opportunity. Clipmart upcoming. |
| **Soleur vs. Devin** | soleur vs devin, AI software engineer vs AI organization, autonomous coding comparison | Commercial | P2 | Devin at $20/month is the price anchor for autonomous agents. Differentiation: engineering-only vs. 8-domain organization. |
| **Soleur vs. Tanka** | soleur vs tanka, AI co-founder comparison, memory AI platform comparison | Commercial | P3 | Tanka claims memory compounding. Need to differentiate: communication-scoped memory vs. cross-domain business memory. |
| **Soleur vs. CrewAI** | soleur vs crewai, AI agent framework vs AI organization, multi-agent comparison | Commercial | P3 | Different categories (framework vs. product) but searchers compare them. Honest positioning: CrewAI is for building custom agents, Soleur is a ready-made organization. |
| **Best Claude Code Plugins 2026** | best claude code plugins, top claude code plugins 2026, claude code extensions | Commercial | P2 | High-intent keyword cluster. Soleur should either appear in or create the definitive list. |

### 2.2 Pillar Content Pages

| Page | Target Keywords | Search Intent | Priority | Timeline |
|------|----------------|---------------|----------|----------|
| **What Is Company-as-a-Service?** | company as a service, CaaS platform, full-stack AI organization | Informational | P1 | Week 2 |
| **The Billion-Dollar Solo Company** | one person billion dollar company, solo founder AI, billion dollar solo company 2026 | Informational | P1 | Week 2-3 |
| **Agentic Engineering: Beyond Vibe Coding** | agentic engineering, compound engineering, vibe coding vs agentic engineering | Informational | P1 | Week 3-4 |
| **Knowledge Compounding in AI Development** | knowledge compounding AI, AI agent memory, compound engineering methodology | Informational | P2 | Week 7-8 |
| **The Solopreneur AI Stack** | solopreneur AI stack 2026, solo founder AI tools, one person SaaS AI | Commercial | P2 | Week 5-6 |

### 2.3 Infrastructure Pages

| Page | Purpose | Priority |
|------|---------|----------|
| **Articles index** (/articles/) | Blog listing page. Required before any articles can be published. | P0 (Week 1) |
| **FAQ page** (or FAQ sections on existing pages) | Structured FAQ content for AI engine consumability | P1 |

---

## Priority 3: Monitoring (Check Monthly)

Pages and keywords to watch for competitive changes. No action needed unless triggers fire.

### 3.1 Competitor Content Monitoring

| Competitor | What to Watch | Trigger for Action | Current Status (2026-03-12) |
|------------|--------------|-------------------|----------------|
| **Anthropic Cowork** | Blog posts, plugin announcements, CaaS positioning, Microsoft Copilot Cowork expansion | Anthropic uses "Company-as-a-Service" or equivalent framing, adds persistent memory, or Copilot Cowork expands beyond M365 workflows | No CaaS framing detected. Microsoft Copilot Cowork launched Mar 9 (Research Preview). Engineering plugins live. |
| **Cursor** | Marketplace business-domain plugins, automation memory expansion, multi-domain features | Cursor marketplace gets marketing/legal/finance plugins, or automation memory becomes cross-domain | **STALE: Requires immediate update.** Automations + 30+ marketplace plugins launched Mar 5. Now an agent platform, not just an IDE. Built-in automation memory that learns from past runs. |
| **Polsia** | Domain expansion, knowledge base, revenue share changes, ARR growth | Polsia adds legal/finance/product domains, implements cross-domain knowledge base, or drops revenue share | **NEW entrant.** $1.5M ARR, 2,000+ companies. $29-59/month tiers. Fastest CaaS traction. |
| **Paperclip** | Clipmart launch, knowledge layer, Claude Code adapter, funding | Clipmart ships with curated company templates, Paperclip adds knowledge layer | **NEW entrant.** 14.6k GitHub stars. v0.3.0 with Cursor/OpenCode/Pi adapters. Clipmart upcoming. |
| **Notion** | Custom Agents updates, engineering agent announcements, solo-founder positioning, post-beta pricing | Notion adds engineering agents or positions Custom Agents for solo founders. Post-beta pricing (May 2026) | Custom Agents launched Feb 24. MiniMax M2.5 support (Mar 3, 10x cheaper). Free beta through May 3. |
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
| **Soleur vs. Polsia** | Create | Polsia at $1.5M ARR, 2,000+ managed companies. $29-59/month tiers. Most direct CaaS competitor. Fully autonomous vs. Soleur's founder-in-the-loop. No existing comparison page. | P1 |
| **Soleur vs. Anthropic Cowork** | Stale (if exists) / Create | Microsoft Copilot Cowork launched March 9 powered by Anthropic Claude. Dual distribution surface (Anthropic direct + Microsoft 365). Must address the Microsoft partnership and expanded enterprise connectors. | P1 |
| **Soleur vs. Paperclip** | Create | Paperclip at 14.6k GitHub stars. Open-source orchestration for zero-human companies. Infrastructure-layer vs. domain intelligence framing. Clipmart upcoming. Complementary positioning opportunity. | P2 |
| **Soleur vs. Notion Custom Agents** | Stale (if exists) / Update | Notion added MiniMax M2.5 support (10x cheaper, March 3). Post-beta pricing ($10/1,000 credits) starts May 2026. Update with credit-based pricing analysis. | P2 |
| **Soleur vs. OpenAI Codex** | Create | GPT-5.4 with native computer-use (March 5). Codex Security agent launched (March 6) -- first domain expansion beyond coding. If OpenAI adds more domain agents, Codex becomes a Tier 0 threat. | P3 |
| **Soleur vs. Replit Agent** | Update (if exists) | Agent 4 launched. Parallel agents, ChatGPT integration, $400M Series D at $9B valuation. $20-100/month tiered. | P3 |

---

_Updated: 2026-03-12. Sources: content-audit.md (2026-02-19), content-plan.md (2026-02-19), competitive-intelligence.md (2026-03-12)._
