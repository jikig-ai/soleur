---
plan_date: 2026-04-27
author: growth (Soleur Claude agent)
scope: Soleur.ai prioritized content plan (audit-driven fixes + new content opportunities)
inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-04-27-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-27-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-04-27-seo-audit.md
  - knowledge-base/marketing/brand-guide.md
horizon: P1 = ship this week, P2 = ship this month, P3 = next quarter
architecture: pillar/cluster (pillar = /blog/ai-agents-for-solo-founders/)
---

# Soleur.ai Content Plan -- 2026-04-27

## Executive Summary

Soleur's site fundamentals are strong. The technical SEO audit scores 93/100 (A) -- canonical tags, JSON-LD, sitemap, llms.txt, AI-crawler access are all clean. Brand voice compliance is on-spec across every audited page. The pillar (`/blog/ai-agents-for-solo-founders/`) is a high-quality, citation-backed definitive guide. This is a healthy baseline.

Three structural problems hold the site back from compounding traffic. First, the content audit found meta descriptions are not detected on any sampled page, while the SEO audit confirms they ARE rendered in the source HTML -- meaning the bug is in the WebFetch extraction path, not the site. The work is not "add meta descriptions" but "audit each meta description string for keyword inclusion against this plan's keyword research." Second, the AEO audit (SAP 62/100, C) flags that no FAQPage JSON-LD is rendered on six FAQ-bearing pages, despite 31 Q&A pairs being present. This is the highest-leverage fix on the entire property. Third, the pillar/cluster architecture is implicit -- `/blog/ai-agents-for-solo-founders/` exists but is not internal-linked from `/agents/`, `/getting-started/`, or the case studies that should support it.

The largest content gap relative to opportunity is **`Claude Code plugin`** as a search vector. Soleur ships as a Claude Code plugin and the plugin marketplace is a high-traffic, technical-buyer surface (110K+ developers visit marketplace directories monthly per the BrightCoding/Build with Claude data) -- but Soleur has no dedicated `/blog/claude-code-plugin/` or `/plugin/` landing page, and the brand guide explicitly forbids "plugin" in headlines. This is solvable: lead with the platform framing in the H1, then use "Claude Code plugin" in body copy and meta description for technical SEO. Without it, Soleur leaves the plugin-marketplace search lane entirely to competitors.

The second-largest content gap is **`agentic engineering`**. The site uses the term consistently (`/skills/` H1: "Agentic Engineering Skills") but does not own a definition page. Industry coverage in 2026 is heavy (LangChain, Deloitte, CIO, The New Stack, Maven all published authoritative pieces), the term is expanding fast, and Soleur is one of very few companies practicing it as the core methodology. A pillar definition piece is overdue.

Recommended sequencing: ship the four P1 audit fixes this week (FAQPage schema, About/Founder page, citation closures, pillar/cluster internal links), then ship two new P1 pillar pieces (Claude Code plugin, agentic engineering definition) in the same cycle. P2 builds the searchable+shareable cluster set around the new pillars. P3 invests in third-party Presence (the Gap-4 weakness in the AEO audit) and structural site assets (glossary, citation-monitoring loop).

## Keyword Research Findings

Search volume and difficulty signals are estimated from 2026 search-result density, SERP composition, and cross-source corroboration in the live web search (volume tools were not directly queried; treat as directional). Intent classification follows the four-class framework (informational / navigational / commercial / transactional). Relevance is rated against Soleur's positioning ("Company-as-a-Service platform, AI agents for solo founders") and brand guide.

| Keyword | Intent | Est. monthly volume | Difficulty | Relevance | Notes / SERP signal |
|---------|--------|---------------------|------------|-----------|---------------------|
| `AI agents for solo founders` | Informational + commercial | Low-medium (rising) | Low | **Highest** | Lead positioning. Pillar already exists. SERP is mixed -- generic "AI tools" lists and Soleur's own pillar. Defensible if Soleur claims it now. |
| `Company-as-a-Service` | Informational | Low (emerging category) | Low | **Highest** | Brand-coined category. Soleur should own this entirely. Currently no clear SERP leader. |
| `Claude Code plugin` | Navigational + commercial | Medium-high | Medium | **High** | Marketplace search lane. SERP has Anthropic official marketplace, awesome-claude-plugins, Build with Claude. Soleur missing entirely. |
| `Claude Code plugin marketplace` | Navigational | Medium | Medium | High | Same intent, slightly different framing. Worth one targeted piece. |
| `best Claude Code plugins` | Commercial | Medium | Medium | High | Listicle SERP. Soleur should be on these lists; outreach (P3) and self-published comparison (P2) both apply. |
| `agentic engineering` | Informational | Medium (rising sharply) | Medium | **High** | LangChain, Deloitte, Maven, The New Stack, CIO all 2026 coverage. Term is solidifying. Soleur uses it as core methodology -- should publish the definitive practitioner piece. |
| `agentic engineering vs vibe coding` | Informational | Low (rising) | Low | High | Soleur already has "Vibe Coding vs Agentic Engineering" blog post -- audit it for keyword optimization. |
| `agentic workflows` | Informational | Medium-high | Medium-high | Medium | Heavily contested by enterprise-AI vendors. Soleur should reference but not lead on this. |
| `AI company automation` | Informational + commercial | Medium | Medium | High | Aligns with CaaS framing. SERP is enterprise-heavy (UiPath, Salesforce). Soleur's solo-founder angle is the differentiator. |
| `automate company with AI agents` | Informational | Low-medium | Medium | High | Same intent, plainer phrasing. Long-tail. |
| `AI tools for solo founders` | Commercial | Medium-high | Medium-high | High | High-commercial intent. SERP is dominated by listicles (Rocket.new, Siift, EntrepreneurLoop). Soleur should pursue via inclusion outreach + a strong owned listicle. |
| `solo founder AI tools` | Commercial | Medium | Medium | High | Same intent, query variant. Bundle with above. |
| `AI tools for solopreneurs` | Commercial | Medium-high | Medium-high | Medium | Slightly less aligned (Soleur targets "founders who think in billions" not lifestyle solopreneurs) but volume justifies one piece. |
| `one-person billion-dollar company` | Informational | Low (Soleur-coined adjacent) | Low | High | Soleur already has a blog post on this. Optimize for the keyword in the meta + intro. |
| `AI agents replace employees` | Informational | Medium (controversial) | Medium | Medium | Strong angle but tonally fragile -- handle with brand-guide trust scaffolding ("human-in-the-loop", "your expertise, amplified"). |
| `AI organization platform` | Commercial | Low (emerging) | Low | High | Adjacent to CaaS. Worth claiming. |
| `AI agents for marketing solo founder` | Commercial + informational | Low | Low | High | Department-vertical long-tail. Replicate pattern for legal, finance, ops, sales, product, support. |
| `Soleur` (brand) | Navigational | Low (pre-launch) | N/A | N/A | Brand search is small now; will scale with launches. Make sure the SERP top-3 are owned (homepage, About, GitHub, X). |
| `Soleur vs Cursor` / `Soleur vs Devin` etc. | Commercial | Low (will grow) | Low | High | Comparison pages exist per AEO audit. Optimize each for `Soleur vs <competitor>` exact-match queries. |

**Related queries / question-shaped keywords** (high AEO value -- these are the questions ChatGPT/Perplexity/Claude get asked):

- "What is Company-as-a-Service?"
- "What is the best AI agent platform for solo founders?"
- "How do I install a Claude Code plugin?"
- "What is agentic engineering?"
- "How is agentic engineering different from vibe coding?"
- "Can AI agents run a whole company?"
- "What is the difference between Cursor and Claude Code?"
- "How much does it cost to replace a marketing team with AI?"
- "Can a solo founder build a billion-dollar company?"

Each of these is a candidate for a dedicated FAQ entry on the relevant page AND a short blog post optimized for the question (titled exactly as the question for AEO match).

**Search-intent distribution across the keyword set:**

- Informational: ~55% (definition pieces, methodology, how-tos)
- Commercial: ~30% (comparison pages, "best X" listicles, AI tool roundups)
- Navigational: ~10% (brand, marketplace, plugin search)
- Transactional: ~5% (pricing, install, signup)

This matches Soleur's funnel: informational entry, commercial evaluation, navigational re-entry, transactional close. The plan biases toward shipping informational pillars (own the definitions) and commercial comparison content (capture evaluation), then upgrading transactional surfaces (pricing page) with cited statistics.

## Competitor Gap Analysis

Soleur's de-facto competitor set (from existing comparison pages and brand-guide context) covers four segments. This is gap-by-segment, not feature-by-feature.

### 1. Coding-tool segment: Cursor, Devin, Claude Code (raw)

These cover 30% of running a company (engineering only, per Soleur's framing). Soleur's edge is the other 70% (marketing, legal, finance, operations, product, sales, support) plus shared knowledge. **Content gaps Soleur can fill:**

- "What Cursor doesn't do" content -- not a hit piece, a value-stack diagram. Most "Soleur vs Cursor" page reads should leave with "Cursor for code, Soleur for company."
- Claude Code-native angle: Soleur is BUILT ON Claude Code. Show this as a strength, not a fork. Pieces: "How Soleur extends Claude Code into a full AI organization", "The 7 departments Claude Code doesn't ship with."
- Devin/Cognition-style autonomy comparison: explicit, citation-backed.

### 2. Workflow / automation segment: Notion AI, Cowork, Polsia, Paperclip, Zapier-with-AI

These are organizational tools with AI features bolted on. Soleur is AI organization with workflow built in. **Gaps:**

- "Why bolted-on AI fails" (methodology piece, not vendor-attack).
- Existing comparison pages exist (Cowork, Notion, Polsia, Paperclip per AEO audit) -- audit each for FAQ schema, citations, exact-match meta titles ("Soleur vs Notion AI for Solo Founders").

### 3. Listicle + AI-tool-directory traffic: Rocket.new blog, Siift, EntrepreneurLoop, "best AI tools for solo founders" roundups

These dominate the `AI tools for solo founders` SERP. Soleur appears in NONE per AEO Gap 4. **Two-pronged gap close:**

- Outreach (P3): submit Soleur to AI-agent directories (There's An AI For That, AI Agents Directory, Futurepedia, Product Hunt). Pitch inclusion in dev.to, IndieHackers, HN-friendly newsletter roundups.
- Self-publish a stronger version (P2): "The full AI tool stack for solo founders -- 2026" listicle with Soleur framed as the orchestrator above the stack, not a competitor within it. This both ranks for the listicle keyword and demonstrates Soleur's architectural role.

### 4. Industry-thought-leadership segment: LangChain, Deloitte, CIO, The New Stack on agentic engineering

These define the term Soleur uses as core methodology. They are not competitors for buyers, but they are competitors for SEO authority on `agentic engineering`. **Gap:**

- Soleur is one of very few full-stack practitioners. Publish a definition piece that is more concrete than LangChain's, more practitioner than Deloitte's, more methodology-deep than CIO's. Cite all four.
- Internal-link the existing "Vibe Coding vs Agentic Engineering" post into the new pillar.

### Net competitor positioning

Soleur is alone in the "Company-as-a-Service for solo founders" category. The brand-coined term is both a moat and a marketing burden -- nobody is searching for it yet. The plan therefore biases toward winning **adjacent searched terms** (`AI agents for solo founders`, `agentic engineering`, `Claude Code plugin`) and using each ranking page to introduce CaaS as the category Soleur invented.

## Scoring Matrix Used to Prioritize

Each candidate piece is scored 1-5 on four axes. Total = sum (max 20). Higher = ship sooner.

| Axis | What it measures |
|------|------------------|
| Customer impact | Does the topic matter to ICP (technical solo founder, $10-50K MRR or pre-revenue with conviction)? |
| Content-market fit | Can Soleur write this credibly today (existing knowledge base, founder voice, real case studies)? |
| Search potential | Estimated traffic volume * achievable rank position (volume alone is not enough). |
| Resource cost | Inverse: 5 = cheap to ship (existing material, edit pass), 1 = expensive (new research, original data). |

Pieces scoring 16+ go P1. 12-15 go P2. Below 12 go P3 (or get cut).

## Content Architecture: Pillar / Cluster Map

Three pillars. Each has 3-6 cluster pieces that link to the pillar and at least one sibling cluster.

### Pillar A -- AI Agents for Solo Founders (existing, optimize)

URL: `/blog/ai-agents-for-solo-founders/` (live)

Clusters (some live, some new):

- (live) `/agents/` -- product page, link to pillar
- (live) Case studies -- link each to pillar + one sibling case study
- (new P2) "AI agents for marketing as a solo founder" (and one per department -- legal, finance, ops, sales, product, support)
- (new P2) "Can a solo founder build a billion-dollar company?" -- shareable, opinion-led, links to pillar

### Pillar B -- Agentic Engineering (new, P1)

URL (proposed): `/blog/agentic-engineering/` or `/agentic-engineering/`

Clusters:

- (live) `/skills/` -- product page, link to pillar
- (live) "Vibe Coding vs Agentic Engineering" -- link to pillar
- (live) "Knowledge Compounding" 2026-04-23 -- link to pillar
- (new P2) "Agentic engineering lifecycle: brainstorm → plan → implement → review → compound" (definition cluster)
- (new P2) "Agentic engineering vs prompt engineering vs vibe coding" (disambiguation cluster)
- (new P3) Case study: "How I shipped 420+ PRs solo using agentic engineering"

### Pillar C -- Claude Code Plugin / Marketplace (new, P1)

URL (proposed): `/blog/claude-code-plugin-soleur/` or `/blog/the-claude-code-plugin-for-running-a-company/`

Clusters:

- (live) `/getting-started/` -- product page, link to pillar
- (new P2) "Best Claude Code plugins for solo founders -- 2026" (listicle, frames Soleur as the orchestration layer)
- (new P2) "How Soleur extends Claude Code into a full AI organization"
- (new P2) "Soleur vs the official Claude Code plugin marketplace"
- (new P3) "Build your first Claude Code plugin for your own business"

Cross-pillar: each pillar links once to one of the others (Pillar A -> Pillar B at the agentic-engineering definition; Pillar B -> Pillar C at the install path; Pillar C -> Pillar A at the "what you actually get" section).

## Searchable vs Shareable Tagging

Brand-guide guidance: a content plan that is 100% searchable is missing the social distribution lane; flag if so.

This plan is intentionally mixed:

- Searchable: ~70% of pieces (pillars, comparison, definition, departmental long-tails)
- Shareable: ~30% of pieces (opinion-led pieces like "Can a solo founder build a billion-dollar company?", "The 70% problem", case-study narratives, "Soleur was built using Soleur")

Each item below is tagged `[S]` searchable or `[Sh]` shareable (some are both `[S/Sh]`).

---

## P1 -- Ship This Week

These six items combine the highest-leverage audit fixes (where shipping unblocks scoring on every other piece) with the two new pillar-defining posts. Total estimated effort: 4-6 working days for one person.

### P1.1 -- Inject FAQPage JSON-LD on six FAQ-bearing pages [S]

| Field | Value |
|-------|-------|
| Audit source | AEO audit Gap 1, P1.1 |
| Action | Add FAQPage JSON-LD using existing Q&A copy verbatim. Site-template change in `_includes/base.njk` (or per-page front-matter) |
| Pages | Home (6 Q&A), Agents (5), Vision (4), Getting Started (7), Pricing (5), Skills (4) |
| Target keyword | All FAQ questions become AEO-citable (~31 questions) |
| Search intent | Informational (question-shaped) |
| Content type | Schema, not new content |
| Outline | n/a -- structural |
| Expected impact | Moves SAP Structure 26->32, Total 62->68. Highest single move available. Likely Google rich results within 2-3 weeks. |
| Score | Customer impact 4 / CMF 5 / Search 5 / Resource cost 5 = **19** |

### P1.2 -- Publish About / Founder page with Person schema [S/Sh]

| Field | Value |
|-------|-------|
| Audit source | AEO audit Gap 3 (flagged for 6+ audits), Content audit page 2 |
| Action | Either upgrade existing `/about/` to a proper Founder page, or add `/founder/`. Include: mission, founder bio (Jean Deruelle), Jikigai legal-entity disclosure, "15+ years building distributed systems" credential as a structured stat block, contact paths. Add Person schema with `@id: "https://soleur.ai/about/#jean-deruelle"`, cross-link from Organization.founder and BlogPosting.author. |
| Target keyword | `Jean Deruelle Soleur`, `Soleur founder`, `who founded Soleur` |
| Search intent | Navigational + informational (E-E-A-T) |
| Content type | Page upgrade + schema |
| Outline | Hero -- Why Soleur exists. Body -- Founder bio (15+ years distributed systems / dev tools, prior projects, why CaaS). Section -- Jikigai (legal entity) and how Soleur ships. Section -- How to reach me. FAQ block (with FAQPage schema): "Who built Soleur?", "What is Jikigai?", "Why a solo founder?". |
| Expected impact | Closes the longest-running AEO gap. Unblocks E-E-A-T scoring across the site. Required precursor for SEO audit P2 (cross-link Person entity in JSON-LD). |
| Score | Customer impact 4 / CMF 5 / Search 3 / Resource cost 4 = **16** |

### P1.3 -- Audit/inject meta descriptions and unify titles [S]

| Field | Value |
|-------|-------|
| Audit source | Content audit P1.1, P1.5 |
| Action | (a) Verify each page's `<meta name="description">` rendered HTML against the suggested copy in the content audit (homepage, pricing, agents, getting-started, pillar, about, skills, blog index, vision, community). The SEO audit confirms descriptions ARE in HTML -- this is a copy-quality audit, not a presence audit. (b) Audit `{{ title }} - Soleur` template pattern; remove brand-name duplication from frontmatter `title:` fields on /about/, /getting-started/, /skills/, /community/, /changelog/, /blog/, /vision/. (c) On homepage, demote 5 of 6 H1s to H2; keep "Stop hiring. Start delegating." as the sole H1. |
| Target keyword | All target keywords reach SERP snippets |
| Search intent | Mixed |
| Content type | Edit pass across ~10 pages |
| Outline | n/a -- structural |
| Expected impact | Recovers wasted SERP characters across the entire site. Single-H1 fix concentrates topical signal on lead keyword. |
| Score | Customer impact 5 / CMF 5 / Search 5 / Resource cost 5 = **20** |

### P1.4 -- Wire pillar/cluster internal links + close citation gaps [S]

| Field | Value |
|-------|-------|
| Audit source | Content audit P1.4, P1.7; AEO audit Gap 2 + Gap 7 |
| Action | (a) Add "Read the definitive guide" link from `/agents/`, `/getting-started/`, homepage hero secondary, and each case study to `/blog/ai-agents-for-solo-founders/`. (b) From the pillar, link out to top 3 case studies and `/agents/` as siblings. (c) Convert the 5 named practitioners on /agents/ (Heinemeier Hansson, Evans, Feathers, Farley, Karpathy) to inline citations with linked source works. (d) Replace "production-grade code" / "catches what humans miss" on Home with cited or methodology-linked claims; link the "70% of running a company" claim on Home to the Pricing page methodology. (e) Add inline source link to the Anthropic-CEO 70-80% probability claim on /vision/. |
| Target keyword | `AI agents for solo founders` (consolidates topical authority on the pillar) |
| Search intent | Mixed |
| Content type | Edit pass |
| Outline | n/a -- structural |
| Expected impact | Doubles AI-engine citation probability for cited claims (per AEO playbook). Moves SAP Authority 24->28 and concentrates pillar ranking signal. |
| Score | Customer impact 4 / CMF 5 / Search 5 / Resource cost 5 = **19** |

### P1.5 -- Pillar B: "What is Agentic Engineering? The 2026 Practitioner's Guide" [S/Sh]

| Field | Value |
|-------|-------|
| Audit source | New (keyword research + competitor gap) |
| Action | New pillar post |
| Target keyword | `agentic engineering` (primary), `agentic engineering definition`, `what is agentic engineering` |
| Secondary keywords | `agentic workflows`, `agentic engineering vs vibe coding`, `agentic engineering lifecycle` |
| Search intent | Informational (definitive-guide intent) |
| Content type | Pillar blog post (~3,500-5,000 words), Cormorant H1, technical register |
| Outline | (1) Definition -- "Agentic engineering is the practice of orchestrating multiple AI agents with shared memory, defined roles, and human-in-the-loop review across the full software and business lifecycle." Quotable, AI-citable, linked. (2) Why it matters in 2026 -- the 30%/70% framing, Maven/Deloitte/CIO citations. (3) The lifecycle -- brainstorm → plan → implement → review → compound. (4) Agentic engineering vs prompt engineering vs vibe coding (link existing post). (5) The compounding effect -- knowledge compounding (link existing post). (6) Soleur as practitioner -- 60+ agents, 60+ skills, departmental coverage. (7) FAQ (with FAQPage schema): "What is agentic engineering?", "How is agentic engineering different from prompt engineering?", "Who coined the term?", "What tools enable agentic engineering?". |
| Expected impact | Owns the term Soleur already uses internally. SERP for `agentic engineering` is contestable -- LangChain, Deloitte, CIO all rank, but a practitioner piece with original methodology and citation-backed claims is differentiated. Estimated 6-12 month organic ramp; immediate AEO citation potential. |
| Score | Customer impact 4 / CMF 5 / Search 4 / Resource cost 3 = **16** |

### P1.6 -- Pillar C: "Soleur: The Claude Code Plugin That Runs Your Whole Company" [S/Sh]

| Field | Value |
|-------|-------|
| Audit source | New (keyword research + competitor gap) |
| Action | New pillar post + companion landing modifications |
| Target keyword | `Claude Code plugin` (primary in body + meta), `Claude Code plugin marketplace`, `Soleur Claude Code` |
| Secondary keywords | `best Claude Code plugins`, `Claude Code plugin for solo founders` |
| Search intent | Navigational + commercial |
| Content type | Pillar blog post (~2,500-3,500 words), Cormorant H1 (uses platform framing), body + meta use Claude Code plugin terminology |
| Outline | (1) H1: "Soleur: An AI Organization, Delivered as a Claude Code Plugin" (platform first per brand guide; "plugin" permitted per brand-guide exception in technical/install context). (2) The marketplace problem -- 800+ plugins solving narrow tasks; Soleur solves a category. (3) What you get -- 60+ agents across 8 departments, 60+ skills, shared knowledge base. (4) Two commands to install -- with code block, "30 seconds" claim. (5) How it differs from Cursor / Devin / raw Claude Code -- comparison table. (6) The open-source path (Apache 2.0). (7) FAQ (FAQPage schema): "What is the Soleur Claude Code plugin?", "How do I install it?", "Is it free?", "How is it different from other Claude Code plugins?", "Does it work without Claude Code?". |
| Expected impact | Captures the entire `Claude Code plugin` search lane Soleur is currently invisible in. High commercial intent -- marketplace browsers are pre-qualified. Drives plugin-marketplace cross-references and listicle inclusion (P3 outreach). |
| Score | Customer impact 5 / CMF 5 / Search 4 / Resource cost 3 = **17** |

---

## P2 -- Ship This Month

These build the cluster set around the new and existing pillars, address the second-tier audit findings, and close the searchable/shareable balance.

### P2.7 -- Add Organization schema (footer) + fix entity graph [S]

| Field | Value |
|-------|-------|
| Audit source | AEO audit P2 #5; SEO audit P2 #1 |
| Action | Site-wide footer Organization schema with `name: "Soleur"`, `legalName: "Jikigai"`, `founder: { @id: "https://soleur.ai/about/#jean-deruelle" }`, `sameAs: [discord, github, x, linkedin, bluesky]`. Add Person `@id` on /about/ and back-reference from BlogPosting.author across all 19 posts. |
| Target keyword | Brand entity disambiguation |
| Intent | Navigational |
| Outline | n/a -- schema |
| Expected impact | Resolves entity graph for AI engines. Closes most of the AEO Entity-clarity gap. |
| Score | 4/5/3/4 = **16** (P1-borderline, slot in early P2) |

### P2.8 -- Pricing page upgrade: Product/Offer schema + pain-point hero [S]

| Field | Value |
|-------|-------|
| Audit source | Content audit P2.12; AEO audit P1.1 |
| Action | Add Product schema with `offers` array ($49 floor, $499 ceiling, `priceValidUntil`). Add "Stop hiring. Start delegating." pain-point hero above the table. Promote $95K/mo replacement to a one-line stat block. Link the 70% claim to its citation. |
| Target keyword | `AI organization pricing`, `Soleur pricing`, `Company-as-a-Service pricing` |
| Intent | Commercial / transactional |
| Outline | Hero (pain-point) > Stat block ($95K/mo replacement, cited) > Pricing table (existing) > FAQ (existing, with FAQPage schema from P1.1). |
| Expected impact | Improves transactional conversion + AEO pricing-query coverage. |
| Score | 5/5/3/4 = **17** |

### P2.9 -- "Agentic engineering vs vibe coding vs prompt engineering" [S]

| Field | Value |
|-------|-------|
| Audit source | New (Pillar B cluster) |
| Action | Disambiguation post |
| Target keyword | `agentic engineering vs vibe coding`, `prompt engineering vs agentic engineering` |
| Intent | Informational |
| Content type | ~2,000 word cluster post, links to Pillar B and existing Vibe Coding post |
| Outline | Definition table (3 columns). When to use each. The lifecycle differences (one-shot prompts vs orchestrated multi-agent flows vs autocomplete-driven). Why "vibe coding" peaks at MVP; agentic engineering scales to product. FAQ. |
| Expected impact | Long-tail capture; reinforces Pillar B; addresses real reader confusion. |
| Score | 4/5/3/4 = **16** |

### P2.10 -- Departmental long-tail series: "AI agents for [department] as a solo founder" [S]

| Field | Value |
|-------|-------|
| Audit source | New (Pillar A cluster, departmental long-tails) |
| Action | Six pieces (one per non-engineering department): marketing, legal, finance, operations, sales, product, support |
| Target keyword | `AI agents for marketing solo founder`, etc. |
| Intent | Commercial + informational |
| Content type | ~1,200-1,500 words each. Clear template: Why this department is hard solo > How AI agents handle the recurring work > What still needs human judgment > Where Soleur's [Department] agents fit. |
| Outline | Per piece: pain-point hook > 3-5 specific recurring tasks > the agent set that handles them (link to /agents/ department block) > "What you don't delegate" (trust scaffolding) > install CTA. |
| Expected impact | Captures 6 department-vertical long-tails. Each links to Pillar A. Gives sales conversations cited departmental ROI proof. |
| Score | 4/4/4/4 = **16** |

### P2.11 -- "The 2026 AI tool stack for solo founders -- with the orchestrator on top" [S/Sh] (listicle counter-position) |

| Field | Value |
|-------|-------|
| Audit source | Competitor gap analysis Section 3 |
| Action | Self-published listicle that frames Soleur as the orchestration layer above the stack |
| Target keyword | `AI tools for solo founders`, `solo founder AI tools`, `AI tools for solopreneurs` |
| Intent | Commercial |
| Content type | ~3,000-word listicle |
| Outline | Intro -- the stack problem (everyone lists the same 12 tools; nobody coordinates them). Tier 1 -- Foundation models (Claude, GPT, etc.). Tier 2 -- Vertical tools (Notion, Stripe, etc.). Tier 3 -- The orchestration layer (Soleur as Company-as-a-Service). Show how each tier composes. Practical sections: $0/mo stack, $50/mo stack, $500/mo stack. FAQ (FAQPage schema). |
| Expected impact | Captures listicle SERP without sounding self-promotional. Demonstrates Soleur's architectural role. Shareable on LinkedIn/X. |
| Score | 4/4/4/3 = **15** |

### P2.12 -- "Best Claude Code plugins for solo founders -- 2026" [S/Sh]

| Field | Value |
|-------|-------|
| Audit source | New (Pillar C cluster + commercial keyword) |
| Action | Self-published Claude Code plugin listicle |
| Target keyword | `best Claude Code plugins`, `Claude Code plugins for solo founders` |
| Intent | Commercial |
| Content type | ~2,500 words. Honest reviews of 8-12 plugins with criteria (token efficiency, scope, maintenance cadence, license). Include Soleur. |
| Outline | Selection criteria > Plugin reviews (one paragraph each) > Composing them with Soleur > Install instructions for the recommended stack > FAQ. |
| Expected impact | Captures `best Claude Code plugins` lane. Drives plugin-marketplace cross-pollination. Shareable in dev communities. |
| Score | 4/4/4/3 = **15** |

### P2.13 -- "Can a solo founder build a billion-dollar company?" [Sh]

| Field | Value |
|-------|-------|
| Audit source | Brand thesis -- shareable counterweight to searchable plan |
| Action | Opinion-led narrative post that anchors Soleur's thesis |
| Target keyword | `one-person billion-dollar company`, `solo founder billion dollars` |
| Intent | Informational |
| Content type | ~2,000-3,000 word essay. Founder voice. |
| Outline | The Sam Altman quote / Amodei probability set-up (cited). The four reasons it's now possible (cost, agents, knowledge compounding, market). The four reasons it usually fails (taste, energy, capital, distribution). What Soleur does about each. Soleur's own progress (case study). |
| Expected impact | Hero shareable piece for X / LinkedIn / HN. Drives brand search. Anchors the thesis for press. |
| Score | 4/5/2/3 = **14** |

### P2.14 -- Citation-monitoring loop (process, not content) [Sh, internal]

| Field | Value |
|-------|-------|
| Audit source | AEO audit Gap 5 + P2 #8 |
| Action | Document a weekly query set in `knowledge-base/marketing/seo/citation-monitoring.md`: "AI agents for solo founders", "Claude Code plugin marketplace", "Company as a Service platform", "Soleur", "Soleur vs Cursor", "What is agentic engineering". Run in ChatGPT, Perplexity, Claude weekly. Capture screenshots and citations. Track week-over-week. |
| Expected impact | Makes Presence measurable. Without this, P3 outreach has no feedback loop. |
| Score | 5/5/N-A/4 = **14** (process, not search) |

### P2.15 -- Recategorize the 5 "Uncategorized" skills [S]

| Field | Value |
|-------|-------|
| Audit source | AEO audit P2 #9 |
| Action | Categorize before next AI-engine crawl |
| Expected impact | Removes taxonomy-debt signal leaking to crawlers. |
| Score | 3/5/2/5 = **15** |

### P2.16 -- Cluster siblings on case studies [S]

| Field | Value |
|-------|-------|
| Audit source | Content audit P3 #17 (promoted to P2 because it pairs with P1.4) |
| Action | Each case study links to (a) the pillar `/blog/ai-agents-for-solo-founders/`, (b) one sibling case study, (c) the relevant agent department |
| Expected impact | Reinforces pillar/cluster topology |
| Score | 3/5/3/5 = **16** |

---

## P3 -- Next Quarter

Investments with longer payoff horizons or that depend on P1/P2 shipping first.

### P3.17 -- Third-party Presence outreach [Sh]

Submit Soleur to AI-tool directories (There's An AI For That, AI Agents Directory, Futurepedia, Product Hunt at cloud-launch). Pitch inclusion in `best AI tools for solo founders` listicles on dev.to, IndieHackers, HN-friendly newsletters. Pitch a guest piece to LangChain or The New Stack on agentic engineering practitioner experience. Closes AEO Gap 4. Resource cost is high (sustained outreach), search potential is medium (presence, not direct SEO). Score 4/3/3/2 = **12**.

### P3.18 -- Glossary site asset (`/glossary/`) [S]

DefinedTerm schema entries for "Company-as-a-Service", "agentic engineering", "compound engineering lifecycle", "knowledge compounding", "human-in-the-loop", "AI organization." Each term gets a 1-2 sentence canonical definition (AI-citable) and links to the pillar/cluster pieces that expand it. AEO P2 #7. Score 4/5/3/3 = **15** (timing, not score, defers it -- depends on Pillars A/B/C definitions stabilizing).

### P3.19 -- BlogPosting schema audit on all 19 blog posts [S]

Verify `author`, `datePublished`, `dateModified`, `headline`, `image`, `mainEntityOfPage`. Out of growth-skill scope (seo-aeo-analyst territory) but called out so it doesn't drop. Score 3/5/3/4 = **15**.

### P3.20 -- Architecture diagrams + visual content for long-form posts [S/Sh]

Per SEO audit P4 #5. Add one diagram per pillar (Pillar A: 8-department architecture; Pillar B: agentic engineering lifecycle; Pillar C: Claude Code plugin install flow). Multi-modal AI engines + image search. Score 3/4/3/2 = **12**.

### P3.21 -- "Soleur was built using Soleur" deep dive [Sh]

The strongest dogfood narrative the brand can produce. Brand-guide example phrase already exists ("Designed, built, and shipped by Soleur -- using Soleur"). One long-form essay + companion video walkthrough. Hero piece for LinkedIn / HN. Score 4/5/2/2 = **13**.

### P3.22 -- "How Soleur extends Claude Code into a full AI organization" [S]

Pillar C cluster expansion. Architectural how-it-works deep dive. Resource cost is medium (real engineering content). Score 3/5/3/3 = **14** (Q-end target).

### P3.23 -- Annual year-anchored update of the pillar (`(2026)` -> `(2027)`) [S]

Per content audit P3 #16. Updates the pillar's title and any year-bound claims at the start of each calendar year. Score 4/5/4/5 = **18** but annual cadence places it in Q1 next year.

### P3.24 -- "Press" / "as cited in" strip on the home page [Sh]

Per AEO audit P3 #13. Triggers once third-party Presence (P3.17) produces 3+ citations. Self-reinforcing Presence signal.

### P3.25 -- `dateModified` on static pages + base/relative-link cleanup [S, technical]

SEO audit P3 #2 and #3. One-line Nunjucks change for `dateModified`; bigger cleanup for base/relative links. Both low-impact, low-cost; bundle into one technical pass.

### P3.26 -- llms.txt + AI-engine summary surfaces [S]

Out of growth scope (SEO already gives this 5/5) but worth re-validating after content launches: each new pillar should be referenced from `/llms.txt`.

---

## Cross-Plan Risk Notes

1. **Brand-guide voice compliance.** Two new pillars (B agentic engineering, C Claude Code plugin) involve technical-register copy. Pillar C in particular needs careful headline construction -- "plugin" is forbidden in headlines except in CLI/install/legal contexts. The proposed H1 ("Soleur: An AI Organization, Delivered as a Claude Code Plugin") threads this needle by leading with the platform framing. Run all new headlines past the brand-guide Don'ts list before publishing.

2. **Soft-floor compliance.** All new pieces must say "60+ agents" / "60+ skills" in static prose. Hard counts are reserved for filesystem-rendered surfaces (`{{ stats.agents }}`).

3. **Trust scaffolding.** Brand guide flags trust signals as the #1 missing element across all framings. Every new piece must include at least one trust phrase ("human-in-the-loop", "your expertise, amplified", "starting point, not final answer") in the first 200 words.

4. **Departmental long-tail series cadence.** Six pieces (P2.10) is a real volume. Avoid a content-mill feel by spacing across the cycle (one per week) and by rotating real Soleur agent demos through them (not just abstract pitches).

5. **Listicle authenticity.** P2.11 (AI tool stack listicle) and P2.12 (Claude Code plugin listicle) will fail if they read self-promotional. The frame is honest comparison with Soleur as one option (P2.12) or as the orchestration layer above (P2.11). Reviewer must be willing to recommend competitors where they win.

6. **Citation discipline.** AEO Gap 2 -- single-citation problem -- is the easiest gap to re-introduce. Every new piece must have minimum 3 cited external claims with linked anchors. Pricing page is the on-site model.

## Tracking and Re-evaluation

- **Re-audit cadence:** AEO and content audits at 4 weeks (post P1 ship). SEO audit quarterly.
- **Exit criteria for P1:** SAP score >=75 (B+); Structure >=32/40; FAQPage schema verified across all 6 pages; About/Founder page live with Person schema; pillar internal-link graph complete; two new pillars (B, C) published with FAQ schema and 3+ citations each.
- **P2 readiness signal:** Citation-monitoring loop captures at least one third-party AI-engine citation of Soleur within 8 weeks of P1 ship.
- **P3 readiness signal:** Pillars A/B/C each rank top-20 for primary target keyword within 12 weeks.

## Notes on Sources Used

Keyword research drew on live web search of: claude code plugins marketplace 2026 (BrightCoding, claudemarketplaces.com, Build with Claude, awesome-claude-plugins); agentic engineering 2026 (LangChain, Deloitte, CIO, Maven, The New Stack, Akraya, Stack AI); AI tools for solo founders 2026 (Rocket.new, Siift, EntrepreneurLoop, AI Journal, OPC Community); AI agents automate company departments solopreneur (Maketocreate, Just Think AI, AAIA, Modern Outreach, Klover.ai). Volume and difficulty figures are directional estimates from SERP composition, not from a paid keyword tool. Re-validate with Ahrefs / Semrush before committing to ranking targets per piece.
