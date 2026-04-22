---
title: "Soleur.ai Prioritized Content Plan"
date: 2026-04-21
type: content-plan
owner: CMO / growth
inputs:
  - 2026-04-21-content-audit.md
  - 2026-04-21-aeo-audit.md (78/B+)
  - 2026-04-21-seo-audit.md (94/A)
brand_guide: knowledge-base/marketing/brand-guide.md
previous_plan: knowledge-base/marketing/audits/soleur-ai/2026-04-18-content-plan.md
---

# Soleur.ai Prioritized Content Plan — 2026-04-21

## Executive Summary

The three 2026-04-21 audits converge on one conclusion: **the structural floor is finished, the content ceiling is the work**. SEO scores 94/A (the remaining items are template polish — CSS preload, canonical host alignment, per-post hero images). AEO scores 78/B+ (up from 72 on 2026-04-18) — the only remaining lift is source citations on core pages and third-party presence. The content audit is unambiguous about the two page-level bugs blocking commercial-intent capture: `/getting-started/` reuses homepage hero copy instead of transactional-intent copy, and `/pricing/` has no FAQ.

Three priorities dominate the next two weeks:

1. **Fix `/getting-started/` and `/pricing/` as transactional-intent surfaces.** These are the two pages closest to a conversion event and both fail the content audit's search-intent test. `/getting-started/` duplicates the homepage H1, and `/pricing/` has a bare `<title>` "Pricing", no FAQ, and no in-prose aggregate cost claim. Combined effort: ~3 hours. Expected lift: commercial-intent traffic capture + AEO citation rate on the pricing query cluster.
2. **Ship the "Claude Code plugin" pillar.** Same finding as the 2026-04-18 plan. Still unshipped. Soleur IS the reference Claude Code plugin (60+ agents, 66 skills, public repo) but ranks for none of the head terms — Anthropic's official marketplace now hosts 100+ plugins and community directories (claudemarketplaces.com, buildwithclaude.com, aitmpl.com) own the SERP. This is the highest-volume, highest-intent acquisition channel that exactly matches the product's install path.
3. **Ship the "billion-dollar solo founder" pillar.** The "one-person billion-dollar company" narrative has gone from thesis to evidence in 2026: Medvi ($1.8B projected sales, one founder, Sept 2024 start — Inc.com / Wealthy Tent / PYMNTS); Amodei's 70-80% "first billion-dollar one-person company by 2026" prediction has been quoted in 15+ tier-1 outlets. Soleur's positioning is exactly this thesis. Owning the SERP for "billion-dollar solo founder", "one-person unicorn", and "AI company automation" is a once-in-a-category window that competitors (Cofounder.co, n8n, MindStudio) are actively not filling.

---

## Keyword Research

Every keyword classified by search intent (informational / navigational / commercial / transactional) and tagged with ICP relevance (High / Medium / Low) per brand guide Identity section (solo founders thinking in billions, technical builders, non-technical founders).

### Cluster 1 — "Claude Code plugin"

The Claude Code plugin ecosystem has consolidated around five surfaces in the last 60 days: Anthropic's official marketplace (claude-plugins-official), `claudemarketplaces.com`, `buildwithclaude.com`, `aitmpl.com`, and the IDE integrations (JetBrains, VS). 105,000+ developers visit Claude Code plugin marketplaces monthly.

| Keyword | Intent | Relevance | Notes |
|---|---|:---:|---|
| claude code plugin | Informational + Commercial | High | Head term. Anthropic docs + aggregators dominate. Soleur absent from SERP. |
| claude code plugins | Informational + Commercial | High | Plural; listicle-intent. |
| best claude code plugins 2026 | Commercial | High | Review intent. Aitmpl, claudemarketplaces, buildwithclaude all rank. |
| claude code plugin marketplace | Navigational | High | Direct-to-product search. Opportunity: "alternatives to the marketplace" framing. |
| claude code plugin marketplace guide 2026 | Informational | High | `agensi.io/learn/claude-code-plugin-marketplace-guide` is the top-ranking primer. Soleur can write the definitive one. |
| how to build a claude code plugin | Informational | Medium | Developer intent; Soleur is a reference implementation. |
| claude code plugin tutorial | Informational | Medium | DataCamp, alexop.dev rank. |
| install claude code plugin | Transactional | High | Matches `/getting-started/` install path. |
| claude code plugin examples | Informational | Medium | Soleur's 60+ agents are the largest public example. |
| claude code vs cursor | Commercial | High | Soleur has a post; add a cross-link from the pillar. |
| claude code mcp vs plugin | Informational | High | Disambiguation query growing fast. Strong P2 cluster candidate. |
| claude plugin marketplace add | Transactional | Medium | Exact install verb. |
| anthropic plugins official | Navigational | Medium | Brand query for Anthropic's directory. |

Related queries (SERP PAA): "do claude code plugins cost money", "can I publish my own claude code plugin", "claude code hooks vs plugins", "claude code extension vs plugin".

### Cluster 2 — "Agentic engineering"

Growing category. In 2026 SERP the term has split into four adjacent queries: "agentic engineering" (definition), "agentic AI" (enterprise), "agentic coding" (developer tooling), and "agentic workflow" (process). Anthropic published a "2026 Agentic Coding Trends Report" (PDF) — a citation-worthy primary source Soleur can quote.

| Keyword | Intent | Relevance | Notes |
|---|---|:---:|---|
| agentic engineering | Informational | High | SERP owned by Voitanos, AddyOsmani, GitLab, TuringCollege. Soleur's existing post ranks for the comparison only. |
| what is agentic engineering | Informational | High | `/skills/` H1 uses the term but never defines it (AEO finding). |
| agentic engineering workflow | Informational | Medium | Matches Soleur's brainstorm → plan → work → review → compound chain. |
| agentic engineering tools | Commercial | High | Comparison intent; `/skills/` is the natural landing page. |
| agentic AI workflow 2026 | Informational + Commercial | High | CIO, Deloitte, Vellum, StackAI, Maven all ranking — large top-of-funnel surface. |
| agentic coding trends 2026 | Informational | High | Anthropic PDF is the primary source; cite and extend. |
| agentic workflow architectures | Informational | Medium | Vellum and StackAI own the query. Reference, don't compete. |
| vibe coding vs agentic engineering | Informational | High | Soleur has this post; refresh with 2026-04 data. |
| compound engineering | Informational | Medium | Every.to owns the term; Soleur can own the "compound engineering in practice" angle. |
| context engineering | Informational | Medium | NxCode, Karpathy. Adjacent anchor for the pillar. |
| agentic AI vs SaaS | Informational | High | Crosses Cluster 3. Bain, Deloitte, YC publishing. |
| delegate review own operating model | Informational | Low | CIO article coined framing. Quote, don't target. |

Related queries: "what is an AI agent", "AI orchestration platform", "MCP Model Context Protocol", "Karpathy agentic engineering".

### Cluster 3 — "AI company automation"

Head-term cluster for the CaaS thesis. 2026 has produced concrete evidence (Medvi $1.8B, Levels $3M/yr) and named predictions (Amodei's 70-80% / 2026 — now cited in Inc.com, PYMNTS, LinkedIn, Entrepreneur, Rocket). The narrative is live; the category owner has not been chosen.

| Keyword | Intent | Relevance | Notes |
|---|---|:---:|---|
| AI company automation | Informational + Commercial | High | Broad head term; primary category anchor for CaaS. |
| automate entire business with AI | Informational + Commercial | High | Matches "Stop hiring, start delegating". |
| AI agents for business operations | Commercial | High | Matches the 8-department framing. |
| end-to-end business automation AI | Commercial | High | Lower competition, clear commercial intent. |
| AI agents vs SaaS | Informational | High | Bain, Deloitte, SuperAnnotate. Existing CaaS post can be extended. |
| vertical AI agents | Informational | Medium | YC-coined reframing. |
| one person billion dollar company | Informational | High | Amodei quote already cited on-site; owned narrative. |
| billion dollar solo founder | Informational + Navigational | High | Now an established news hook. `therundown.ai`, `thiswithkrish.com`, Inc.com ranking. |
| one person unicorn | Informational | High | NxCode ranks top; pillar candidate for Soleur. |
| AI workforce | Commercial | Medium | Salesforce Agentforce owns the term; compete on solo-founder angle. |
| company of one AI | Informational | Medium | Adjacent to solopreneur cluster. |
| Amodei billion dollar company prediction | Navigational | Medium | News/reference query — citation anchor. |

Related queries: "Medvi GLP-1 AI startup", "Matt Gallagher one person billion dollar", "agentic contracting", "outcome-based pricing AI agents".

### Cluster 4 — "Solo founder AI tools"

High-volume commercial cluster. 2026 listicle SERP is saturated (Rocket, Entrepreneur, Inc., SiliconIndia, PrometAI, NxCode, Browse.ai, OrbilonTech, AiShortcutLab). Differentiation requires operator POV — "the stack someone actually uses in production" — not another listicle.

| Keyword | Intent | Relevance | Notes |
|---|---|:---:|---|
| solo founder AI tools | Commercial | High | Head term. Saturated SERP. |
| AI tools for solopreneurs | Commercial | High | Alternate phrasing. |
| best AI tools solo founders 2026 | Commercial | High | Listicle intent. Enter as the operator-POV alternative. |
| solopreneur AI stack 2026 | Commercial | High | PrometAI ranks. Clean entry point. |
| AI tools for indie hackers | Commercial | Medium | Distribution channel (IndieHackers.com). |
| one person company AI | Informational | High | Crosses Cluster 3. |
| AI cofounder | Navigational + Commercial | Medium | Cofounder.co brand-owns; reframe to "AI team" angle. |
| AI stack for solo founders | Commercial | High | Matches "Stack" format posts. |
| how to run a company alone with AI | Informational | High | Long-tail; perfect positioning match. |
| best AI for startup founders | Commercial | High | Broad intent; competes with Cursor, ChatGPT, Zapier. |
| AI virtual assistant alternatives | Commercial | Medium | Content audit flagged as missing coverage. |
| bootstrap with AI | Informational | Medium | Indie hacker narrative. |
| can one person build a billion dollar company | Informational | High | AEO monitoring query per AEO audit §Monitoring Recommendations. |

Related queries: "Medvi one person startup", "Pieter Levels $3M solo", "Base44 $80M Wix acquisition", "Carta solopreneur report", "ChatGPT Plus Claude Pro Midjourney stack".

---

## Competitive Gap Analysis

Scope: the agentic-engineering / AI-agent-platform adjacency where Soleur's ICP is shopping. All competitors surfaced via WebSearch on 2026-04-21 plus existing Soleur vs-X posts.

| Competitor | Primary Positioning | Content Strength | Soleur Exploit |
|---|---|---|---|
| **Cursor** | AI code editor | Changelog-led; weak long-form | Owns code-editor SERP. Soleur owns "beyond code" (marketing, legal, finance). Existing `/blog/soleur-vs-cursor/` covers. |
| **Anthropic (Claude Code + official marketplace)** | Platform host | Owns docs SERP. 100+ plugins listed. | No opinionated editorial content — pure docs. Soleur can publish the "which plugins actually compound" editorial. |
| **claudemarketplaces.com** | Directory | Lists 506+ plugins, MCP servers, skills. High SERP rank on "claude code plugins". | Pure aggregator, no product. Soleur writes the definitive guide the directory links to. |
| **buildwithclaude.com, aitmpl.com, agensi.io** | Directories / listicle publishers | High SERP rank on plugin review terms. | Review-intent. Soleur's angle: the plugin that replaces an org, not a tool. |
| **Cofounder.co** | "AI cofounder" for product work | Thin content depth; strong brand | Product scope. Soleur owns "beyond product" (legal, finance, ops). Add: "Soleur vs Cofounder.co" post (gap flagged 2026-04-18, still missing). |
| **n8n (AI agents)** | Visual automation + agents | Massive template library | Tool-workflow focus; no founder-level narrative. Missing: "Soleur vs n8n agents". |
| **MindStudio** | No-code agent builder | Template library | No pre-built organization; users assemble. Soleur ships the org. |
| **Orbilon Tech, PrometAI, NxCode, therundown.ai** | One-person-unicorn narrative publishers | Strong long-form. Ranking for "billion-dollar solo founder", "one-person unicorn". | Media/content plays, not products. Soleur is the referenced product. Must be cited in this cluster, not competing. |
| **Inc.com, PYMNTS, LinkedIn (Medvi story)** | News / case study | Top SERP on Medvi, Amodei prediction | Media, not products. Soleur extends with "The Solo Founder Stack Medvi Actually Used" angle. |
| **Voitanos, AddyOsmani, TuringCollege, Vellum, StackAI, CIO, Deloitte** | Agentic engineering thought leaders | Very strong long-form, high citation density | Content plays, not products. Cite and extend, don't compete. |
| **Salesforce Agentforce** | AI workforce for enterprise | Enterprise positioning | Enterprise vs solo-founder. Soleur owns solo-founder narrative on price + velocity. |
| **Paperclip / Polsia / other plugins** | Single-purpose Claude Code plugins | Narrow scope | Already covered by existing Soleur vs-X posts. |

### Content gaps where Soleur has zero coverage (as of 2026-04-21)

| Gap | Priority | Why it matters |
|---|---|---|
| Head-term "Claude Code plugin" pillar | P1 | Soleur IS one. Does not publish claiming territory. Highest-intent acquisition channel. |
| Head-term "agentic engineering" pillar (expansion of vibe-coding post) | P1 | `/skills/` uses the term without defining it (AEO audit P1-1, content audit §7). |
| "Billion-dollar solo founder" / "one-person unicorn" pillar | P1 | Medvi + Amodei + Carta make this a moment. No competitor is filling it. |
| Role-based commercial pages (AI CTO, AI CMO, AI General Counsel, AI CFO) | P1/P2 | Pricing page has the math. No page owns the query. |
| "Soleur vs Cofounder.co" | P2 | Cofounder.co is actively competing for same ICP. Missing from vs-X set. |
| "Soleur vs n8n agents" | P2 | n8n is an ICP-adjacent shopping alternative. Missing. |
| "AI agents vs SaaS: end of seat-based software" category pillar | P1 | Bain, Deloitte, YC framing the question. Soleur has the thesis. |
| "The Solo Founder AI Stack: What Actually Runs a 2026 One-Person Company" (operator POV) | P1 | Operator-POV angle defensibly different from the listicle SERP. |
| Glossary / Key Concepts page | P2 | AEO audit: define "compounding knowledge base", "agentic engineering", "MCP", "Company-as-a-Service" consistently. |
| FAQ section on `/pricing/` | P1 | AEO audit P1: "pricing FAQ is the #1 AEO gap". Content audit §2 Critical. |
| `/getting-started/` transactional-intent rewrite | P1 | Content audit §5 Critical. H1 duplicates homepage. Mismatched intent. |
| "How I Built Soleur Using Soleur" (founder narrative) | P3 | AEO audit: first-person proof-of-thesis. Authority signal. |

---

## Content Architecture (Pillar / Cluster)

The plan organizes 14 net-new or refreshed pieces around three pillar hubs. Two of the three pillars carry over from the 2026-04-18 plan (unshipped); one (billion-dollar solo founder) replaces a weaker cluster with a sharper thesis. Every cluster page must link to its pillar and at least one sibling cluster.

### Pillar A — "Claude Code Plugins" (new, unshipped from 2026-04-18)

- **Pillar:** "The Complete Guide to Claude Code Plugins (2026)" — P1
- **Clusters:**
  - "How to Build Your First Claude Code Plugin" — P2
  - "Claude Code Plugin vs MCP Server: When to Use Which" — P2
  - "From Plugin to Company: How Soleur Extends Claude Code" — P3

### Pillar B — "Agentic Engineering" (existing post needs promotion to pillar)

- **Pillar:** "What Is Agentic Engineering? The Definitive Guide" — P1 (expand `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`)
- **Clusters:**
  - "The Agentic Engineering Workflow: Brainstorm → Plan → Implement → Review → Compound" — P2
  - "Compound Engineering: Why Agents Should Learn From Every Session" — P2
  - "Agentic Engineering Tools Compared: Cursor, Claude Code, Soleur, n8n" — P3

### Pillar C — "The Billion-Dollar Solo Founder Stack" (new; supersedes prior "AI Company / Solo Founder" pillar)

- **Pillar:** `/blog/what-is-company-as-a-service/` (existing — 80/B+ AEO score) + new companion pillar "The Billion-Dollar Solo Founder Stack (2026)" — P1
- **Clusters (role-replacement, commercial intent):**
  - "AI CTO: What an AI Engineering Leader Actually Does" — P1
  - "AI CMO: Marketing Leadership Without the $240K Salary" — P1
  - "AI General Counsel: Legal Coverage for Solo Founders" — P2
  - "AI CFO: Finance, Bookkeeping, and Reporting for One-Person Companies" — P2
- **Clusters (category):**
  - "AI Agents vs SaaS: The End of Seat-Based Software" — P1
  - "The Solo Founder AI Stack: What Actually Runs a 2026 One-Person Company" — P1 (operator-POV)
  - "Soleur vs Cofounder.co" — P2
  - "Soleur vs n8n Agents" — P2
  - "How I Built Soleur Using Soleur: A Founder's Log" — P3

### Linking rules (enforced by content-writer skill)

- Every cluster links back to its pillar in the first 200 words.
- Every cluster links to at least one sibling cluster in the body.
- Every pillar links down to every cluster in a "Related reading" section.
- All new posts link to `/pricing/` in the closing CTA.
- All new posts add `pillar:` frontmatter to render "Part of the X series" block.
- All new posts open with a definition paragraph quotable in 1-2 sentences (AEO structural requirement).
- All statistical claims carry an inline hyperlinked citation (AEO audit P1-1, P1-2).

---

## Prioritization Scoring Matrix

Each piece scored 1-5 on four dimensions (customer impact × content-market fit × search potential × inverse resource cost). Higher total = higher priority. All items above 15 go P1.

| # | Piece | Cust. impact | Content-market fit | Search potential | Resource cost (1=expensive, 5=cheap) | Total | Tier |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| X0 | **Fix `/getting-started/` transactional-intent rewrite** | 5 | 5 | 5 | 5 | **20** | P0 |
| X1 | **Fix `/pricing/` (title, H1, FAQ, prose aggregate)** | 5 | 5 | 5 | 4 | **19** | P0 |
| X2 | **Fix `/`, `/about/`, `/community/`, `/blog/` titles + H1s** | 4 | 5 | 4 | 5 | **18** | P0 |
| 1 | Claude Code Plugin pillar (P1.1) | 5 | 5 | 5 | 3 | 18 | P1 |
| 2 | Billion-Dollar Solo Founder Stack pillar (P1.7) | 5 | 5 | 5 | 3 | 18 | P1 |
| 3 | AI Agents vs SaaS pillar (P1.5) | 4 | 5 | 5 | 3 | 17 | P1 |
| 4 | Agentic Engineering pillar expansion (P1.2) | 4 | 5 | 4 | 3 | 16 | P1 |
| 5 | AI CTO role-replacement (P1.3) | 5 | 5 | 4 | 3 | 17 | P1 |
| 6 | AI CMO role-replacement (P1.4) | 5 | 5 | 4 | 3 | 17 | P1 |
| 7 | Solo Founder AI Stack operator-POV (P1.6) | 4 | 5 | 4 | 3 | 16 | P1 |
| 8 | How to Build Your First Claude Code Plugin (P2.1) | 3 | 4 | 4 | 4 | 15 | P2 |
| 9 | AI General Counsel (P2.2) | 4 | 5 | 3 | 3 | 15 | P2 |
| 10 | AI CFO (P2.3) | 4 | 5 | 3 | 3 | 15 | P2 |
| 11 | Agentic Engineering Workflow (P2.4) | 3 | 5 | 3 | 3 | 14 | P2 |
| 12 | Claude Code Plugin vs MCP Server (P2.5) | 3 | 5 | 4 | 4 | 16 | P2 |
| 13 | Soleur vs Cofounder.co (P2.6) | 4 | 5 | 3 | 4 | 16 | P2 |
| 14 | Soleur vs n8n Agents (P2.7) | 3 | 4 | 3 | 4 | 14 | P2 |
| 15 | Glossary / Key Concepts page (P2.8) | 3 | 5 | 2 | 4 | 14 | P2 |
| 16 | Agentic Engineering Tools Compared (P3.1) | 3 | 4 | 3 | 3 | 13 | P3 |
| 17 | From Plugin to Company (P3.2) | 3 | 5 | 2 | 3 | 13 | P3 |
| 18 | Compound Engineering in Practice (P3.3) | 3 | 5 | 2 | 3 | 13 | P3 |
| 19 | How I Built Soleur Using Soleur (P3.4) | 3 | 5 | 2 | 2 | 12 | P3 |

**Searchable vs Shareable balance check:** of the 19 items, 14 are primarily searchable, 3 are dual (searchable + shareable — the pillars), 2 are primarily shareable (Compound Engineering in Practice, How I Built Soleur Using Soleur). The ratio (~75% searchable, ~25% dual-or-shareable) meets the growth-skill requirement that the plan is not 100% searchable.

---

## Prioritized Content Plan

### P0 — Fix existing pages this week (inline, no net-new content)

P0 items do not create new pages — they are inline rewrites of existing pages based on the content audit's Critical findings. They ship before any P1 content because they unblock every piece that links to them.

#### P0.X0 — `/getting-started/` transactional-intent rewrite

| Field | Value |
|---|---|
| Source finding | Content audit §5 Critical (H1 duplicates homepage; meta description pricing-CTA-style; intent mismatch). |
| Target keywords | install Soleur, how to install Claude Code plugin, get started Soleur, Claude Code plugin install |
| Search intent | Transactional |
| Estimated effort | 30 min |

**Changes:**

- H1: "The AI that already knows your business." → "Get started with Soleur in two commands"
- Hero sub: "Install Soleur in Claude Code and run your first AI agent in 30 seconds. Join the managed platform waitlist or run the open-source version today."
- Meta description → "Install Soleur in two commands. Run the open-source Claude Code plugin locally, or join the waitlist for the managed platform. Get started with 60+ AI agents across 8 departments."
- Add founder attribution line per AEO audit P3-10: "Soleur is built by Jean Deruelle (Jikigai, Ltd.)."
- Link each workflow step (brainstorm, plan, work, review, compound) to its individual skill page (content audit §5 Improvement).

#### P0.X1 — `/pricing/` rewrite + FAQ section

| Field | Value |
|---|---|
| Source finding | Content audit §2 Critical (bare title, no FAQ, no prose aggregate); AEO audit Pricing §Issues (no in-line BLS/Levels.fyi citation on methodology footnote). |
| Target keywords | Soleur pricing, AI agent pricing, AI team cost, AI CTO pricing, Claude Code plugin pricing |
| Search intent | Commercial + Transactional |
| Estimated effort | 2-3 hr (includes FAQ JSON-LD + citation hyperlinks) |

**Changes:**

- Frontmatter `title`: `Pricing` → `Soleur Pricing — A Full AI Organization From $49/mo`
- H1 subhead: prepend "Soleur pricing: every department, one price."
- Add new paragraph before comparison table: "A full executive team costs about $80,000 per month. Soleur delivers the same eight functions — CTO, Marketing Director, General Counsel, CFO, Sales Director, Operations Manager, Product Lead, and Head of Support — starting at $49 per month." (AEO quotable, content audit rewrite R2-3.)
- Add inline hyperlink citations to the "Based on US market median" methodology footnote: BLS OES 15-1299 (CTO band), Levels.fyi (tech comp), Glassdoor (marketing/sales comp). AEO audit P1 item #1.
- Add FAQ section with FAQPage JSON-LD (5-7 items): "How much does Soleur cost?", "Is there a free tier?", "What is the Spark tier?", "Can I self-host Soleur for free?", "Does Soleur charge for Claude API usage?" (include typical $20-200/mo Claude cost range per AEO audit P2-7), "When is the managed platform available?", "Is pricing per user or per agent?"

#### P0.X2 — Cross-page title/H1 fixes

| Page | Change | Rationale |
|---|---|---|
| `/` | Add hero eyebrow `<p>`: "AI agents for solo founders — every department, one platform" above the H1 | Content audit §1: H1 has zero target keyword |
| `/` | Change hero subhead: "The Company-as-a-Service platform for solo founders." → "The AI agent platform for solo founders. Company-as-a-Service for the billion-dollar solo company." | Content audit §1 |
| `/about/` | H1 "About" → "About Jean Deruelle, Soleur Founder" | Content audit §3 Critical |
| `/about/` | Hero sub: "The founder behind Soleur." → "Jean Deruelle, Founder and CEO of Soleur — the AI agent platform for solo founders." | Content audit §3 |
| `/community/` | `<title>` "Community" → "Soleur Community — Discord, GitHub, and Contributors" | Content audit §8 |
| `/blog/` | `<title>` "Blog" → "Soleur Blog — Agentic Engineering and Company-as-a-Service" | Content audit §9 |
| `/vision/` | Remove "world's first model-agnostic orchestration engine" → "an open-source, model-agnostic orchestration platform" | Content audit §4 Critical; AEO audit P1 item #3 |
| `/vision/` | Label "Bring Your Own Intelligence" as Roadmap if not supported today | Content audit §4 Critical |
| `/vision/` | Add one-sentence definition of "Company-as-a-Service" as the first body sentence | Content audit §4 rewrite R1 |
| `/`, `/pricing/` | Remove "6 GitHub Stars" stat; replace with "500+ merged PRs" or waitlist count | AEO audit P2 item #5 |
| `/` (H3s) | Wrap emoji in `<span aria-hidden="true">` or drop from H3 text nodes | AEO audit P4 item #11 |
| `/agents/`, `/skills/` | Lead paragraphs with inline definitions of "agentic engineering" and "compound engineering" BEFORE the external link | Content audit §6, §7; AEO audit P3 item #9 |
| `/agents/`, `/skills/` | Add "Roster updated: 2026-04-XX" line above the listings | AEO audit P2 item #6 |
| `/blog/` | Add author byline "By Jean Deruelle" on every listing entry | AEO audit P1 item #4 |

**Total P0 effort:** 4-6 hours. Hand off to `soleur:growth` skill with the `--apply` execution mode, or to the `seo-aeo` skill for the AEO-specific fixes.

---

### P1 — Ship next 2 weeks (7 new posts)

Each P1 maps back to at least one 2026-04-21 audit finding or a documented keyword gap. Every post includes a quotable 1-2 sentence definition in the first 100 words per AEO structural requirement.

#### P1.1 — "The Complete Guide to Claude Code Plugins (2026)" (pillar)

| Field | Value |
|---|---|
| Target keywords | claude code plugin, claude code plugins, best claude code plugins 2026, claude code plugin marketplace |
| Search intent | Informational + Commercial |
| Word count | 3,500–4,500 |
| Type | Pillar |
| Searchable vs Shareable | Both (searchable primary; shareable as canonical reference) |
| Why it matters | Unshipped from 2026-04-18 plan. Soleur IS a Claude Code plugin but ranks for none of the head terms. Anthropic now has 100+ official plugins; claudemarketplaces.com / buildwithclaude.com / aitmpl.com own the SERP. Highest-intent acquisition channel. |

**Outline:**

1. Definition paragraph (quotable, 100 words max): "A Claude Code plugin is a packaged bundle of skills, agents, hooks, and MCP server configurations that extends Anthropic's Claude Code with domain-specific capabilities. Plugins are discovered through marketplaces and installed with `claude plugin marketplace add <repo>`."
2. The plugin ecosystem in April 2026 — 100+ official plugins in claude-plugins-official, 500+ listed on claudemarketplaces.com, 9,000+ third-party — cite Anthropic plugin docs (code.claude.com/docs/en/discover-plugins), claudemarketplaces.com, buildwithclaude.com, agensi.io guide.
3. Anatomy of a plugin — manifest, commands, agents, skills, hooks, MCP (cite official docs).
4. Plugin vs MCP server vs hook — the three extension surfaces, when to use which.
5. The compound case — why one comprehensive plugin beats many single-purpose plugins. Introduce Soleur as reference architecture (60+ agents, 66 skills, public repo).
6. Evaluation checklist — maintainer activity, permission scope, documented agents/skills, MCP footprint, test coverage.
7. Short-listed review — 8 plugins worth keeping, including Soleur, Context7, Chrome DevTools MCP, Ralph Loop, connect-apps, plus official Anthropic plugins. Cite Firecrawl, aitmpl review.
8. FAQ (10 Qs, FAQPage schema): definition, plugin vs MCP, are plugins free, how to install, can I publish my own, plugin vs extension, best for beginners, etc.
9. CTA: install Soleur (one-command path).

**Citations required:** Anthropic plugin docs, claude-plugins-official GitHub, claudemarketplaces.com, buildwithclaude.com, aitmpl.com, agensi.io plugin marketplace guide, Karpathy on agents.

**Internal links:** `/getting-started/`, `/agents/`, `/skills/`, `/blog/what-is-company-as-a-service/`, sibling P2.1 and P2.5.

---

#### P1.2 — "What Is Agentic Engineering? The Definitive Guide" (pillar expansion)

| Field | Value |
|---|---|
| Target keywords | agentic engineering, what is agentic engineering, agentic engineering workflow, agentic engineering tools, agentic coding trends 2026 |
| Search intent | Informational |
| Word count | 3,000–4,000 |
| Type | Pillar (expansion of `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`) |
| Searchable vs Shareable | Searchable primary, shareable-opinion secondary |
| Why it matters | `/skills/` uses "Agentic Engineering" as its H1 but never defines it (AEO audit). AddyOsmani, Voitanos, GitLab, TuringCollege, Vellum, StackAI all rank. Anthropic's 2026 Agentic Coding Trends Report is a primary source to cite and extend. |

**Outline:**

1. Definition (quotable, 1-2 sentences): "Agentic engineering is a structured methodology where AI agents execute multi-step business workflows under human oversight, compounding institutional knowledge across every session."
2. The lineage — Karpathy coined vibe coding (Feb 2025); AddyOsmani distinguished AI-assisted engineering; arxiv 2505.19443 formalized the split; Anthropic's 2026 Agentic Coding Trends Report is the current benchmark.
3. The five properties of an agent (goal-oriented, tool-using, memory-carrying, verifiable, correctable).
4. The operating model shift — "delegate, review and own" (cite CIO / Deloitte TMT 2026).
5. The workflow: brainstorm → plan → implement → review → compound.
6. Comparison table — agentic engineering vs vibe coding vs AI-assisted development.
7. Where it works (production software, recurring ops); where it breaks (weekend scripts).
8. Tooling landscape — Cursor, Claude Code, Soleur, n8n positioning.
9. FAQ (8 Qs, schema-tagged).
10. CTA: try Soleur's agents + skills.

**Citations required:** Karpathy tweet (Feb 2025); AddyOsmani; Voitanos; arxiv 2505.19443; Anthropic 2026 Agentic Coding Trends Report PDF; GitLab roadmap; CIO and Deloitte TMT 2026 agentic-AI pieces; Vellum 2026 agentic workflows guide.

**Also:** Update `/skills/` intro to include the new pillar link and a one-sentence inline definition (AEO audit P3 item #9: wrap definition in `<blockquote>` for snippet extraction).

---

#### P1.3 — "AI CTO: What an AI Engineering Leader Actually Does"

| Field | Value |
|---|---|
| Target keywords | AI CTO, AI engineering leader, AI chief technology officer, how to replace CTO with AI |
| Search intent | Commercial |
| Word count | 2,000–2,500 |
| Type | Cluster (Pillar C) |
| Searchable vs Shareable | Searchable |
| Why it matters | Pricing page lists $18K/mo CTO. No page ranks for "AI CTO". Highest commercial intent in role cluster. Carries over from 2026-04-18 plan — still unshipped. |

**Outline:** $18K/mo problem (cite BLS 15-1299 + Levels.fyi CTO band) → what a human CTO does → what Soleur's CTO-related agents do (architecture, security-sentinel, test-driven, review) with real output examples → where the human stays in the loop → cost comparison with footnote citations → FAQ (6 Qs) → pricing CTA.

**Citations required:** BLS OES 15-1299, Levels.fyi CTO, Payscale.

---

#### P1.4 — "AI CMO: Marketing Leadership Without the $240K Salary"

| Field | Value |
|---|---|
| Target keywords | AI CMO, AI marketing director, AI chief marketing officer, AI marketing agent |
| Search intent | Commercial |
| Word count | 2,000–2,500 |
| Type | Cluster (Pillar C) |
| Searchable vs Shareable | Searchable |
| Why it matters | Sister to P1.3. Marketing is Soleur's strongest domain (per brand guide: heavy marketing agent coverage). |

**Outline:** $10K/mo CMO problem → human CMO scope → Soleur's marketing org (brand-strategist, copywriter, growth, seo-aeo, campaign-calendar, social-distribute) with one output per agent → where human judgment stays (taste, positioning) → cost comparison → FAQ → pricing CTA.

**Citations required:** BLS Marketing Managers OES, HubSpot 2026 marketing-team benchmark.

---

#### P1.5 — "AI Agents vs SaaS: The End of Seat-Based Software"

| Field | Value |
|---|---|
| Target keywords | AI agents vs SaaS, agentic AI disruption SaaS, vertical AI agents, company-as-a-service |
| Search intent | Informational |
| Word count | 2,500–3,000 |
| Type | Cluster (Pillar C — category) |
| Searchable vs Shareable | Both (shareable opinion + searchable on category term) |
| Why it matters | Bain, Deloitte, SuperAnnotate, YC all publishing. Soleur has the thesis. No page targets the query. Claims the category narrative on behalf of the product. Carries over from 2026-04-18 plan. |

**Outline:** Hook — "SaaS helps you manage work; AI agents complete it." → shift in contracting (cite Mayer Brown agentic-contracting) → YC's "B2B SaaS → vertical AI agents" reframing (cite SuperAnnotate) → where the two models collide (seat-based pricing breaks when work is agent-executed) → the Company-as-a-Service synthesis → enterprise vs solo-founder dynamics (Agentforce vs Soleur) → FAQ → pillar link to `/blog/what-is-company-as-a-service/`.

**Citations required:** Bain 2026 report, Deloitte TMT 2026 agentic AI strategy, Mayer Brown agentic contracting, YC / SuperAnnotate on vertical AI agents, HN thread on martinalderson.com.

---

#### P1.6 — "The Solo Founder AI Stack: What Actually Runs a 2026 One-Person Company" (operator POV)

| Field | Value |
|---|---|
| Target keywords | solo founder AI tools, AI stack for solo founders, solopreneur AI stack 2026, AI tools for solopreneurs, best AI tools solo founders 2026 |
| Search intent | Commercial |
| Word count | 2,500–3,500 |
| Type | Cluster (Pillar C — solopreneur) |
| Searchable vs Shareable | Both |
| Why it matters | Highest-intent solopreneur query. SERP saturated with generic listicles (Rocket, Entrepreneur, Inc., SiliconIndia, PrometAI, NxCode, Browse.ai). Operator-POV angle — Jean building Soleur using Soleur — is defensibly different. Carries over from 2026-04-18. |

**Outline:** Hook — Medvi did $401M Y1 / $1.8B projected with one founder; 64% of surveyed solopreneurs say AI was load-bearing (cite Inc.com, Rocket) → the economics ($3K-$12K/yr stack vs $80K/mo executive team) → stack by department (engineering: Claude Code + Soleur; marketing: Soleur marketing; legal: Soleur legal; finance: Soleur finance; ops: Zapier/Make; design: Canva/Figma) → live case studies (Medvi $1.8B, Pieter Levels $3M, Base44 $80M Wix acquisition, HeadshotPro $300K MRR, Sarah Chen $420K ARR) → Amodei prediction context (cite Inc.com, Wealthy Tent, PYMNTS) → FAQ → pricing + CaaS pillar CTAs.

**Citations required:** Inc.com ("1-Employee Billion-Dollar Startup" + Amodei), Wealthy Tent (Medvi), PYMNTS (one-person billion-dollar company), Rocket solo-founder tools, PrometAI, NxCode one-person unicorn, Carta 2024 solopreneur report, therundown.ai.

---

#### P1.7 — "The Billion-Dollar Solo Founder Stack (2026)" (new pillar)

| Field | Value |
|---|---|
| Target keywords | billion dollar solo founder, one person billion dollar company, one person unicorn, AI company automation, how to build a billion dollar company alone |
| Search intent | Informational + Commercial |
| Word count | 3,500–4,500 |
| Type | Pillar (Pillar C — new) |
| Searchable vs Shareable | Both (shareable opinion + searchable on head term) |
| Why it matters | Medvi + Amodei + Carta make the narrative concrete in 2026. SERP leaders (therundown.ai, Inc.com, PYMNTS, NxCode, Wealthy Tent, ThisWithKrish, DEV Community) are media publishers, not products. Soleur's positioning literally is this thesis ("Build a Billion-Dollar Company. Alone." per brand guide). No product is filling the category-owner slot. Once-in-a-category window. |

**Outline:**

1. Definition (quotable, 1-2 sentences): "The billion-dollar solo founder is a single person running a company that generates over $1B in annual revenue, using AI agents to execute the work of departments that used to require headcount." Include Amodei quote with Inc.com citation.
2. The Medvi proof point — $20K starting capital, $401M Y1, $1.8B projected, Sept 2024 launch. Cite Wealthy Tent + Inc.com + LinkedIn (Nicholas Thompson post).
3. The Amodei 70-80% / 2026 prediction — cite Inc.com primary + PYMNTS + Entrepreneur secondary.
4. What makes it possible now (2026 specifically) — (a) frontier models reason over multi-step workflows, (b) MCP standardized tool connectivity, (c) Claude Code / Cursor / Soleur package the orchestration layer.
5. The stack by function — engineering (Claude Code + Soleur), marketing (Soleur marketing agents), legal (Soleur legal + licensed human for jurisdictional matters), finance (Soleur finance + human CPA for filings), ops (Zapier / Make), design (Midjourney + Figma + Canva), customer service (custom agents + ElevenLabs like Medvi).
6. What still requires the human — taste, positioning, final go/no-go decisions, regulated actions (tax filings, litigation, M&A, jurisdictional legal).
7. How Soleur fits — full Company-as-a-Service org out of the box, compounding knowledge base. Link to CaaS pillar + pricing.
8. Counterpoint — what could stop this (regulatory, model costs, attention economy collapse, vibe-coding-induced tech debt). Brand guide §Trust-scaffolding rule.
9. FAQ (10 Qs): Who has already done it? Is this ethical? Do you still hire anyone? What's the Claude API cost? Which model? Is it defensible vs. a 20-person team?
10. CTA: pricing + join waitlist.

**Citations required:** Wealthy Tent (Medvi $1.8B), Inc.com (Amodei + 1-Employee Billion-Dollar Startup), PYMNTS, LinkedIn/Nicholas Thompson, therundown.ai, thiswithkrish.com, Entrepreneur, PrometAI, NxCode, Carta 2024 solopreneur report, Anthropic 2026 Agentic Coding Trends Report, Deloitte TMT 2026, CIO agentic workflows.

**Internal links:** `/vision/`, `/pricing/`, `/blog/what-is-company-as-a-service/`, P1.5, P1.6.

---

### P2 — Ship next month (8 posts)

| # | Title | Target keywords | Intent | Word count | Type |
|---|---|---|---|:---:|---|
| P2.1 | How to Build Your First Claude Code Plugin | how to build a claude code plugin, claude code plugin tutorial, claude code plugin example | Informational | 1,800-2,400 | Cluster (Pillar A) |
| P2.2 | AI General Counsel: Legal Coverage for Solo Founders | AI general counsel, AI legal startup, AI lawyer for founders, fractional general counsel AI | Commercial | 2,000-2,500 | Cluster (Pillar C) |
| P2.3 | AI CFO: Finance, Bookkeeping, and Reporting for One-Person Companies | AI CFO, AI CFO as a service, AI finance manager, AI bookkeeping founders | Commercial | 2,000-2,500 | Cluster (Pillar C) |
| P2.4 | The Agentic Engineering Workflow: Brainstorm → Plan → Implement → Review → Compound | agentic engineering workflow, compound engineering, agentic development process | Informational | 2,500-3,000 | Cluster (Pillar B) |
| P2.5 | Claude Code Plugin vs MCP Server: When to Use Which | claude code plugin vs mcp, claude code hooks vs plugins, MCP server vs plugin | Informational | 1,800-2,400 | Cluster (Pillar A) |
| P2.6 | Soleur vs Cofounder.co | soleur vs cofounder, cofounder.co alternative, AI cofounder alternative | Commercial | 1,800-2,400 | Cluster (Pillar C) |
| P2.7 | Soleur vs n8n Agents | soleur vs n8n, n8n AI agents alternative, n8n vs claude code | Commercial | 1,800-2,400 | Cluster (Pillar C) |
| P2.8 | Glossary / Key Concepts | company-as-a-service, compounding knowledge base, agentic engineering, MCP, Claude Code plugin | Informational | 1,200-1,800 | Glossary page |

Each P2 piece follows the same structural contract as P1 (quotable definition in first 100 words, inline hyperlinked citations for every stat, sibling-cluster links, pillar link in first 200 words, `/pricing/` link in closing CTA).

**P2.2 special requirement:** legal disclaimer per brand guide trust-scaffolding rule — "Not a substitute for licensed legal counsel for jurisdictional matters."

**P2.3 special requirement:** CPA disclaimer — "Not a substitute for a licensed CPA for tax filings."

**P2.8 special requirement:** link every glossary term to its canonical page (e.g., "company-as-a-service" → `/blog/what-is-company-as-a-service/`, "agentic engineering" → P1.2, "Claude Code plugin" → P1.1). This is the AEO audit's recommended way to consolidate scattered definitions.

---

### P3 — Future / backlog (4 posts)

| # | Title | Type | Why deferred |
|---|---|---|---|
| P3.1 | Agentic Engineering Tools Compared: Cursor, Claude Code, Soleur, n8n | Cluster (Pillar B) | Downstream of P1.2 pillar + P2.6/P2.7 vs-X posts — ship after both. |
| P3.2 | From Plugin to Company: How Soleur Extends Claude Code | Cluster (Pillar A) | Founder-narrative depth. Low search volume but high shareable value. |
| P3.3 | Compound Engineering in Practice: A Worked PR Walkthrough | Cluster (Pillar B) | Requires screenshots + production PR reference. High craft cost. |
| P3.4 | How I Built Soleur Using Soleur: A Founder's Log | Cluster (Pillar C) | Best first-person proof-of-thesis per AEO audit. Low search volume — reserve for distribution push (HN + newsletter). |

---

## GEO/AEO Content-Level Recommendations (aligned with AEO audit)

Every new piece must:

1. Open with a quotable 1-2 sentence definition paragraph in the first 100 words. The definition sentence should be extractable without surrounding context.
2. Include inline hyperlinked citations for every statistical claim. "65 agents", "67 skills", "$95K/mo", "$18K/mo CTO", "70-80% probability" — all cite.
3. Use named-entity anchors (Amodei, Karpathy, Evans, DHH, Farley) where relevant — AEO audit identified these as an underrated AEO asset on `/agents/`.
4. Carry an author byline ("By Jean Deruelle" or agent + reviewer) and last-updated timestamp. Missing bylines on blog listings is AEO audit P1 item #4.
5. Wrap FAQ sections in FAQPage JSON-LD.
6. End with a CTA link to `/pricing/`, a pillar, and a sibling cluster.

## Presence / Third-Party Monitoring (from AEO audit §Monitoring Recommendations)

- Seed 2-3 additional tier-1 third-party mentions this cycle. Candidates: HN front-page comment thread on the Medvi story / Amodei thesis; TechCrunch, The Information, or Stratechery feature on Soleur; inclusion in an established AI-tools newsletter (Ben's Bites, The Neuron, The Rundown AI).
- Set up Google Alerts for "Soleur AI", "Jikigai", "Jean Deruelle".
- Schedule a monthly AI-citation probe (via `soleur:schedule`) running five canonical queries through ChatGPT, Perplexity, Claude, and Google AI Overviews: "what is company-as-a-service", "AI platform for solo founders", "Soleur vs Cursor", "AI agents for solo founders 2026", "can one person build a billion-dollar company". Log citation rate in `knowledge-base/marketing/analytics/ai-citation-log.md`.

## Delta vs 2026-04-18 Plan

| Plan Item | 2026-04-18 | 2026-04-21 |
|---|---|---|
| `/getting-started/` rewrite | P0 | P0 (still unshipped) |
| `/pricing/` FAQ + title + prose aggregate | P0 | P0 (still unshipped) |
| Claude Code Plugin pillar (P1.1) | P1 | P1 (still unshipped) |
| Agentic Engineering pillar expansion (P1.2) | P1 | P1 (still unshipped) |
| AI CTO / AI CMO (P1.3/P1.4) | P1 | P1 (still unshipped) |
| AI Agents vs SaaS (P1.5) | P1 | P1 (still unshipped) |
| Solo Founder AI Stack operator POV (P1.6) | P1 | P1 (still unshipped) |
| **Billion-Dollar Solo Founder pillar (P1.7)** | — | **NEW P1** (Medvi + Amodei evidence published since last plan) |
| Soleur vs Cofounder.co, Soleur vs n8n | P2 gap noted | P2 (explicitly added) |
| Glossary / Key Concepts | P2 | P2 (carried) |

SEO audit score: 98/A (2026-04-18) → 94/A (2026-04-21). Slight drop explained by warnings that surfaced this audit (CSS preload, canonical-vs-www mismatch, per-post hero images) that the 2026-04-18 audit did not measure. Still an A.

AEO audit score: 72/B- (2026-04-18) → 78/B+ (2026-04-21). +6 points reflects the new citations added on `/`, `/vision/`, `/agents/`, `/skills/` plus the FAQ-schema expansion. Next lift to 85/B requires executing the P0 pricing-FAQ fix + P1.7 citation density.

Content audit: no numeric score; critical-issue count steady at 6 across 2026-04-13 → 2026-04-21 (same core issues — the fixes haven't been applied).

---

## Execution Handoff

- **P0 inline fixes** — hand to `soleur:growth` with `--apply` execution mode, or split between `soleur:growth` (content rewrites) and `soleur:seo-aeo` (title tags, JSON-LD).
- **P1 posts** — hand each piece to `soleur:content-writer` with its outline, citations list, and internal-links list as the brief.
- **P2 vs-X posts** — same handoff to `soleur:content-writer`, with `soleur:competitive-analysis` as a preceding step for live competitor research.
- **P2 glossary** — hand to `soleur:content-writer` with `soleur:architecture` consulted for canonical term definitions.
- **Distribution** — every P1 post through `soleur:social-distribute` + `soleur:release-announce` + `soleur:community` for Discord + HN seeding (brand guide §Channel Notes).

## Methodology Notes

- All three 2026-04-21 audits read end-to-end.
- Brand guide §Identity + §Voice + §Audience Voice Profiles applied throughout.
- Keyword research via WebSearch (2026-04-21) across four seed terms plus SERP-adjacent discovery.
- Competitor analysis surfaced via WebSearch; no unreachable competitors.
- Scoring matrix per growth skill spec (customer impact × content-market fit × search potential × inverse resource cost). Each dimension 1-5; total out of 20.
- Searchable/shareable balance verified per growth skill spec — plan is not 100% searchable.
- Pillar/cluster architecture per growth skill spec — every cluster links to pillar + at least one sibling.
- SEO audit JSON-LD / sitemap / llms.txt findings routed to `seo-aeo-analyst` agent per growth skill scope (not included in this plan).
