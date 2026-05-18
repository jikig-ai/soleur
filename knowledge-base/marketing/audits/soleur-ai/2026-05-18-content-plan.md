---
plan_date: 2026-05-18
plan_type: prioritized-content-plan
scope: soleur.ai (post-audit synthesis)
inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-05-18-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-05-18-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-05-18-seo-audit.md
brand_guide: knowledge-base/marketing/brand-guide.md (read and applied)
owner: CMO
issue_refs:
  - "#2615 (Presence >= 55/D exit criterion — currently failing at 48)"
---

# Soleur.ai Prioritized Content Plan — 2026-05-18

## Executive Summary

Three audits ran on 2026-05-18 against the deploy source-of-truth because **the live site at https://soleur.ai/ returned Cloudflare HTTP 526 (origin SSL handshake failure) for every HTML and XML route except `/robots.txt`**. The SEO audit graded the live surface at **0/100 (F)**; the AEO audit graded the underlying corpus at **68/100 (C)** with **Presence at 12/25 (48%) — failing the issue #2615 exit criterion of `Presence >= 55/D`**; the content audit found **7 critical issues** including `{{ stats.agents }}` interpolation drift in prose, the `/about/` page using "About" as its H1, and "Company-as-a-Service" capitalized inconsistently across pages.

The trajectory is recoverable. The 2026-05-04 baseline was 65/C; the 2026-05-18 corpus scored 68/C, a **+3 net** driven by the Company-as-a-Service pillar's expanded citation set (BLS, CNBC, TechCrunch, VentureBeat, Karpathy). But the live 526 outage **nullifies every gain** for AI crawlers (Perplexity, ChatGPT browsing, Claude.ai, Gemini) until origin is restored. Zero availability = zero presence.

This plan sequences the work into four priority bands:

- **P0 (today, infra-blocking):** Fix the Cloudflare 526 so any AEO/SEO signal can be measured live.
- **P1 (this week, 4-8 hours):** Eliminate the seven critical content issues, add `last_updated` metadata to evergreen pages, and add stat-led summary paragraphs under every H1 to win AI extraction.
- **P2 (next sprint, 1-2 weeks):** Close the Presence gap with citation monitoring, press-strip expansion, and surfaced commercial-investigation H2s for "Soleur vs Cursor" / "Claude Code plugin" queries.
- **P3 (next cycle, 2-4 weeks):** Build the cluster content the keyword research surfaces — agentic engineering, solo founder AI tools, AI company automation — each linked back to the Company-as-a-Service pillar.

The plan is mostly **searchable**: the keyword research below identifies high-intent informational, commercial-investigation, and navigational queries Soleur is not currently capturing. Two **shareable** pieces are added to P3 (the "Soleur changelog post-mortem" narrative and a founder-voice essay on agentic engineering) so the content mix is not 100% search-optimized.

---

## P0 — Blocker (infra-class; content plan cannot ship until resolved)

| Ref | Action | Expected impact | Effort |
|-----|--------|-----------------|--------|
| **P0-1** | **Restore origin SSL so soleur.ai returns 200, not 526.** Inspect origin TLS cert (expiry, hostname match, chain), Cloudflare SSL/TLS mode (Full vs Full-strict vs Flexible), and whether the recent `seo_page_redirects` ruleset (commit `54ce580`) is masking an origin pull config change. Hand off to seo-aeo-analyst / infra owner immediately. Once live, re-run all three audits before shipping P1 edits. | Unblocks every AEO/SEO/content gain below. Without this, the AI crawlers that drive Soleur's biggest near-term distribution channel (Perplexity, ChatGPT browsing, Claude.ai, Gemini) return 526 for every URL and cannot refresh cached content. Repeated 5xx → soft de-indexing in Google Search within days. | 1-4 hours of infra work; not content-class. |
| **P0-2** | Add origin-uptime monitoring with alerting on first 5xx, if not already in place. A 526 is silently catastrophic for SEO — no visible UI break for whitelisted internal users, failure mode only manifests in crawler logs days later. | Prevents recurrence. Catches the next 526 in minutes, not at the next audit. | 1 hour of infra setup. |
| **P0-3** | Once HTTP 200 is restored: submit the sitemap to Google Search Console, request re-indexing on `/`, `/blog/`, `/pricing/`, `/agents/`, and the top three blog posts. Check Coverage report 24-48 hours later for any URL flagged `Server error (5xx)`. | Shortens crawler-recovery window from "next natural recrawl" to ~48 hours. | 30 minutes once origin is healthy. |

---

## P1 — This week (critical content fixes + AEO foundations)

All seven critical content issues from the content audit, plus the two highest-leverage AEO recommendations (`last_updated` metadata, stat-led summary paragraphs). Total estimated effort: **4-8 hours of edits across six `.njk` files**.

| Ref | Action | Expected impact | Effort | Target keywords |
|-----|--------|-----------------|--------|-----------------|
| **P1-1** | **C-1, C-3: Apply soft-floor counts in prose** across `index.njk` (hero sub + final CTA + 3 FAQ answers + JSON-LD FAQ block) and `pricing.njk` (Plans subhead). Replace `{{ stats.agents }}` with `60+` and `{{ stats.skills }}` with `60+` in narrative copy only. Keep `{{ stats.* }}` interpolation in stat strips, tables, and structured-data numeric fields. Per brand guide §Numbers. | Removes drift hazard (today's "66 agents" becomes tomorrow's "72 agents" in cached AI answers). Restores brand-guide compliance on the highest-traffic page. | 30 min find-and-replace across 5 files. | "AI agents for solo founders", "Company-as-a-Service" |
| **P1-2** | **C-2: Capitalize "Company-as-a-Service" consistently** as a proper noun across `index.njk`, `pricing.njk`, `about.njk`, `vision.njk`, `getting-started.njk`, `company-as-a-service.njk`. Update FAQ JSON-LD `name` fields to match. Per brand guide §Tagline. | Cleans entity-clarity signal for AI engines. Prevents the entity being seen as two distinct strings ("company-as-a-service" vs "Company-as-a-Service"). | 30 min, single pass. | "Company-as-a-Service" (owned category) |
| **P1-3** | **C-5: Replace `/about/` H1 from "About" to "About Jean Deruelle"** with subheadline "Founder of Soleur. Building the Company-as-a-Service platform for solo founders." Per brand guide §Website hero pattern. | Captures the navigational keyword in H1. Reclaims the highest-impact element on the page. Adds "solo founders" head term to a page that currently has it only in meta. | 5 min, one-line change. | "Jean Deruelle", "Soleur founder", "who founded Soleur" |
| **P1-4** | **C-4: Define "concurrent conversations" inline on the Solo plan card** with the one-line example from the FAQ ("two chats running work in parallel — your CTO reviews code while your CMO drafts copy"). Per brand guide §General register inline definition. | Removes a pre-purchase friction point. Visitor no longer has to scroll past the plan grid to understand what they're paying for. | 10 min. | "Soleur pricing", "AI agents pricing" |
| **P1-5** | **C-6: Replace the "vessel" sentence on `/vision/`** with the three-sentence rewrite from the content audit ("Soleur turns judgment and taste into leverage. When code and AI replicate labor at near-zero marginal cost, the founder's unique insight becomes the entire moat. Soleur is the platform that makes one founder's insight scale like a hundred-person team."). Per brand guide §Don't startup jargon. | Removes the worst voice violation on the site. Replaces metaphor-as-jargon with a quotable claim that AI engines can extract. | 10 min. | "AI organization platform", "solo founder leverage" |
| **P1-6** | **C-7: Demote internal codenames on `/vision/`** — strip "Global Brain", "Decision Ledger", "Coordination Engine", "Master Plan" proper-noun framing. Replace each `Internally called "X"` paraphrase with a single quotable definition (per AEO audit finding #5). | Highest-leverage Structure fix on Vision. Coined terms aren't citation-eligible; quotable single-sentence definitions are. | 30 min. | "AI agent orchestration", "multi-model AI" |
| **P1-7** | **AEO #3: Add `last_updated` frontmatter** to every evergreen `.njk` page (`index`, `about`, `vision`, `pricing`, `agents`, `company-as-a-service`, `skills`, `getting-started`, `community`, `changelog`). Render it in the page header next to the H1 as "Last updated: YYYY-MM-DD · Author: Jean Deruelle". Use the existing `site.statsLastVerified` pattern as precedent. | Closes the freshness signal gap. Perplexity in particular penalizes undated evergreen pages. | 1 hour across 10 files. | All evergreen-page keywords |
| **P1-8** | **AEO #4: Add a stat-led summary paragraph directly under the H1** on `/`, `/about/`, `/pricing/`, `/vision/`, `/agents/`, `/company-as-a-service/`. Format: 2-3 sentence factual paragraph stating "Soleur is a Company-as-a-Service platform: 60+ agents across 8 departments, 60+ skills, Apache-2.0 open-source, built on Claude Code and MCP. Founded 2026 by Jean Deruelle." Per AEO finding #4. Use General register on homepage/About/Pricing; Technical register on Vision/Agents. | Single highest-leverage AEO win. Hero slogans are skipped by extraction; a stat-led paragraph gives a clean quote target without diluting the brand hero. Lifts Structure score ~3-4 points. | 1 hour. | "What is Soleur", "Company-as-a-Service definition" |
| **P1-9** | **JSON-LD regeneration after rewrites.** All FAQPage JSON-LD blocks on `/`, `/pricing/`, `/about/`, `/vision/`, `/agents/`, `/company-as-a-service/` need re-rendering after P1-1 and P1-6 land (the JSON-LD strings hard-code the same prose). Verify `jsonLdSafe` filter still produces valid JSON; verify visible `<details>` text matches `mainEntity[].acceptedAnswer.text` byte-for-byte (Google demerits "answer not visible on page"). | Prevents stale JSON-LD shipping with new prose. Maintains FAQPage extraction validity. | 30 min review pass once P1-1/P1-6 land. | — |
| **P1-10** | **Re-run all three audits** (content, AEO, SEO) against the live site once P0-1 lands and P1-1 through P1-9 ship. Target: SEO back to 90+/A; AEO **Presence >= 55/D** (clears #2615 exit criterion); SAP total >= 75 (B+). | Verification gate. Without this, we cannot close #2615 and cannot confirm the regressions are repaired. | 1 hour of audit time. | — |

---

## P2 — Next sprint (Presence-class fixes + commercial-investigation capture)

Closes the Presence gap that's failing #2615 and surfaces the commercial-investigation content already on-site but buried. Estimated effort: **1-2 weeks part-time**.

| Ref | Action | Expected impact | Effort | Target keywords |
|-----|--------|-----------------|--------|-----------------|
| **P2-1** | **I-1: Promote the Cursor/Copilot comparison FAQ out of `<details>`** on the homepage. Add a standalone `<h3>Soleur vs. Cursor and GitHub Copilot</h3>` with the first sentence ("Cursor and Copilot help you write code. Soleur helps you run a company.") rendered as a non-collapsed lead paragraph. Keep the deep answer collapsed below. | Captures commercial-investigation traffic for "soleur vs cursor", "github copilot alternatives", "cursor alternatives 2026". The keyword research below confirms this is high-volume traffic Soleur isn't currently capturing. | 30 min. | "soleur vs cursor", "cursor alternatives", "github copilot alternatives" |
| **P2-2** | **AEO #6: Start citation monitoring.** Create `knowledge-base/marketing/audits/soleur-ai/citation-monitoring.md`. Test 8 queries weekly in ChatGPT, Perplexity, Claude.ai, Gemini: "AI agents for solo founders", "Company-as-a-Service", "Soleur vs Cursor", "best Claude Code plugins 2026", "agentic engineering platform", "AI for solo founders", "one person company AI", "Claude Code plugin marketplace". Log brand mentions, ranking position, source URLs cited. | Without this we can't measure whether Presence gains are real. Required to demonstrate exit-criteria compliance on #2615 going forward. | 1 hour to scaffold + 30 min/week ongoing. | All target keywords |
| **P2-3** | **AEO #6: Diversify press strip beyond Inc.com.** Ship the planned Product Hunt launch (logo + link in press strip). Seed dev.to and HN Show. Submit to ComposioHQ/awesome-claude-plugins (already in keyword-research SERP for "best claude code plugins"). Target one industry analyst-firm coverage (a16z portfolio post, Latent Space mention, ThePrimeagen/Karpathy quote-tweet). | Direct lift to Presence score. The single-outlet press strip is the loudest "thin authority" signal on the site. Adds external-corpus presence that AI engines weight when answering brand queries. | 4-8 hours seed work + outreach. | "Soleur", "Soleur review", "Soleur Product Hunt" |
| **P2-4** | **I-7, I-8: Reorder `/about/` bio to thesis-first** and remove "open-source Claude Code plugin" framing (replace with "open-source Company-as-a-Service platform that runs on Claude Code today; the hosted platform is in development"). | Lead with leverage claim, not credentials, per brand guide §Voice. Removes a §Don't violation ("plugin" in public-facing content). | 30 min. | "Jean Deruelle thesis", "Company-as-a-Service founder" |
| **P2-5** | **I-9: Add `<h2>What is Company-as-a-Service?</h2>` anchor on `/vision/`** with the homepage FAQ definition rendered as a quotable single paragraph. Currently the vision page assumes the reader is already bought in; this captures the entry-level informational query. | Captures "what is company-as-a-service" head-term traffic. AEO-friendly definition extractability. | 15 min. | "what is company-as-a-service", "Company-as-a-Service definition" |
| **P2-6** | **I-4: Replace pricing "Coming Soon" badges** on all paid tiers with either a concrete date band ("Q3 2026") or a link to the founding-cohort intro at `/getting-started/`. Per brand guide §Don't hedge. | Removes the soft-hedge signal across the pricing page. Improves trust scaffolding for transactional-intent visitors. | 20 min. | "Soleur pricing", "Soleur launch date" |
| **P2-7** | **AEO #7: Source-link the authority names on `/agents/`.** Eric Evans → DDD book canonical URL; Michael Feathers → Working Effectively With Legacy Code; Dave Farley → Continuous Delivery; Martin Fowler → martinfowler.com; DHH → dhh.dk or Rails canonical. One link each converts name-drops to citation-eligible claims. | Direct lift to Authority score. AI engines weight cited authorities higher than name-dropped ones. | 30 min. | Agent-specific keywords |
| **P2-8** | **AEO #2: Blog citation pass on top 3 evergreen posts.** Identify the three highest-leverage posts (e.g., `best-claude-code-plugins-2026`, `one-person-billion-dollar-company`, `soleur-vs-cursor`). Add minimum 3 inline citations each: Anthropic primary sources, MCP spec, industry research (a16z, Gartner, HBR, McKinsey), primary-source competitor blog posts. | Largest single Authority-class gap. Blog is 27 posts averaging 0-1 external links per post; the largest content surface on the site is a citation desert. | 2-3 hours across 3 posts. | Post-specific long-tail keywords |
| **P2-9** | **I-3: Expand homepage press strip** with the second outlet (Product Hunt logo + link, or Latent Space mention). Until then, rename "As seen in" to "In the conversation" so a single anchor proof reads intentional. | Removes the "thin press" visual signal that currently undermines E-E-A-T. | 15 min. | — |

---

## P3 — Next cycle (cluster content + shareable content + consistency sweep)

New content tied to the keyword research below, organized as a pillar/cluster model with `/company-as-a-service/` as the existing pillar. Each cluster page links back to the pillar and at least one sibling cluster. Plus the lower-priority consistency-sweep items from the content audit. Estimated effort: **2-4 weeks part-time** (content writing dominates).

| Ref | Action | Expected impact | Effort | Target keywords | Type |
|-----|--------|-----------------|--------|-----------------|------|
| **P3-1** | **Cluster post: "Best Claude Code Plugins for Solo Founders (2026)"** — review of the top 5-7 plugins from the Composio/Firecrawl/Bito SERP, positioning Soleur as the only one that goes beyond code-assistance into full-company automation. 1,500-2,000 words. Links to pillar `/company-as-a-service/`. Targets the SERP currently owned by Composio, Firecrawl, Bito, Redwerk. | Captures a Tier-1 long-tail informational keyword with established SERP demand. Inserts Soleur into the comparison set for the most popular Claude Code plugin search. | 4-6 hours writing. | "best Claude Code plugins 2026", "Claude Code plugins for developers", "Claude Code plugin marketplace" | Searchable |
| **P3-2** | **Cluster post: "What is Agentic Engineering? (And Why It's the Operating System for Solo Founders)"** — define agentic engineering using the LangChain/IBM/Simon Willison framings, then position Company-as-a-Service as the application of agentic engineering principles beyond software. 1,500-2,000 words. Cite Anthropic 2026 Agentic Coding Trends Report, Karpathy primary sources. Links to pillar `/company-as-a-service/` and sibling P3-1. | Captures a rising informational head term with established 2026 SERP. Strong narrative leverage point (agentic engineering → CaaS is the natural extension). | 4-6 hours writing. | "agentic engineering", "agentic engineering definition", "agentic engineering 2026" | Searchable |
| **P3-3** | **Cluster post: "AI Tools for Solo Founders: The Company-as-a-Service Stack (2026)"** — head-to-head comparison vs. the conventional solopreneur stack (Jasper, Taskade, ChatGPT, Make/Zapier). Use the Medvi case study ($401M revenue, one founder) as the lead. 1,500-2,000 words. Links to pillar, P3-1, P3-2. | High-volume commercial-investigation traffic. Per keyword research, "AI tools for solo founders 2026" is a heavily-contested SERP with clear search intent. | 4-6 hours writing. | "AI tools for solo founders", "solo founder tech stack 2026", "one person company AI tools" | Searchable |
| **P3-4** | **Cluster post: "AI Company Automation: How to Run All 8 Departments With AI Agents"** — operational how-to format. Targets commercial-investigation visitors evaluating departmental AI automation. Cite BLS, the 2026 Solopreneur Tech Stack data ($3K-$12K/year stack, 95-98% cost reduction). Links to pillar, P3-3. | Captures the operational-automation SERP that today routes to generic "12 AI tools" listicles. Soleur is uniquely positioned because the platform is the answer, not a tool to evaluate. | 6-8 hours writing. | "AI company automation", "AI for business operations", "automate business with AI agents" | Searchable |
| **P3-5** | **Founder-voice essay: "We Built 60+ Agents and Killed Our Own Codenames"** — shareable post-mortem narrative on the P1-6 vision rewrite. Explain why "Global Brain" sounded smart internally and read as jargon externally. Honest, voice-on, no marketing varnish. Target: HN front page, X founder-circle reshare. | First explicitly **shareable** piece (vs P3-1 through P3-4 which are searchable). Content plan was 100% search-optimized before this; brand needs novelty/opinion content too. | 3-4 hours writing. | — (distribution, not search) | Shareable |
| **P3-6** | **Shareable: "Building Soleur in Public — Audit Cadence as Marketing"** — meta-narrative on how Soleur runs 3 audits every two weeks and publishes the trend lines (the audit trend table in the AEO doc is itself shareable). Position the audit-as-process as a differentiator. | Second shareable piece. Founders share other founders' transparent build-in-public content; this is exactly that format. | 3-4 hours writing. | — (distribution, not search) | Shareable |
| **P3-7** | **I-5: Surface pricing methodology footnote** as an `<h3>Methodology: How We Sourced $95K/mo</h3>` section. Currently the Robert Half / Payscale / Levels.fyi citations are buried in small-text footnote. Promote to citation-friendly heading. | Lifts E-E-A-T citation visibility. The methodology block is already the strongest evidence block on the site; surfacing it makes it AI-extractable. | 30 min. | "AI agents vs hiring cost", "AI agents ROI" | — |
| **P3-8** | **I-13: Unify workflow-step naming.** Pick one labeling system (Think/Plan/Build/Review/Ship/Compound from homepage) and apply to `/getting-started/`. Currently the two pages name the same six steps differently (brainstorm/plan/work/review/compound/ship). | Cross-page consistency. Prevents entity confusion for AI engines summarizing the Soleur workflow. | 20 min. | — | — |
| **P3-9** | **I-12: Rotate founding-cohort scarcity claim weekly** ("limited to 10" → date-stamped "X slots remaining as of YYYY-MM-DD") or replace with static "Email ops@jikigai.com to discuss founding-cohort access". | Removes the evergreen-marketing-copy smell. Trust scaffolding. | 30 min to set up; ~5 min/week ongoing. | — | — |
| **P3-10** | **I-14: De-hedge "Prefer to run it yourself?"** on `/getting-started/`. Per brand guide §Don't hedge. | Small voice fix. Removes the softener. | 5 min. | — | — |
| **P3-11** | **Cross-page consistency sweep:** "single founder" → "one founder" everywhere in marketing prose (matches §Example Phrases "One founder. Full-stack AI. No compromises."). Drop "curator" framing except as a single aside on `/vision/`. Normalize `--` → `—` in pricing meta description. | Voice and surface polish. | 1 hour. | — | — |

---

## Keyword Research Findings

Four target terms researched on 2026-05-18. Each is classified by search intent (informational, navigational, commercial-investigation, transactional), volume estimate, relevance to Soleur (high/medium/low), and competitive landscape.

### 1. "Claude code plugin"

| Attribute | Finding |
|-----------|---------|
| Search intent | **Informational + commercial-investigation.** SERP today is dominated by listicles ("Top 10", "Best 7", "10 you actually need") aimed at developers evaluating which plugins to install. |
| Volume estimate | **High and rising.** 10+ Tier-1 results published in April-May 2026 confirms active monthly search demand. The Composio/Firecrawl/Bito/Redwerk cluster suggests this is an established SERP. |
| Relevance to Soleur | **High** — Soleur is one of the most ambitious Claude Code plugins by scope (60+ agents, 60+ skills, 8 departments) but does not appear in the consensus top-10 lists. |
| Related queries | "best Claude Code plugins 2026", "Claude Code plugin marketplace", "awesome Claude Code plugins", "Claude Code plugins for developers", "Claude Code subagents and skills" |
| Search-intent classification per related query | informational (definition), commercial-investigation (which to pick), navigational (the marketplace) |
| Gap action | **P3-1** cluster post. |

### 2. "Agentic engineering"

| Attribute | Finding |
|-----------|---------|
| Search intent | **Informational.** Top results are definitional ("What is agentic engineering?" — IBM, LangChain, Simon Willison, Glide, MindStudio, NxCode). |
| Volume estimate | **High and rising.** This is the post-vibe-coding successor term and the term is consolidating fast — IBM and LangChain both shipped pillar pages in 2026; ICSE has an "AGENT 2026" workshop; Anthropic published the 2026 Agentic Coding Trends Report. |
| Relevance to Soleur | **High** — Soleur is a direct application of agentic engineering principles (multi-agent coordination, shared memory, observability layer). Soleur does not currently own this term in its corpus. |
| Related queries | "agentic engineering vs vibe coding", "agentic coding 2026", "multi-agent software development", "AI agents in software engineering", "agentic AI workflows" |
| Search-intent classification per related query | informational (definition, vs vibe coding), commercial-investigation (workflows, tooling) |
| Gap action | **P3-2** cluster post. |

### 3. "AI company automation"

| Attribute | Finding |
|-----------|---------|
| Search intent | **Commercial-investigation + transactional.** SERP today is dominated by listicles ("10 best AI automation tools for solopreneurs", "12 AI tools to scale solo business") and category-overview pieces (Taskade, PrometAI, Solo Business Hub). |
| Volume estimate | **High.** 2026 solopreneur statistic ($1.3T US economic contribution, 41.8M solo operators) is the volume driver; the SERP shows established commercial demand. |
| Relevance to Soleur | **High** — Soleur is literally an AI company automation platform. Existing SERP routes to generic tool-listicles; Soleur is structurally differentiated (platform, not single tool). |
| Related queries | "automate business with AI agents", "AI for business operations", "AI for back office", "AI agents for company operations", "AI to replace hiring" |
| Search-intent classification per related query | commercial-investigation (which platform), transactional (replace hiring is a buying signal) |
| Gap action | **P3-4** cluster post. |

### 4. "Solo founder AI tools"

| Attribute | Finding |
|-----------|---------|
| Search intent | **Commercial-investigation.** Heavy SERP demand; Entrepreneurloop, Rocket, GreyJournal, NxCode, PYMNTS all run 2026-dated pillar pages. |
| Volume estimate | **Very high.** PYMNTS coverage of the "one-person billion-dollar company" (Medvi $401M → $1.8B trajectory) is mainstreaming the category. |
| Relevance to Soleur | **Very high.** This is Soleur's primary ICP head term. Soleur's homepage SEO title already targets it ("AI Agents for Solo Founders"). |
| Related queries | "AI tools for solopreneurs", "one person company AI", "solopreneur tech stack 2026", "build a startup solo with AI", "delegate to AI agents" |
| Search-intent classification per related query | commercial-investigation, informational (definition of one-person company) |
| Gap action | **P3-3** cluster post; reinforced by P1-3 (about/H1) and P1-8 (stat-led summary paragraphs). |

### Search-intent coverage matrix (post-plan)

| Intent | Pages currently covering it | Pages added/strengthened by this plan |
|--------|-----------------------------|----------------------------------------|
| Informational ("what is X") | `/company-as-a-service/`, `/vision/` (partial) | P1-8 stat-led paragraphs on all evergreen pages; P2-5 Vision H2; P3-2 agentic engineering cluster |
| Commercial-investigation ("X vs Y", "best X") | Homepage FAQ (Cursor/Copilot answer, but buried) | P2-1 surfaces vs-Cursor H3; P3-1 best-Claude-Code-plugins cluster; P3-3 AI-tools-for-solo-founders cluster |
| Transactional ("Soleur pricing", "install Soleur") | `/pricing/`, `/getting-started/` | P2-6 replaces "Coming Soon" hedge with concrete framing |
| Navigational ("Jean Deruelle", "Soleur founder") | `/about/` (but H1 wastes the keyword) | P1-3 fixes about H1 |

---

## Competitor Gap Analysis

Competitors are drawn from the keyword-research SERPs above and from the content audit's existing comparison set. The 2026-05-04 Soleur audit also flagged Cursor, Devin, Notion, CrewAI, Tanka, Polsia, Paperclip, and Anthropic Cowork as named comparison surfaces (9 comparison blog posts already exist). This gap analysis covers the **content surface** (what topics each competitor owns) rather than feature parity (which is a separate product analysis).

| Competitor | Owns SERP for | Soleur gap | Plan ref |
|------------|---------------|------------|----------|
| **Cursor** | "AI code editor", "Cursor pricing", "Cursor vs Copilot", "Cursor alternatives" | Soleur's "vs Cursor" answer is the strongest comparison content on the homepage but is gated behind `<details>` and not crawlable as an H2/H3 anchor. | P2-1 |
| **GitHub Copilot** | "AI pair programmer", "Copilot pricing", "GitHub Copilot alternatives" | Same as Cursor — comparison content exists but is buried. | P2-1 |
| **Devin (Cognition)** | "AI software engineer", "Devin pricing" | Soleur already has a vs-Devin blog post. Citation density on that post is low (per AEO finding #2). | P2-8 |
| **CrewAI** | "multi-agent framework", "agent orchestration framework" | Soleur is platform; CrewAI is framework. The CaaS pillar makes this distinction but it's not in the agentic-engineering cluster yet. | P3-2 |
| **Composio (`awesome-claude-plugins`)** | "best Claude Code plugins", "Claude Code plugin directory" | Soleur is not currently in the consensus top-10 lists; Composio runs the canonical awesome-list AND the Tier-1 listicle. Submitting Soleur to the awesome-list is in P2-3. | P2-3, P3-1 |
| **Jasper / Taskade / Make** | "AI tools for solopreneurs" (operational tools tier) | These are single-purpose tools; Soleur is a platform. The "AI Tools for Solo Founders" cluster (P3-3) is the head-to-head. | P3-3 |
| **Medvi (case study, not product)** | "one-person billion-dollar company" narrative | Medvi is the narrative anchor for the entire 2026 solopreneur SERP; Soleur should cite it as a proof point in P3-3 and P3-4 (the founder used multiple AI tools — Soleur replaces the orchestration layer they built bespoke). | P3-3, P3-4 |
| **IBM, LangChain, Simon Willison, NxCode** | "agentic engineering" definitional SERP | Soleur is absent from the agentic-engineering definitional surface. P3-2 puts Soleur on the map. | P3-2 |
| **Anthropic** | "Claude Code", "agentic coding trends" | Soleur cites Anthropic correctly today (Claude Code docs, MCP spec). Anthropic is more a substrate than a competitor; surface their 2026 Agentic Coding Trends Report in P3-2. | P3-2 |

**Competitive content surfaces Soleur uniquely owns** (defensible moats):
- `/pricing/` hiring-comparison table with Robert Half / Payscale / Levels.fyi methodology footnote — strongest E-E-A-T block on the site.
- `/company-as-a-service/` pillar with BLS-anchored category definition — owns "Company-as-a-Service" as a coined category.
- Open-source posture (Apache-2.0, public GitHub `jikig-ai/soleur`) — none of Cursor, Devin, or Jasper compete on this dimension.

**Skipped competitors** (unreachable or out of scope this cycle):
- None unreachable in this analysis pass; all competitors above are public companies with public marketing surfaces.

---

## Scoring Matrix — Top 8 P3 Content Pieces (1-5 each, ranked by total)

| Piece | Customer impact (ICP fit) | Content-market fit (can we write credibly?) | Search potential (volume + difficulty) | Resource cost (inverse — lower cost = higher score) | Total | Rank |
|-------|--------------------------:|--------------------------------------------:|---------------------------------------:|---------------------------------------------------:|------:|-----:|
| P3-1 Best Claude Code Plugins for Solo Founders | 5 | 5 | 5 | 4 | **19** | 1 |
| P3-3 AI Tools for Solo Founders | 5 | 5 | 5 | 3 | **18** | 2 |
| P3-2 What is Agentic Engineering | 4 | 5 | 5 | 4 | **18** | 2 |
| P3-4 AI Company Automation Operational Guide | 5 | 4 | 4 | 3 | **16** | 4 |
| P3-7 Pricing Methodology Surfaced as H3 | 4 | 5 | 3 | 5 | **17** | 5 (low-effort win) |
| P3-5 Killed Our Codenames (shareable) | 3 | 5 | 2 | 4 | **14** | 6 |
| P3-6 Audit Cadence as Marketing (shareable) | 3 | 5 | 2 | 4 | **14** | 6 |
| P3-9 Founding-cohort freshness rotation | 4 | 5 | 1 | 5 | **15** | 8 |

P3-1, P3-2, P3-3 are the strongest investments. Ship in that order.

---

## Exit Criteria & Verification

This plan is complete when:

1. **P0:** soleur.ai returns HTTP 200 on every URL in the sitemap. Verified by re-running the SEO audit.
2. **P1:** SAP total >= 75 (B+); Presence >= 14/25 (clears #2615 `>= 55/D` bar with margin); zero critical issues in the next content audit.
3. **P2:** Two new outlets in the homepage press strip; `citation-monitoring.md` has 4 weekly entries logged; vs-Cursor H3 surfaced; blog top-3 posts each carry >= 3 inline citations.
4. **P3:** Three cluster posts (P3-1, P3-2, P3-3) shipped, each linking to the CaaS pillar and one sibling; two shareable pieces shipped; consistency sweep applied.

Next audit cycle: **2026-06-01**. Target SAP score: **>= 80 (B)**.
