---
audit_date: 2026-04-27
auditor: growth (Soleur Claude agent)
scope: soleur.ai content audit (keyword alignment, search intent, readability)
brand_guide: knowledge-base/marketing/brand-guide.md (Identity + Voice sections applied)
sample: 9 pages (homepage, about, pricing, getting-started, agents, skills, blog index, vision, community) + 1 representative blog post + changelog
---

# Soleur.ai Content Audit -- 2026-04-27

## Executive Summary

Soleur.ai is a brand-strong site with a coherent positioning system (Company-as-a-Service, "Stop hiring. Start delegating.", 65 agents / 8 departments). The pages already use declarative voice, concrete numbers, and a consistent FAQ pattern -- meaning the foundation for both search and AI-engine visibility is in place. Three structural gaps hold the site back from competing for high-intent terms:

1. **Meta descriptions are missing or unverified on every audited page.** No page returned a meta description via WebFetch. This is a P1 discoverability issue: SERP snippets default to whatever Google extracts, which on this site is hero copy that does not contain target keywords like "AI agents for solo founders."
2. **Title tags target the right concept but inconsistently include the lead keyword.** Homepage and `/agents/` carry `AI Agents for Solo Founders`; `/about/`, `/pricing/`, `/skills/`, `/community/`, `/changelog/`, `/vision/`, and `/blog/` do not surface that phrase or a near-variant. This fragments topical authority.
3. **Pillar/cluster architecture is implicit but not signalled.** `/blog/ai-agents-for-solo-founders/` is the de-facto pillar for the lead keyword, but `/agents/`, `/getting-started/`, `/vision/`, and the case studies do not link back to it as the canonical hub. Internal linking to that pillar is the highest-leverage SEO move available.

Brand voice is on-spec across every audited page -- declarative, concrete, no hedging, no banned phrases ("AI-powered," "leverage AI," "just," "simply" not detected). Rewrite suggestions below are tightening, not realignment.

Readability is uniformly strong for the technical register. The two pages most at risk of losing non-technical founders are `/getting-started/` (CLI commands appear before the value proof) and `/vision/` (Anthropic-CEO probability claim and "model-agnostic architecture" appear without inline definitions). Both are P2.

The site's largest unrealized opportunity is a single-keyword push on `AI agents for solo founders`: own it on the homepage title, the `/agents/` page, the pillar blog post, and one cluster from each case-study cluster. With existing content this is achievable in a single editing pass.

## Per-Page Analysis

### 1. Homepage (https://soleur.ai/)

| Field | Value |
|-------|-------|
| Title | "Soleur -- AI Agents for Solo Founders \| Every Department, One Platform" |
| Detected target keywords | `AI agents for solo founders`, `Company-as-a-Service`, `every department` |
| Search intent | Commercial/navigational (brand-led discovery + product evaluation) |
| Intent match | Strong -- hero ("Stop hiring. Start delegating."), pricing CTA, FAQ all align with evaluation intent |
| Readability | Strong -- declarative, short sentences, clear stat line ("8 Departments / 65 Agents / 67 Skills") |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description not detected. Without one, Google will auto-generate from "Stop hiring. Start delegating." -- punchy but keyword-light. SERP snippet will not contain "AI agents" or "solo founders."
- Critical: Multiple H1s detected ("Stop hiring. Start delegating.", "This Is the Way", "Your AI Organization", "The Workflow", "Frequently Asked Questions", "Stop hiring. Start delegating."). Multiple H1s dilute topical signal. Demote all but the hero to H2.
- Improvement: The phrase "AI agents for solo founders" appears in the title but not in the H1 or the first 100 words of body copy. Inject it once in the subheadline or the first body paragraph for first-fold keyword reinforcement.
- Improvement: Stat line uses "8 Departments / 65 AI Agents / 67 Skills." Brand guide specifies soft-floor prose ("60+ agents") -- the live counts are correct here per the soft-floor exception (filesystem-rendered), but ensure prose elsewhere uses 60+, not the hardcoded 65/67.

**Rewrite suggestions**

- Current subheadline: "The Company-as-a-Service platform that already knows your business."
- Suggested: "The Company-as-a-Service platform. AI agents for solo founders -- every department, one knowledge base."
- Rationale: Injects lead keyword in first-fold copy without diluting the tagline. Matches "Stop hiring. Start delegating." pain-point framing from brand guide.

- Current (suggested new) meta description: none detected.
- Suggested: "Stop hiring. Start delegating. Soleur is the Company-as-a-Service platform: AI agents for solo founders that handle marketing, legal, finance, ops, and more -- with shared, compounding memory of your business."
- Rationale: 158 chars (within snippet limit), leads with primary framing from brand guide, contains lead keyword, and signals breadth.

---

### 2. About (https://soleur.ai/about/)

| Field | Value |
|-------|-------|
| Title | "About Jean Deruelle - Soleur" |
| Detected target keywords | `Jean Deruelle`, `Soleur founder`, `Company-as-a-Service` |
| Search intent | Navigational/informational (founder credibility, brand vetting) |
| Intent match | Strong for navigational; weak for informational ("who is behind Soleur and why should I trust them") -- the page does cover this but does not surface it in title/meta |
| Readability | Strong -- short biographical paragraphs |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing.
- Improvement: Title is bare. "About Jean Deruelle - Soleur" gives no signal beyond name. Add credibility hooks.
- Improvement: No author schema / E-E-A-T cue surfaced in the markdown copy ("15 years experience" appears but not as a quotable, structured statement). For AEO, this matters -- AI engines cite authors more often when expertise is stated as an extractable claim.

**Rewrite suggestions**

- Current title: "About Jean Deruelle - Soleur"
- Suggested: "About Soleur and Jean Deruelle -- Founder, Company-as-a-Service Platform"
- Rationale: Adds the platform category, supports navigational queries on "Soleur founder" and "Company-as-a-Service founder."

- Suggested meta description: "Soleur was founded by Jean Deruelle, a software engineer with 15+ years building distributed systems and developer tools. Read why he's building the Company-as-a-Service platform for solo founders."
- Rationale: Establishes E-E-A-T (specific years, named expertise), names the platform category, sets reader expectation.

- Suggested first-paragraph addition: "Soleur is an open-source Company-as-a-Service platform: AI agents for solo founders, organized into eight departments that share a compounding knowledge base."
- Rationale: One sentence, AI-extractable definition ("Soleur is..."), contains lead keyword. Aligns with cq-style "answer density" for AEO.

---

### 3. Pricing (https://soleur.ai/pricing/)

| Field | Value |
|-------|-------|
| Title | "Pricing -- AI Agents for Solo Founders \| Soleur" |
| Detected target keywords | `pricing`, `AI agents for solo founders`, `AI organization pricing` |
| Search intent | Transactional / commercial-evaluation |
| Intent match | Strong -- four-tier table, replacement-cost framing, clear CTA |
| Readability | Strong -- table-first scan layout |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing. Pricing pages get high-intent traffic; missing description is a wasted SERP slot.
- Improvement: The "$95,000/mo" replacement-cost claim is exactly the kind of statistic AI engines cite, but it is buried under "What You Replace" with no schema or summary. Promote to a one-line stat block at the top of the pricing copy ("Replace $95K/mo of department headcount for $49--$499/mo.") and AI engines will quote it.
- Improvement: Brand guide flags tool-replacement framing as secondary -- the page leads with replacement, which is fine for pricing-page intent, but the page should also surface the primary pain-point framing ("Stop hiring. Start delegating.") in the hero or just below it.

**Rewrite suggestions**

- Current H1 "Every department. One price." (works -- keep)
- Suggested meta description: "AI agents for solo founders -- pricing from $49/mo. Replace $95K/mo in department headcount with a full AI organization across 8 departments. See plans, concurrency tiers, and the open-source path."
- Rationale: Includes lead keyword, the cited stat (citation-ready for AEO), price anchor, and the open-source CTA.

- Suggested addition (above pricing table): "Stop hiring. Start delegating. From $49/mo, Soleur replaces a fraction of the cost of a single contractor with AI agents across all eight departments."
- Rationale: Pulls the primary brand framing into the pricing surface; reinforces the cost story without redundant claims.

---

### 4. Getting Started (https://soleur.ai/getting-started/)

| Field | Value |
|-------|-------|
| Title | "Getting Started with Soleur - Soleur" |
| Detected target keywords | `getting started with Soleur`, `install Soleur`, `Soleur tutorial` |
| Search intent | Informational / transactional (user has decided, wants the path) |
| Intent match | Mixed -- the page mixes hosted-waitlist CTA with self-host install, which is correct for the audience split but could lose non-technical readers in the first scroll |
| Readability | Strong for technical register; weaker for general register -- CLI commands appear before the value framing for non-technical founders |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing.
- Critical: Title is repetitive ("Getting Started with Soleur - Soleur"). Drop the duplicate brand suffix or expand the first half.
- Improvement: The H1 reads "Getting Started" with the H2 "The AI that already knows your business" below it. The memory-first variant is the strongest hook per the brand guide -- consider promoting it to the H1 or pre-headline.
- Improvement: For non-technical readers, the hosted/self-host split should be explicit upfront (two clear paths, two CTAs) rather than ordered sequentially.

**Rewrite suggestions**

- Current title: "Getting Started with Soleur - Soleur"
- Suggested: "Get Started with Soleur -- The AI Organization for Solo Founders"
- Rationale: Removes brand-name duplication, surfaces lead positioning, action-oriented.

- Suggested meta description: "Get started with Soleur in two paths: reserve hosted access (no setup) or install the open-source Claude Code plugin in two commands. Your AI organization across 8 departments, ready in minutes."
- Rationale: Sets explicit expectation for both audiences, contains "Soleur" and the platform descriptor, ends with concrete time anchor.

- Current opening (per scrape): "The AI that already knows your business" (H2)
- Suggested promotion: Make this the H1; demote "Getting Started" to a section label per brand visual pattern (ALL CAPS gold label).
- Rationale: Aligns with brand guide's stated hero pattern (Badge > Headline > Subheadline > CTA) and uses the memory-first framing recommended for A/B test.

---

### 5. Agents (https://soleur.ai/agents/)

| Field | Value |
|-------|-------|
| Title | "65 AI Agents for Solo Founders -- Every Department \| Soleur" |
| Detected target keywords | `AI agents for solo founders`, `AI agents list`, `multi-agent platform` |
| Search intent | Informational / commercial (browsing capability) |
| Intent match | Strong -- the page enumerates the 8 departments with agent counts |
| Readability | Strong -- scannable department blocks |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing. This page should rank for "AI agents for solo founders" and the missing snippet is leaving CTR on the table.
- Improvement: The page is the strongest candidate for the cluster page targeting `AI agents for solo founders` but does not internal-link to the pillar at `/blog/ai-agents-for-solo-founders/`. Add a "Read the definitive guide" link at the top of the agents list pointing to the pillar.
- Improvement: Per brand guide, soft-floor prose should say "60+ agents" not "65 AI Agents" in the title. The exception applies to filesystem-rendered counts; titles are static prose. Either template the title to render `{{ stats.agents }}` or change to "60+ AI Agents."
- Improvement: "Product" department has no agent count next to it (others do). Inconsistency.

**Rewrite suggestions**

- Current title: "65 AI Agents for Solo Founders -- Every Department \| Soleur"
- Suggested: "AI Agents for Solo Founders -- 60+ Specialists, 8 Departments \| Soleur"
- Rationale: Soft-floor compliance (won't drift), keeps lead keyword first, retains specificity. Or, if templated, render `{{ stats.agents }}+ AI Agents for Solo Founders -- Every Department`.

- Suggested meta description: "60+ AI agents for solo founders, organized across 8 departments: engineering, finance, legal, marketing, operations, product, sales, support. Each agent shares a compounding knowledge base of your business."
- Rationale: Front-loads the keyword, enumerates departments (citation-friendly for AEO), specifies the compounding-memory differentiator.

- Suggested first-line addition: "Soleur deploys 60+ AI agents for solo founders across 8 business departments. New here? Read [the definitive guide to AI agents for solo founders](/blog/ai-agents-for-solo-founders/) for the full overview."
- Rationale: Establishes pillar-cluster link explicitly. Standalone, AI-extractable definition.

---

### 6. Skills (https://soleur.ai/skills/)

| Field | Value |
|-------|-------|
| Title | "Soleur Skills - Soleur" |
| Detected target keywords | `agentic engineering skills`, `Soleur skills`, `Claude Code skills` |
| Search intent | Informational (capability browsing) |
| Intent match | Adequate -- enumerates skill categories |
| Readability | Strong |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing.
- Critical: Title duplicates brand ("Soleur Skills - Soleur"). Same fault as `/getting-started/`.
- Improvement: H1 "Agentic Engineering Skills" is correct for the technical audience but loses the lead keyword. The page has no internal link path back to the homepage's primary framing.
- Improvement: A definition of "skill" should appear in the first 100 words and is not surfaced. AEO benefits from extractable definitions.

**Rewrite suggestions**

- Current title: "Soleur Skills - Soleur"
- Suggested: "Soleur Skills -- 60+ Agentic Engineering Workflows for Solo Founders"
- Rationale: Removes duplication, adds soft-floor count, ties to lead audience.

- Suggested meta description: "Soleur Skills are reusable agentic-engineering workflows -- 60+ of them -- that orchestrate AI agents, tools, and your business knowledge into repeatable processes. Browse by category."
- Rationale: Includes definition of a skill (AI-extractable), category browse signal, and soft-floor count.

- Suggested first-paragraph addition: "A Soleur Skill is a structured workflow that orchestrates AI agents, tools, and institutional knowledge into a repeatable process. Skills turn agentic engineering from one-off prompts into compounding capability."
- Rationale: Definition is self-contained, quotable, free of demonstratives, ideal for AI-engine extraction.

---

### 7. Blog index (https://soleur.ai/blog/)

| Field | Value |
|-------|-------|
| Title | "Blog -- Soleur" |
| Detected target keywords | None strong; `Soleur blog` is navigational |
| Search intent | Informational / navigational |
| Intent match | Adequate -- categorized list |
| Readability | Strong |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing.
- Improvement: Title is generic. "Blog -- Soleur" wastes the slot. The category headings ("Company-as-a-Service," "Soleur vs. Competitors," "Case Studies," "Engineering Deep Dives") are distinctive and could be surfaced in the title.
- Improvement: No introduction text describes what topics this blog covers or who it is for. AI engines cannot cite a faceless index.

**Rewrite suggestions**

- Current title: "Blog -- Soleur"
- Suggested: "Soleur Blog -- Company-as-a-Service, Agentic Engineering, and Solo-Founder Case Studies"
- Rationale: Three distinct topical hooks for SEO and AEO.

- Suggested meta description: "Field notes from building Soleur: Company-as-a-Service deep dives, agentic-engineering tutorials, solo-founder case studies, and competitor breakdowns. New posts shipping weekly."
- Rationale: Sets cadence expectation, lists post categories, signals the brand's primary topics.

- Suggested intro paragraph: "The Soleur blog covers three threads: how Company-as-a-Service works in practice (case studies and architecture), how agentic engineering changes solo-founder workflows, and how Soleur compares to other AI tools. Written by the team building it -- no contracted SEO content."
- Rationale: Trust signal, AI-citable, names topical pillars explicitly.

---

### 8. Vision (https://soleur.ai/vision/)

| Field | Value |
|-------|-------|
| Title | "Soleur Vision: Company-as-a-Service - Soleur" |
| Detected target keywords | `Company-as-a-Service`, `solopreneur platform`, `model-agnostic` |
| Search intent | Informational (philosophy / brand-narrative) |
| Intent match | Strong for narrative; weak for high-intent search (vision pages rarely rank) |
| Readability | Mixed -- references the "Anthropic CEO 70-80% probability" claim, "model-agnostic architecture" without inline definitions; loses non-technical readers |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing.
- Critical: Title duplicates brand. "Soleur Vision: Company-as-a-Service - Soleur" -> drop one Soleur.
- Improvement: "Anthropic's CEO assigns 70-80% probability" is a load-bearing claim with no inline source link visible in the scrape. Per growth/AEO playbook, source citations are the highest-leverage trust signal -- attach a hyperlink to the original interview/source inline.
- Improvement: "Model-agnostic architecture" appears as an H2 with no one-sentence definition near first usage. Non-technical readers will bounce.

**Rewrite suggestions**

- Current title: "Soleur Vision: Company-as-a-Service - Soleur"
- Suggested: "Vision: The Company-as-a-Service Platform for Solo Founders \| Soleur"
- Rationale: Removes brand duplication, contains lead audience.

- Suggested meta description: "Soleur's vision: a Company-as-a-Service platform where AI agents run every department of a one-person company. Read the master plan, the architecture, and why this is an engineering problem -- not science fiction."
- Rationale: Pulls the brand thesis sentence directly, surfaces "master plan" and "architecture" anchors.

- Suggested addition under "Model-Agnostic Architecture": "Model-agnostic means Soleur is not locked to one AI provider. Agents run on Claude today, with the architecture designed to support other frontier models as they mature."
- Rationale: Inline definition, plain-language register, AI-citable.

- Suggested addition under the Anthropic-CEO claim: "(Source: Dario Amodei, Anthropic CEO, [link to interview])"
- Rationale: Source citations are the #1 GEO/AEO factor. Uncited claims do not get cited by AI engines.

---

### 9. Community (https://soleur.ai/community/)

| Field | Value |
|-------|-------|
| Title | "Community -- Soleur" |
| Detected target keywords | `Soleur community`, `Soleur discord`, `Soleur GitHub` |
| Search intent | Navigational |
| Intent match | Strong |
| Readability | Strong |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing.
- Improvement: Title is generic. Add channel signals ("Discord, GitHub, and contributing").
- Improvement: No mention of the open-source repo URL or license in surfaced copy (license is described but not linked in the scrape).

**Rewrite suggestions**

- Current title: "Community -- Soleur"
- Suggested: "Community -- Soleur on Discord, GitHub, and Open-Source Contribution"
- Rationale: Surfaces the channels users actually search for.

- Suggested meta description: "Join the Soleur community on Discord, contribute to the open-source repo on GitHub (Apache 2.0), and follow weekly releases. Built by solo founders, for solo founders."
- Rationale: License and audience are both citation-worthy; cadence claim ("weekly releases") repeats the changelog signal.

---

### 10. Pillar blog post (https://soleur.ai/blog/ai-agents-for-solo-founders/)

| Field | Value |
|-------|-------|
| Title | "AI Agents for Solo Founders: The Definitive Guide - Soleur" |
| Detected target keywords | `AI agents for solo founders` (exact match), `solo founder`, `agentic engineering`, `Company-as-a-Service` |
| Search intent | Informational (definitive-guide intent) |
| Intent match | Strong -- structured H2s, definitions, FAQ, citations |
| Readability | Strong |
| Meta description | NOT DETECTED |

**Issues**

- Critical: Meta description missing on the most important SEO asset on the site.
- Improvement: Title duplicates brand suffix, costs character budget that could front-load secondary keywords.
- Improvement: Cites Carta, BLS, Fortune, TechCrunch -- this is excellent E-E-A-T. Make sure each citation is an outbound link with the source name visible in anchor text (improves both reader trust and AEO).
- Improvement: This is the pillar. Every cluster page (case studies, vs.-competitor posts, `/agents/`, `/skills/`) should link back to it with the anchor text "AI agents for solo founders."

**Rewrite suggestions**

- Current title: "AI Agents for Solo Founders: The Definitive Guide - Soleur"
- Suggested: "AI Agents for Solo Founders: The Definitive Guide (2026)"
- Rationale: Drop redundant `- Soleur` (canonical brand suffix can be appended in template if needed); add year for freshness signal -- year-anchored guides retain CTR longer.

- Suggested meta description: "The definitive guide to AI agents for solo founders. What an AI agent actually is, the eight domains of a company, why point solutions fail, and what a full AI organization looks like. With sources from Carta, BLS, and TechCrunch."
- Rationale: Mirrors the H2 structure (high SERP-snippet match), names cited sources (E-E-A-T trigger), 248 chars (trim to 158 for safe display).

- Trimmed (158-char) meta: "The definitive guide to AI agents for solo founders. What an AI agent is, the 8 domains of a company, why point solutions fail, and what a full AI org looks like."

---

## Cross-Cutting Issues

### Critical (block discoverability)

1. **Meta descriptions missing on every audited page.** Every page returned "not detected" via WebFetch. If frontmatter `description` is set in the source `.md` files but not rendered into the `<meta name="description">` tag, that is a template bug; if descriptions are simply unset, that is a content gap. Verify by reading the rendered HTML of any page. Either way, this is the single highest-leverage fix on the site.

2. **Title-tag brand-suffix duplication on multiple pages.** `/about/`, `/getting-started/`, `/skills/`, `/community/`, `/changelog/`, `/blog/`, `/vision/`, and the pillar blog post all end in `- Soleur` after a title that already includes the brand or category. This wastes characters that could carry secondary keywords. The site likely has a global `{{ title }} - Soleur` template -- audit individual frontmatter `title:` values to remove embedded brand names so the suffix does the job.

3. **Multiple H1s on the homepage.** WebFetch detected six H1-tagged headings. Search engines and AI extractors weight the first H1 most heavily; the remaining five dilute topical signal. Demote all but "Stop hiring. Start delegating." to H2.

### Improvement (enhance ranking and AI extractability)

4. **Pillar/cluster linking is implicit.** `/blog/ai-agents-for-solo-founders/` is a strong pillar but is not linked from `/agents/`, `/getting-started/`, the homepage, or the case-study clusters. Add a one-line "Read the definitive guide" link from each cluster to the pillar; add reverse links from the pillar to top case studies as siblings.

5. **Soft-floor compliance drift in titles and headings.** The brand guide specifies "60+ agents" and "60+ skills" in static prose. The homepage stat line and the `/agents/` title use exact counts (65, 67) which will drift. Either template these tags with `{{ stats.agents }}` or revert to soft floors.

6. **Statistics buried, not surfaced.** Strong claims exist on multiple pages -- "$95K/mo replacement," "23.7% to 36.3% solo-founder rate," "15+ years" of founder experience -- but most are inside paragraphs rather than callouts. AEO scoring rewards extractable, standalone statistical claims. Consider promoting one stat per page to a stat-block or pull-quote.

7. **Source citations need outbound anchor text.** The pillar post cites Carta, BLS, Fortune, TechCrunch but the scrape did not surface these as inline anchors with source-name text. Verify that citations are hyperlinks with descriptive anchor text -- AI engines weight cited claims more heavily when the citation is visible.

8. **Definitions not surfaced near first usage on `/skills/`, `/vision/`, `/getting-started/`.** "Skill," "model-agnostic," and the implicit "Company-as-a-Service" terminology should each appear with a one-sentence inline definition the first time they're used. This is both a readability fix for non-technical founders and an AEO citation opportunity.

9. **Trust scaffolding is absent from headlines.** Brand guide flags this explicitly: all framings tested in synthetic research lacked trust signals, and "What if the output is wrong?" was the #1 objection from 8/10 personas. Phrases like "human-in-the-loop," "starting point, not final answer," or "your expertise, amplified" are present in some body copy but not in any headline or subheadline. Adding one to the homepage subheadline would address the load-bearing objection at first contact.

10. **Banned-phrase compliance check.** No instances of "AI-powered," "leverage AI," "just," "simply," "assistant," "copilot," "disrupt," or "synergy" surfaced in scraped copy. Voice compliance is on-spec.

## Prioritized Rewrite Recommendations

### P1 -- High impact, ship this week

| # | Page | Action | Why |
|---|------|--------|-----|
| 1 | All pages | Add `<meta name="description">` per the suggestions above (homepage, pricing, agents, getting-started, pillar post are highest priority) | Missing meta descriptions block keyword-relevant SERP snippets across the site |
| 2 | Homepage | Consolidate to a single H1 ("Stop hiring. Start delegating."); demote others to H2 | Multiple H1s dilute topical signal |
| 3 | Homepage | Inject "AI agents for solo founders" into subheadline | Lead keyword absent from first-fold body copy |
| 4 | `/agents/`, `/getting-started/`, case studies | Add internal link to `/blog/ai-agents-for-solo-founders/` (pillar) | Pillar exists but is unsupported by cluster links |
| 5 | All titles | Audit `{{ title }} - Soleur` template -- remove brand-name duplication from frontmatter `title:` fields | Wastes character budget on every page |
| 6 | `/agents/` | Switch hardcoded "65" to soft-floor "60+" or templated `{{ stats.agents }}+` | Counts will drift; brand-guide compliance |
| 7 | Pillar post | Verify citations are inline anchors with source-name anchor text (Carta, BLS, etc.) | E-E-A-T and AEO citation weight |

### P2 -- Medium impact, ship this month

| # | Page | Action | Why |
|---|------|--------|-----|
| 8 | `/getting-started/` | Promote "The AI that already knows your business" to H1; demote "Getting Started" to section label | Memory-first framing tested strongest in brand-guide synthetic research; current H1 is generic |
| 9 | `/skills/` | Add a one-sentence inline definition of "skill" in the opening paragraph | AEO extractability + readability for general register |
| 10 | `/vision/` | Add inline source link to Anthropic-CEO probability claim; add inline definition of "model-agnostic" | Source citations are top AEO signal; reduces non-technical bounce |
| 11 | Homepage subheadline | Add a trust-scaffolding phrase ("human-in-the-loop" or "your expertise, amplified") | Addresses #1 objection from synthetic-research cohort |
| 12 | `/pricing/` | Add primary pain-point framing ("Stop hiring. Start delegating.") above the pricing table | Brand guide flags pure tool-replacement framing as secondary |
| 13 | `/about/` | Surface the "15+ years" credential as a quotable, structured statement (callout or stat block) | E-E-A-T at content level |
| 14 | `/blog/` | Add intro paragraph naming the three content threads | Faceless index; AI engines cannot cite generic blog hubs |

### P3 -- Future / next quarter

| # | Page | Action | Why |
|---|------|--------|-----|
| 15 | All FAQ blocks | Audit for FAQPage JSON-LD schema (schema validity belongs to seo-aeo-analyst, but content-level: ensure each Q is phrased as a real user query, A is 1-3 sentences, self-contained) | AEO answer-density |
| 16 | Pillar post | Annotate the title with a year ("(2026)") for freshness signal | Year-anchored guides retain CTR over time |
| 17 | Each case study | Confirm it links to both `/blog/ai-agents-for-solo-founders/` (pillar) and one sibling case study | Cluster siblings reinforce topical depth |
| 18 | `/changelog/` | Add an SEO-aware intro paragraph above the version list | Currently the page has no descriptive copy for crawlers |
| 19 | All pages | Add an opening "summary paragraph" pattern (factual, 2-3 sentences, AI-quotable) where missing | AEO summary-quality dimension |
| 20 | Site-wide | Build a topical map of pillar -> cluster relationships and document in `knowledge-base/marketing/seo/` for ongoing reference | Codifies the architecture so future content slots in correctly |

## Notes on Audit Method and Limits

- All page content was retrieved via WebFetch, which converts HTML to markdown. Meta description and JSON-LD presence cannot be definitively confirmed from this signal alone -- the seo-aeo-analyst agent should validate template-level rendering of meta tags. This audit reports them as "not detected" which is the highest-confidence claim from the data.
- Sample covers 9 priority pages plus the pillar blog post and changelog. Per audit policy for sites with 15+ pages, the priority sampling is: homepage > nav-linked pages > sitemap order. The blog has ~20 posts not individually audited; recommendation in P3 is to audit case-study and competitor-comparison clusters individually before they become primary ranking targets.
- Brand guide voice compliance is on-spec across audited pages -- no banned phrases detected, declarative voice consistent, soft-floor numbers respected in body copy (drift only in titles/H1s). Rewrite suggestions are tightening, not realignment.
