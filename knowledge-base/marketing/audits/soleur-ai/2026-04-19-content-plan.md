---
title: "Soleur.ai Prioritized Content Plan"
date: 2026-04-19
type: content-plan
inputs:
  - 2026-04-19-content-audit.md
  - 2026-04-19-aeo-audit.md (81/B)
  - 2026-04-19-seo-audit.md (93/A)
brand_guide: knowledge-base/marketing/brand-guide.md
content_strategy: knowledge-base/marketing/content-strategy.md
previous_plan: knowledge-base/marketing/audits/soleur-ai/2026-04-18-content-plan.md
owner: CMO
---

# Soleur.ai Prioritized Content Plan

## Key Findings

Findings below are written one-line-per-finding with priority labels so `ship` Phase 5.5 can generate tracking issues one-per-row. Each line starts with a concise title, followed by audit origin and one-sentence rationale.

| Priority | Title | Origin | One-line rationale |
|---|---|---|---|
| P0 | Cloudflare 403 blocks AI crawlers | AEO 2026-04-19 P0-1 | `GPTBot`, `ClaudeBot`, `PerplexityBot`, and `WebFetch`-class clients receive 403 on `soleur.ai/*`; FAQPage schema is invisible to AI engines until the bot-fight rule is allowlisted. Ops / infra scope but belongs here because it blocks every content lift downstream. |
| P0 | Numeric drift across site and brand guide | Content Audit C1 | Homepage says 65 agents / 66 skills; pricing says 65 specialists; brand guide says 63 agents / 62 skills; stat blocks say 60+. E-E-A-T red flag — pick canonical numbers (or soft floors) and apply repo-wide in one commit. |
| P1 | Homepage H1/H2 missing "Company-as-a-Service" pillar keyword | Content Audit C2 / SEO Audit P1 | The category-defining term appears in title and body but not in H1/H2 anchors; homepage cannot rank for its own category. |
| P1 | Pillar page lives in `/blog/` instead of top-level `/company-as-a-service/` | Content Audit C3 | The defining category page is a blog post; promote to top-level pillar (or canonical) and back-link from every comparison post. |
| P1 | `/vision/` H2s use internal vocabulary with zero search signal | Content Audit C4 | "The Global Brain", "The Decision Ledger", "The Coordination Engine" carry no search intent; rewrite with search-extractable H2s while keeping poetic names in body prose. |
| P1 | Homepage FAQ answer to "Is Soleur free?" references undefined "Spark tier" | Content Audit C5 | Violates AEO self-containment rule; AI engines quoting this surface an ambiguous tier. Rewrite per RW-2. |
| P1 | $95K/mo replacement-cost table on `/pricing/` has no linked source | AEO P1-2 / Content Audit I10 | Add BLS OEWS + levels.fyi footnote; uncited economic claims don't get cited by AI engines. |
| P1 | No `Organization` JSON-LD on homepage | AEO P1-3 | 15-minute edit; single biggest brand knowledge-graph win. (SEO-audit boundary: JSON-LD belongs to seo-aeo agent, flagged here because it gates content authority.) |
| P1 | Own the "Claude Code plugin" query cluster before the ecosystem consolidates | Carryover from 2026-04-18 P1.1 | Anthropic's marketplace lists 101+ plugins; Soleur appears in zero "best plugins" reviews. Highest-intent acquisition channel matching the actual install path. |
| P1 | Ship the role-based commercial-intent cluster (AI CTO / AI CMO / AI CFO / AI GC) | Carryover from 2026-04-18 P1.3–P1.4 | Pricing page has the math, no page owns the individual role-replacement query. |
| P1 | Ship "What Is Agentic Engineering?" pillar | Carryover from 2026-04-18 P1.2 | `/skills/` H1 uses the term without defining it (AEO 2026-04-19 still shows extractability gap on `/skills/`). |
| P2 | `/agents/` meta description is a flat comma list, no benefit hook | Content Audit I1 | Rewrite with concrete number + outcome; improves SERP CTR. |
| P2 | Comparison cluster (`soleur-vs-*`) has no shared hub and no sibling links | Content Audit I3 / RW-10 | Cluster-pillar model requires each page link to pillar + 1 sibling; add shared back-link include. |
| P2 | `/getting-started/` splits intent between waitlist and OSS install | Content Audit I2 / RW-6 | Either split or add "Two ways to start" H2 with parallel cards. |
| P2 | `/skills/` shows "Uncategorized" H2 | Content Audit I6 / RW-9 | Reads like a staging leak — rename or fold into existing categories. |
| P2 | No FAQ on `/getting-started/` or `/vision/` | AEO P2-6 | Two highest-probability landing pages for query-style prompts with no FAQ; adds extractable Q&A. |
| P2 | `/changelog/` opens into v3.53.1 with no summary lede | Content Audit I8 / RW-11 | Add weekly "This week: N releases…" H2 so AI engines get one quotable velocity line. |
| P2 | `/community/` foregrounds small counts while claiming "active community" | Content Audit I9 / RW-8 | Reframe as "early builder community — small by design" until numbers catch up. |
| P2 | Expand third-party press mentions beyond one Inc.com citation | AEO P1-5 | Seed Product Hunt, HN, dev.to, hashnode; target 5 distinct outlets within 60 days. |
| P2 | BlogPosting JSON-LD `image` mismatches post-specific `og:image` | SEO P1 | Align `image` property with slug-based URL to unblock Google rich-result eligibility. |
| P2 | Homepage `og:title` is just "Soleur" | SEO P1 | Expand to include the value proposition for LinkedIn/Twitter preview quality. |
| P2 | Primary-source the Amodei billion-dollar quote | AEO P1-4 | Currently linked via Inc.com only across three pages; add Anthropic/YouTube primary for authority. |

---

## Carryovers from Previous Plan (2026-04-18)

Every P1/P2/P3 item in the 2026-04-18 plan remains open as of 2026-04-19. None shipped in the 24-hour window between plans. Items are carried forward below with their original scoring intact; the new 2026-04-19 findings have been added as an additional Site-Fixes track (SF-1…SF-10) that runs in parallel with the content-piece track.

Carried over, unchanged, from 2026-04-18 plan:

| Prev ID | Title | Status | Reason to keep |
|---|---|---|---|
| P1.1 | "The Complete Guide to Claude Code Plugins" (pillar) | Pending | Head-term ownership still open; SERP ownership by Firecrawl / AITmpl / BuildToLaunch unchanged. |
| P1.2 | "What Is Agentic Engineering? The Definitive Guide" (pillar) | Pending | `/skills/` still undefines the term on-page per 2026-04-19 AEO. |
| P1.3 | "AI CTO: What an AI Engineering Leader Actually Does" | Pending | Pricing table still cites $18K/mo CTO with no landing page for the query. |
| P1.4 | "AI CMO: Marketing Leadership Without the $240K Salary" | Pending | Sister cluster to P1.3. |
| P1.5 | "AI Agents vs SaaS: The End of Seat-Based Software" | Pending | Category claim; Bain/Deloitte still own SERP. |
| P1.6 | "The Solo Founder AI Stack: What Actually Runs a 2026 One-Person Company" | Pending | Highest-intent solopreneur query. |
| P2.1 | "How to Build Your First Claude Code Plugin" | Pending | Cluster under Pillar A. |
| P2.2 | "AI General Counsel: Legal Coverage for Solo Founders" | Pending | Cluster under Pillar C. |
| P2.3 | "AI CFO: Finance, Bookkeeping, and Reporting for One-Person Companies" | Pending | Cluster under Pillar C. |
| P2.4 | "The Agentic Engineering Workflow" | Pending | Cluster under Pillar B. |
| P2.5 | "Claude Code Plugin vs MCP Server" | Pending | Cluster under Pillar A. |
| P3.1 | "How I Built Soleur Using Soleur: A Founder's Log" | Pending | Authority gap (now 6/10 on E-E-A-T, up from 62/D — still open). |
| P3.2 | "Compound Engineering: Why AI Agents Should Learn From Every Session" | Pending | Claims a term with low competition. |
| P3.3 | "Soleur vs Cofounder.co vs n8n Agents" | Pending | Completes vs-series gap. |
| P3.4 | Glossary / Key Concepts page | Pending | Definitions still scattered per AEO 2026-04-19. |
| P3.5 | External-presence operational plan | Pending | AEO 2026-04-19 still shows single-source press fragility (Inc.com ×3). |

**New in 2026-04-19 (added to plan, ship next 2 weeks alongside P1 content):**

- SF-1…SF-10 site-fix items (see P1 section below) — narrow-scope on-page edits the content-audit turned up. Applicable in a single PR via `/soleur:growth fix --apply`.

---

## Keyword Research

Keyword research carried forward from 2026-04-18 plan (clusters 1-4). The four clusters ("Claude Code plugin", "Agentic engineering", "AI company automation", "Solo founder AI tools") remain valid — no new SERP movement detected at the head-term level in the 24-hour window. Refer to `2026-04-18-content-plan.md` §Keyword Research for the full tables. Key deltas since last research pass:

- **"Company-as-a-Service"** — term is still uncontested. Homepage still missing it from H1/H2; promote to a pillar URL.
- **"AI agents for solo founders"** — Soleur has a strong blog post (2,871 words) that should be promoted to `/ai-agents-for-solo-founders/` pillar URL.
- **"claude code plugin marketplace alternative"** — new long-tail emerging as Anthropic's marketplace consolidates; worth targeting in P1.1 pillar.

See 2026-04-18 plan for full keyword tables with intent classification and relevance ratings.

---

## Competitive Gap Analysis

Carried forward from 2026-04-18. No new competitor entrants detected in the 24-hour window. Summary of gaps still open:

| Gap | Status |
|---|---|
| Head-term "agentic engineering" definitional pillar | Open — P1.2 addresses |
| Head-term "Claude Code plugins" authoritative piece | Open — P1.1 addresses |
| "Solo founder AI stack" comparison / opinion piece | Open — P1.6 addresses |
| "AI agents vs SaaS" category piece | Open — P1.5 addresses |
| Role-specific replacement pages (AI CTO/CMO/CFO/GC) | Open — P1.3, P1.4, P2.2, P2.3 address |
| "How I built Soleur using Soleur" founder narrative | Open — P3.1 addresses |
| Third-party comparisons (Cofounder.co, n8n) | Open — P3.3 addresses |
| Glossary / Key Concepts page | Open — P3.4 addresses |

Competitors not re-evaluated this pass (see 2026-04-18 plan for full list): Cursor, Anthropic Claude Code, Cofounder.co, MindStudio, n8n agents, Nestr, Orbilon, Voitanos / AddyOsmani / TuringCollege, Paperclip / Polsia.

---

## Content Architecture (Pillar / Cluster)

Unchanged from 2026-04-18. The three-pillar model holds:

- **Pillar A:** `/claude-code-plugins/` (new) — cluster posts on building a plugin, plugin vs MCP, plugin alternatives.
- **Pillar B:** `/agentic-engineering/` (new) — cluster posts on workflow, compound engineering, tools comparison.
- **Pillar C:** `/company-as-a-service/` (promote from `/blog/what-is-company-as-a-service/`) — cluster posts on role replacement (CTO/CMO/CFO/GC), solopreneur stack, AI-vs-SaaS, founder log.

**New architecture requirement (from 2026-04-19 Content Audit C3):** `/blog/what-is-company-as-a-service/` must be promoted to `/company-as-a-service/` (301 redirect OR canonical-tag promotion) before any new cluster content ships under Pillar C. Coordinate with seo-aeo-analyst on the redirect strategy.

---

## Prioritized Content Plan

Two parallel tracks this cycle:

- **Content Track** — 16 content pieces carried forward from 2026-04-18 (P1.1–P3.5).
- **Site-Fixes Track** — 10 narrow-scope on-page edits newly identified by the 2026-04-19 audits (SF-1…SF-10). These are `/soleur:growth fix --apply` targets.

### P1 — Ship next 2 weeks

#### Site-Fixes Track (new — ship in single PR)

| ID | Title | Target keyword / intent | Content type | Target URL | Effort | Audit findings addressed |
|---|---|---|---|---|---|---|
| SF-1 | Add "Company-as-a-Service" to homepage H2 eyebrow | company-as-a-service / informational+commercial | Landing (edit) | `/` | 1h | Content C2, RW-1 |
| SF-2 | Rewrite homepage FAQ "Is Soleur free?" to self-contained answer | is soleur free / informational | FAQ (edit) | `/` | 30m | Content C5, RW-2 |
| SF-3 | Rewrite `/vision/` H2s for search-intent (model routing, decision memory, cross-department coordination) | AI agent orchestration / informational | Landing (edit) | `/vision/` | 2h | Content C4, RW-3, RW-4 |
| SF-4 | Rewrite `/agents/` meta description with concrete number + outcome | AI agents for every department / commercial | Landing (meta edit) | `/agents/` | 30m | Content I1, RW-5 |
| SF-5 | Split `/getting-started/` intent into "Two ways to start" pattern | install Soleur / transactional | Landing (edit) | `/getting-started/` | 2h | Content I2, I4, RW-6 |
| SF-6 | Add dated + linked source footnote to `/pricing/` $95K/mo table | AI team pricing / commercial | Landing (edit) | `/pricing/` | 1h | Content I10, RW-7, AEO P1-2 |
| SF-7 | Rename "Uncategorized" H2 on `/skills/` and add definition of "agentic engineering" inline | agentic engineering / informational | Landing (edit) | `/skills/` | 1h | Content I6, RW-9, AEO extractability |
| SF-8 | Reframe `/community/` as "early builder community — small by design" | Soleur community / navigational | Landing (edit) | `/community/` | 30m | Content I9, RW-8 |
| SF-9 | Add "This week in Soleur" weekly lede to `/changelog/` | Soleur changelog / navigational | Landing (edit) | `/changelog/` | 1h | Content I8, RW-11 |
| SF-10 | Resolve numeric drift (pick canonical agent/skill/dept counts or soft floors) repo-wide | N/A (trust signal) | Cross-cutting | `apps/web-platform/src/content/*.md` + brand-guide.md | 2h | Content C1 |

**Cross-cluster back-links (SF-11, bundled with SF-10 PR):** add shared closing include to all `/blog/soleur-vs-*/` posts linking back to the CaaS pillar + 1 sibling. Addresses Content I3 / RW-10. Effort: 1h.

#### Content Track (carried from 2026-04-18 — re-asserted P1)

| ID | Title | Target keyword | Intent | Content type | Target URL | Effort | Audit findings addressed |
|---|---|---|---|---|---|---|---|
| P1.1 | The Complete Guide to Claude Code Plugins | claude code plugin, best claude code plugins 2026 | Informational + Commercial | Pillar | `/claude-code-plugins/` | 16h | Carryover; Content C3 (pillar-architecture completeness) |
| P1.2 | What Is Agentic Engineering? The Definitive Guide | agentic engineering | Informational | Pillar (expansion) | `/agentic-engineering/` | 14h | Carryover; AEO 2.2 (definitional extractability on `/skills/`) |
| P1.3 | AI CTO: What an AI Engineering Leader Actually Does | AI CTO | Commercial | Cluster (Pillar C) | `/blog/ai-cto/` | 8h | Carryover; pricing-page $18K/mo has no landing |
| P1.4 | AI CMO: Marketing Leadership Without the $240K Salary | AI CMO | Commercial | Cluster (Pillar C) | `/blog/ai-cmo/` | 8h | Carryover; sister cluster |
| P1.5 | AI Agents vs SaaS: The End of Seat-Based Software | AI agents vs SaaS | Informational (shareable) | Cluster (Pillar C) | `/blog/ai-agents-vs-saas/` | 12h | Carryover; category claim |
| P1.6 | The Solo Founder AI Stack | solo founder AI tools, AI stack for solo founders | Commercial | Cluster (Pillar C) | `/blog/solo-founder-ai-stack/` | 12h | Carryover; highest-intent solopreneur query |

### P2 — Ship next month

| ID | Title | Target keyword | Intent | Content type | Target URL | Effort | Audit findings addressed |
|---|---|---|---|---|---|---|---|
| P2.1 | How to Build Your First Claude Code Plugin | how to build a claude code plugin | Informational | Cluster (Pillar A) | `/blog/build-claude-code-plugin/` | 8h | Carryover |
| P2.2 | AI General Counsel: Legal Coverage for Solo Founders | AI general counsel | Commercial | Cluster (Pillar C) | `/blog/ai-general-counsel/` | 8h | Carryover; $15K/mo pricing row |
| P2.3 | AI CFO: Finance, Bookkeeping, and Reporting for One-Person Companies | AI CFO | Commercial | Cluster (Pillar C) | `/blog/ai-cfo/` | 8h | Carryover; $15K/mo pricing row |
| P2.4 | The Agentic Engineering Workflow (brainstorm → plan → implement → review → compound) | agentic engineering workflow, compound engineering | Informational (shareable) | Cluster (Pillar B) | `/blog/agentic-engineering-workflow/` | 10h | Carryover; methodology ownership |
| P2.5 | Claude Code Plugin vs MCP Server: When to Use Which | claude code plugin vs MCP | Informational | Cluster (Pillar A) | `/blog/plugin-vs-mcp/` | 6h | Carryover; ecosystem clarity |
| P2.6 | Add FAQ blocks to `/getting-started/` and `/vision/` | how do I install Soleur; what is the Soleur vision | Informational | FAQ (edit) | `/getting-started/`, `/vision/` | 2h | AEO P2-6 |
| P2.7 | Expand homepage `og:title` + align BlogPosting JSON-LD image with OG | N/A (meta) | N/A | Site edit | `plugins/soleur/docs/_includes/*.njk` | 1h | SEO P1 (cross-posted to seo-aeo agent for JSON-LD half) |

### P3 — Ship next quarter

| ID | Title | Target keyword | Intent | Content type | Target URL | Effort | Audit findings addressed |
|---|---|---|---|---|---|---|---|
| P3.1 | How I Built Soleur Using Soleur: A Founder's Log | build product with AI agents, founder log AI | Informational (shareable) | Cluster (Pillar C) | `/blog/how-i-built-soleur-using-soleur/` | 16h | Carryover; AEO 2.7 E-E-A-T (6/10) |
| P3.2 | Compound Engineering: Why AI Agents Should Learn From Every Session | compound engineering, AI agent memory | Informational (shareable) | Cluster (Pillar B) | `/blog/compound-engineering/` | 10h | Carryover; term ownership |
| P3.3 | Soleur vs Cofounder.co vs n8n Agents: Honest Comparison | Cofounder.co alternative, n8n alternative agents | Commercial | Comparison (Pillar A/C) | `/blog/soleur-vs-cofounder-n8n/` | 10h | Carryover; vs-series gap |
| P3.4 | Glossary / Key Concepts page | what is an AI agent, MCP definition, agentic engineering definition | Informational | Reference page | `/glossary/` | 8h | Carryover; AEO extractability |
| P3.5 | External-presence operational plan (12-week) | N/A (process) | N/A | Process doc | knowledge-base/marketing/ | Ongoing | Carryover; AEO P1-5 (third-party mentions) |

---

## Scoring Matrix (Content Track)

Each piece scored 1–5 on customer impact, content-market fit, search potential, and inverse resource cost. Site-fixes track is excluded (all SF-N items score high on speed/impact and should ship as a single bundle). Content-track scores carried from 2026-04-18 plan — scoring unchanged because neither the competitive set nor ICP shifted.

| # | Title | Impact | Fit | Search | Cost (inv) | Total |
|---|---|:---:|:---:|:---:|:---:|:---:|
| P1.1 | Claude Code Plugins pillar | 5 | 5 | 5 | 3 | **18** |
| P1.6 | Solo Founder AI Stack | 5 | 5 | 5 | 3 | **18** |
| P1.2 | Agentic Engineering pillar | 5 | 5 | 4 | 3 | **17** |
| P1.3 | AI CTO | 4 | 5 | 4 | 4 | **17** |
| P1.4 | AI CMO | 4 | 5 | 4 | 4 | **17** |
| P3.4 | Glossary page | 3 | 5 | 3 | 5 | **16** |
| P1.5 | AI Agents vs SaaS | 4 | 4 | 5 | 3 | **16** |
| P2.1 | How to Build a Claude Code Plugin | 3 | 4 | 4 | 4 | **15** |
| P2.2 | AI General Counsel | 4 | 4 | 3 | 4 | **15** |
| P2.3 | AI CFO | 4 | 4 | 3 | 4 | **15** |
| P2.5 | Plugin vs MCP | 3 | 4 | 3 | 5 | **15** |
| P3.3 | Soleur vs Cofounder vs n8n | 4 | 4 | 3 | 4 | **15** |
| P2.4 | Agentic Engineering Workflow | 3 | 5 | 3 | 3 | **14** |
| P3.1 | How I Built Soleur Using Soleur | 5 | 5 | 2 | 2 | **14** |
| P3.2 | Compound Engineering | 3 | 5 | 2 | 3 | **13** |

Top three by score: **P1.1 (Claude Code Plugins pillar), P1.6 (Solo Founder AI Stack), P1.2 (Agentic Engineering pillar)** — unchanged from last cycle; priorities validated rather than shifted.

---

## Searchable vs Shareable Balance

| Tier | Searchable | Both | Shareable | Site-fixes | Notes |
|---|:---:|:---:|:---:|:---:|---|
| P1 | 3 | 2 | 1 | 11 | Good balance; site-fixes run in parallel |
| P2 | 5 | 0 | 1 | 2 | Searchable-heavy (expected for cluster build-out) |
| P3 | 1 | 0 | 3 | 0 | Shifts to opinion/narrative for distribution |

Plan passes the "100% searchable flagged as missing shareable" check. Shareable anchors: P1.5 (category opinion), P2.4 (methodology), P3.1 (founder log), P3.2 (methodology).

---

## Brand Voice Compliance

All content-track items and site-fix rewrites conform to brand-guide `Voice`:

- Declarative sentences, short and punchy (per "Keep sentences short and punchy")
- No banned phrases: "AI-powered", "copilot", "just", "simply", "terminal-first"
- Human-in-the-loop trust scaffold preserved on role-replacement clusters (P1.3, P1.4, P2.2, P2.3)
- Technical register on P1.1, P1.2, P2.1, P2.4, P2.5; general register on P1.3–P1.6, P2.2, P2.3, P3.1
- Solar Forge visual identity assumed for any hero/banner assets on new pillar pages

---

## Methodology

- Inputs: three 2026-04-19 audits (content, AEO 81/B, SEO 93/A) + brand guide + content-strategy.md + 2026-04-18 plan for carryovers.
- Carryovers explicitly enumerated — no duplicate content commissioned.
- Audit traceability: every P1/P2/P3 item cites the specific audit finding it addresses.
- Scope boundary respected: JSON-LD, `llms.txt`, robots.txt AI-crawler allowlist, and Cloudflare bot-rule edits flagged here as findings but owned by the seo-aeo-analyst agent and ops (terraform `apps/web-platform/infra/`).
- Competitor set unchanged in 24-hour window; keyword research carried forward with deltas noted.

---

## Next Actions

1. **Immediate (this week):** Bundle SF-1…SF-11 into a single `/soleur:growth fix --apply` PR. ~13h of effort, narrow scope.
2. **Infra ticket (P0, parallel):** File Cloudflare-bot-allowlist issue on the `apps/web-platform/infra/` terraform root. Owner: ops. Blocks every AEO lift until resolved.
3. **Pillar promotion decision (C3):** Decide 301 vs canonical for `/blog/what-is-company-as-a-service/` → `/company-as-a-service/`. Owner: seo-aeo-analyst.
4. **Content assignments (P1.1-P1.6):** Assign to content-writer agent or founder. Six pieces, ~70h total.
5. **Citation-monitoring setup (P3.5):** Monthly query sweep on 10 seeds across ChatGPT, Claude, Perplexity. Owner: CMO.
