# Soleur.ai Content Audit Report

**Date:** 2026-03-23
**Scope:** 7 site pages + 10 blog posts (full site coverage excluding legal documents, which are compliance content not subject to keyword optimization)
**Brand Guide:** `knowledge-base/marketing/brand-guide.md` (last updated 2026-02-21, last reviewed 2026-03-02)
**Method:** Live site fetched via WebFetch against `https://soleur.ai`. All content reflects the published state as of 2026-03-23.
**Previous Audit:** `knowledge-base/marketing/audits/soleur-ai/2026-03-17-content-audit.md`

---

## 1. Target Keyword Universe

Keywords derived from brand positioning, competitor landscape, and search intent analysis. Updated from 2026-03-17 audit to reflect new comparison pages and evolving search trends.

| Keyword / Phrase | Search Intent | Relevance | Status on Site |
|---|---|---|---|
| company-as-a-service | Informational | HIGH | Strong coverage -- homepage, vision, pillar blog post, all comparisons |
| CaaS platform | Informational / Navigational | HIGH | Used in pillar article. Abbreviation indexed. |
| AI agents for solo founders | Commercial | HIGH | Present in meta descriptions and body copy across multiple pages |
| AI agents for business | Commercial | HIGH | Used as agents page meta description keyword |
| one person billion dollar company | Informational | HIGH | Concept discussed extensively; exact phrase missing from headings |
| Claude Code plugin | Navigational / Commercial | HIGH | Present in meta descriptions (brand guide violation) |
| agentic engineering | Informational | HIGH | Used on skills page and plateau blog post. Definition still missing on agents page. |
| compound engineering | Informational | MEDIUM | Core concept in plateau article. Growing search interest. |
| compound knowledge base | Informational | MEDIUM | Differentiator keyword. Used in comparisons and plateau post. |
| AI business operations platform | Commercial | MEDIUM | Concept described; exact phrase absent |
| open source AI agent platform | Commercial | MEDIUM | Homepage still does not mention "open source" prominently |
| Soleur vs Cursor | Commercial | HIGH | Dedicated blog post published 2026-03-19 |
| Soleur vs Cowork | Commercial / Navigational | HIGH | Dedicated blog post published 2026-03-16 |
| Soleur vs Notion | Commercial | MEDIUM | Dedicated blog post published 2026-03-17 |
| solopreneur AI tools 2026 | Commercial | HIGH | "Solopreneur" still absent from homepage and most pages |
| AI legal document generator | Commercial | MEDIUM | Case study addresses this. No dedicated landing page. |
| AI competitive intelligence | Commercial | MEDIUM | Case study addresses this. |
| business validation AI | Commercial | MEDIUM | Case study addresses this. |
| AI brand guide generator | Commercial | LOW-MEDIUM | Case study addresses this. Niche query. |
| vibe coding vs agentic engineering | Informational | MEDIUM | Plateau article covers both concepts. Exact phrase absent from headings. |
| AI workflow automation | Commercial | MEDIUM | Skills page describes concept; exact keyword absent |
| how to run a company with AI | Informational | HIGH | Not directly targeted on any page |

---

## 2. Per-Page Analysis

### 2.1 Homepage

**URL:** `https://soleur.ai/`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Soleur - The Company-as-a-Service Platform" |
| **Meta description** | "The company-as-a-service platform. A Claude Code plugin that gives solo founders a full AI organization across every business department." |
| **H1** | "Build a Billion-Dollar Company. Alone." |
| **Detected target keywords** | company-as-a-service, solo founders, AI agents, Claude Code plugin, AI organization, billion-dollar company |
| **Keyword alignment** | STRONG. Meta description contains primary keyword and audience. H1 captures aspirational search intent. Body text hits key terms naturally. |
| **Search intent match** | Mixed navigational/commercial. Correctly answers "what is this product and who is it for." |
| **Readability** | EXCELLENT. Short, declarative sentences. Punchy copy aligned with brand voice. Generous whitespace. Stats presented as monumental numbers. |
| **FAQ section** | Present. 6 questions covering what/how/who/pricing/comparison. Well-structured. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | Meta description says "Claude Code plugin" | Brand guide (line 66): "Do not call it a 'plugin' or 'tool' in public-facing content -- it is a platform." The meta description is the single highest-impression text on the site. This was flagged in the 2026-03-17 audit as C5 and remains unfixed. |
| IMPROVEMENT | H1 contains zero target keywords | "Build a Billion-Dollar Company. Alone." is powerful brand copy but contains no indexable terms. Search engines weight H1 heavily. The primary keyword "company-as-a-service" appears only in meta description and subheadline, not H1. |
| IMPROVEMENT | "Open source" absent from homepage | Soleur is Apache-2.0 licensed -- a key differentiator vs. Cowork ($20/mo), Notion ($10/1000 credits), and Cursor ($20-200/mo). The phrase "open source" does not appear on the homepage. Searchers query "open source AI agent platform." |
| IMPROVEMENT | "Solopreneur" absent | The word "solopreneur" does not appear despite being a high-volume search term. "Solo founders" captures the brand voice but "solopreneur" captures a broader audience in SERP. |
| IMPROVEMENT | Agent count inconsistency | Homepage shows "63 AI Agents" but brand guide (line 23) says "61 agents, 59 skills." The discrepancy suggests the brand guide is stale, but it creates a trust signal mismatch if both are visible to searchers. |
| IMPROVEMENT | "The Soleur Thesis" block quote is not structured for extraction | The thesis statement is powerful content for AI citation. Currently rendered as a blockquote with attribution. Adding an id anchor and clearer semantic markup would improve citability. |

---

### 2.2 Getting Started

**URL:** `https://soleur.ai/pages/getting-started.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Getting Started with Soleur - Soleur" |
| **Meta description** | "Install the Soleur Claude Code plugin and start running your company-as-a-service -- AI agents for engineering, marketing, legal, finance, and more." |
| **H1** | "Getting Started with Soleur" |
| **Detected target keywords** | company-as-a-service, Claude Code plugin, AI agents, AI organization |
| **Keyword alignment** | GOOD. Meta description is keyword-rich. Body covers key terms naturally through workflow explanation. |
| **Search intent match** | Transactional (how to install/use). Correct match. |
| **Readability** | GOOD. Clear step-by-step structure with code blocks. Workflow stages clearly enumerated. |
| **FAQ section** | Present. 5 questions covering requirements, platform support, pricing, commands, and existing projects. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | Meta description says "Claude Code plugin" | Same brand guide violation as homepage. This is the primary transactional landing page -- the page most likely to receive search traffic from "how to install Soleur" queries. Flagged in 2026-03-17 audit as C5; still unfixed. |
| IMPROVEMENT | No time-to-value claim in meta description | The page demonstrates one-command installation but the meta description does not communicate speed. Adding "in one command" or "in under 5 minutes" would improve CTR. |
| IMPROVEMENT | "Install the Claude Code plugin" in body subtitle | Brand guide violation in visible body text. Should reference "platform" not "plugin." |
| IMPROVEMENT | Missing keyword: "free" or "open source" | The FAQ mentions Soleur is free and open source, but neither term appears in the meta description or opening paragraph where search engines weight them most. |

---

### 2.3 Agents

**URL:** `https://soleur.ai/pages/agents.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Soleur AI Agents - Soleur" |
| **Meta description** | "AI agents for business -- engineering, marketing, legal, finance, operations, product, sales, and support." |
| **H1** | "Soleur AI Agents" |
| **Detected target keywords** | AI agents, AI agents for business, company-as-a-service, agentic engineering |
| **Keyword alignment** | STRONG. Meta description hits "AI agents for business" directly. H1 includes brand name and primary term. |
| **Search intent match** | Commercial investigation. Someone evaluating AI agent platforms. Correct match. |
| **Readability** | GOOD. Intro paragraph explains agent philosophy clearly. Department sections with counts are scannable. |
| **FAQ section** | Present. 4 questions on what agents are, customization, activation, and coverage. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | "Agentic engineering" used without definition | The term appears in the intro but is not defined in a standalone, quotable sentence. Adding a one-sentence definition near first usage improves AI-extractability for informational queries. |
| IMPROVEMENT | Missing "open source" differentiator | The agents page does not mention that agents are open source and inspectable. This differentiates from Cowork (closed) and is a search query. |
| IMPROVEMENT | Department descriptions are marketing-light | Descriptions like "Code review, architecture, security, quality testing" are functional but lack the brand voice energy. Compare to homepage's "You decide. Agents execute. Knowledge compounds." |

---

### 2.4 Skills

**URL:** `https://soleur.ai/pages/skills.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Soleur Skills - Soleur" |
| **Meta description** | "Multi-step workflow skills for the Soleur platform -- from feature development and code review to content writing, deployment, and agentic engineering." |
| **H1** | "Agentic Engineering Skills" |
| **Detected target keywords** | agentic engineering, workflow skills, code review, deployment |
| **Keyword alignment** | MODERATE. Targets "agentic engineering" well but misses commercial keywords like "AI workflow automation" or "AI business workflows." |
| **Search intent match** | Informational / navigational. Correct for product documentation. |
| **Readability** | GOOD. Clear compound engineering lifecycle explanation. Skill categories well-organized. |
| **FAQ section** | Present. 4 questions on skill definition, invocation, lifecycle, and count. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | H1 "Agentic Engineering Skills" lacks brand identifier | The title tag says "Soleur Skills" but the H1 says "Agentic Engineering Skills." The H1 should include "Soleur" for brand association in search results. |
| IMPROVEMENT | Missing keyword: "AI workflow automation" | The concept of multi-step automated workflows is described extensively but the commercially-searched phrase "AI workflow automation" is absent. |
| IMPROVEMENT | Title tag vs. H1 mismatch | Title tag = "Soleur Skills - Soleur"; H1 = "Agentic Engineering Skills." Search engines flag title/H1 mismatch as a mixed signal. Align them. |

---

### 2.5 Vision

**URL:** `https://soleur.ai/pages/vision.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Vision - Soleur" |
| **Meta description** | "Where Soleur is headed. The Company-as-a-Service platform that gives solo founders the leverage of a full organization." |
| **H1** | "Vision" |
| **Detected target keywords** | company-as-a-service, solo founder, model-agnostic, AI organization |
| **Keyword alignment** | WEAK. Meta description is acceptable. H1 is a single generic word with zero keyword value. |
| **Search intent match** | Navigational (existing users seeking roadmap). Does not capture informational traffic. |
| **Readability** | MODERATE. Some sections are dense. "AI Agent Swarms" and "Recursive Dogfooding" are jargon-heavy. |
| **FAQ section** | Present. 4 questions covering thesis, CaaS definition, model-agnostic status, and roadmap. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | H1 is "Vision" -- zero keyword value | A one-word H1 provides no search signal. This is the most content-rich page on the site with substantial keyword-bearing body copy, but the H1 wastes the primary heading signal. Flagged in 2026-03-17 audit as C4; still unfixed. |
| IMPROVEMENT | "Billion-Dollar Solopreneur" vs. "solo founders" inconsistency | The vision page uses "Billion-Dollar Solopreneur" as a subsection title while all other pages use "solo founders." Inconsistent keyword targeting. |
| IMPROVEMENT | "Synthetic labor" not in brand vocabulary | The phrase "synthetic labor" appears in the vision page but is not in the brand guide. It could alienate the target audience by framing AI agents as a labor replacement rather than an organization the founder commands. |
| IMPROVEMENT | "CEO Dashboard" referenced but not explained | The vision page mentions a "CEO Dashboard" under the Model-Agnostic Architecture section without defining it or linking to it. This creates unresolved references that reduce page authority. |
| IMPROVEMENT | Master Plan section lacks specificity for milestones 2 and 3 | Milestone 1 (software companies) is concrete. Milestones 2 (hardware) and 3 (multiplanetary) are vague. Vague claims reduce authority signals for AI extraction. |

---

### 2.6 Community

**URL:** `https://soleur.ai/pages/community.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Community - Soleur" |
| **Meta description** | "Join the Soleur community. Connect on Discord, contribute on GitHub, get help, and learn about our community guidelines." |
| **H1** | "Community" |
| **Detected target keywords** | Soleur (brand name only) |
| **Keyword alignment** | WEAK. No target keywords in H1, meta description, or body beyond the brand name. |
| **Search intent match** | Navigational. Correct for existing users. Not designed to capture search traffic. |
| **Readability** | GOOD. Clear card-based layout. Five connection channels with concise descriptions. |
| **FAQ section** | Present. 4 questions on contributing, help channels, CLA requirements, and community existence. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | No keyword context in body text | The community page is pure navigation. Adding a one-paragraph intro with "the Soleur open-source community for solo founders building with AI agents" would add keyword context without changing the page purpose. |

---

### 2.7 Blog Index

**URL:** `https://soleur.ai/blog/`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Blog - Soleur" |
| **Meta description** | "Insights on agentic engineering, company-as-a-service, and building at scale with AI teams." |
| **H1** | "Blog" |
| **Keyword alignment** | MODERATE. Meta description hits key terms. H1 is generic. |
| **Readability** | N/A -- listing page with article cards. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | H1 is "Blog" -- no keyword value | Should be "Soleur Blog" at minimum. Meta description carries the keyword weight but H1 is wasted. |

---

## 3. Blog Post Analysis

### 3.1 "What Is Company-as-a-Service?" (Pillar)

**Published:** 2026-03-05
**URL:** `https://soleur.ai/blog/what-is-company-as-a-service/`
**Estimated word count:** 3,200-3,400

| Attribute | Assessment |
|---|---|
| **Meta description** | "Company-as-a-Service is a new model where AI agents run every business department. Learn what CaaS means, how it works, and why it matters for solo founders." |
| **Keyword alignment** | EXCELLENT. Targets "company-as-a-service," "CaaS," "AI agents," "solo founders." Category-defining pillar content. |
| **Search intent** | Informational. Perfectly matches "what is company-as-a-service" query. |
| **Readability** | EXCELLENT. Clear H2/H3 hierarchy, comparison table (CaaS vs. SaaS vs. AIaaS vs. BPaaS), structured definitions. |
| **Authority signals** | STRONG. Cites Bureau of Labor Statistics, TechCrunch, CNBC, VentureBeat, Inc.com, Fortune. References Cursor $1B ARR, Lovable $200M ARR, Amodei and Altman predictions. |
| **FAQ section** | Present. 5 questions with JSON-LD schema. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Missing heading for "one person billion dollar company" | The article discusses this concept extensively but the exact high-volume phrase does not appear as a heading. Adding an H2 or H3 would capture this informational query. |
| IMPROVEMENT | Opening definition could be more concise for AI extraction | The first sentence is strong ("Company-as-a-Service (CaaS) is a new category of platform...") but runs long. A 1-2 sentence definition followed by expansion would be more extractable. |

---

### 3.2 "Why Most Agentic Engineering Tools Plateau"

**Published:** 2026-03-14
**URL:** `https://soleur.ai/blog/why-most-agentic-tools-plateau/`
**Estimated word count:** 2,400-2,600

| Attribute | Assessment |
|---|---|
| **Meta description** | "Most AI coding tools stop getting better after week two. The missing layer is compound knowledge -- a system that learns from every task and feeds those learnings back into its own rules, agents, and workflows." |
| **Keyword alignment** | STRONG. Targets "agentic engineering," "compound knowledge," "AI coding tools," "compound engineering." |
| **Search intent** | Informational. Matches "why AI coding tools plateau" and "compound engineering" queries. |
| **Readability** | EXCELLENT. Best-structured article on the site. Data tables with concrete reduction percentages (20-96%), comparison matrix, clear three-era framework. |
| **Authority signals** | STRONG. Cites Karpathy, references specific GitHub repos, names competitors with specifics. Original data (governance growth from 26 to 200+ rules). |
| **FAQ section** | Present. 3 questions. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Missing heading: "vibe coding vs agentic engineering" | The article explains both paradigms in detail and draws the contrast, but the exact comparison phrase does not appear as a heading. This is a growing search query. |
| IMPROVEMENT | Comparison matrix may be stale | New competitors (Polsia, Tanka) have entered the market since publication. Comparison tables that omit known alternatives reduce perceived authority. |

---

### 3.3 "Soleur vs. Cursor"

**Published:** 2026-03-19
**URL:** `https://soleur.ai/blog/soleur-vs-cursor/`
**Estimated word count:** ~2,100

| Attribute | Assessment |
|---|---|
| **Meta description** | "Cursor shipped Automations and a Marketplace in March 2026, becoming an agent platform. A direct comparison with Soleur's Company-as-a-Service platform for solo founders." |
| **Keyword alignment** | STRONG. Targets "Soleur vs Cursor," "AI coding tool," "agent platform," "solo founders." |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | GOOD. Clear section structure with "Where They Differ" subsections. |
| **Authority signals** | GOOD. References specific Cursor features (Automations, Marketplace) with timeline. |
| **FAQ section** | Present based on heading. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title missing "(2026)" | Comparison articles date rapidly. Including the year captures dated search queries ("Soleur vs Cursor 2026") and signals freshness to search engines. |
| IMPROVEMENT | Framing is conciliatory -- potentially too soft | The article says platforms "can coexist rather than directly compete." While honest, the commercial search intent behind "Soleur vs Cursor" expects a clear winner recommendation. The article should maintain honesty but provide a clearer recommendation for when each is the right choice. |

---

### 3.4 "Soleur vs. Anthropic Cowork"

**Published:** 2026-03-16
**URL:** `https://soleur.ai/blog/soleur-vs-anthropic-cowork/`
**Estimated word count:** ~2,200

| Attribute | Assessment |
|---|---|
| **Meta description** | "Soleur and Anthropic Cowork both deploy multi-domain AI agents. A direct comparison of knowledge architecture, workflow depth, cross-domain coherence, and pricing." |
| **Keyword alignment** | STRONG. Targets "Soleur vs Cowork," "AI agent platform," "solo founders." Includes Microsoft Copilot Cowork as bonus coverage. |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | EXCELLENT. Side-by-side table, clear sections, honest assessment of all three platforms. |
| **Authority signals** | STRONG. Cites TechCrunch, The Decoder, Claude pricing page. Specific feature comparison. |
| **FAQ section** | Present. 5 questions with JSON-LD schema. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title missing "(2026)" | Same as Cursor comparison. Dated queries are high-intent. |
| IMPROVEMENT | Title says "Anthropic Cowork" but many searchers will query "Claude Cowork" | Consider adding "Claude" as a secondary keyword in the meta description or body intro to capture both query variants. |

---

### 3.5 "Soleur vs. Notion Custom Agents"

**Published:** 2026-03-17
**URL:** `https://soleur.ai/blog/soleur-vs-notion-custom-agents/`
**Estimated word count:** ~2,200

| Attribute | Assessment |
|---|---|
| **Meta description** | "Notion Custom Agents automate recurring workspace tasks. Soleur runs a full AI organization with compounding knowledge. A direct comparison for solo founders." |
| **Keyword alignment** | GOOD. Targets "Soleur vs Notion," "Notion Custom Agents," "solo founders." |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | GOOD. Clear structure with side-by-side comparison and pricing breakdown. |
| **Authority signals** | GOOD. Specific pricing and feature details for Notion. |
| **FAQ section** | Present. 5 questions. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Notion pricing may be dated | The article references "Free beta through May 3, 2026" -- this date will pass in 6 weeks. Content needs a freshness update or evergreen phrasing. |
| IMPROVEMENT | Missing keyword: "Notion AI vs Soleur" | Many searchers will use "Notion AI" rather than "Notion Custom Agents" as the query. The meta description and title do not capture this variant. |

---

### 3.6 Case Studies (5 posts)

All five case studies follow a consistent structure: problem statement, AI approach, result, cost comparison, compound effect, FAQ. This is strong content architecture.

| Case Study | Meta Description Quality | Keyword Alignment | FAQ Quality |
|---|---|---|---|
| Brand Guide Creation | GOOD -- specific outcome and process | MODERATE -- "AI brand guide" present, "brand workshop" absent | Present, 3 questions |
| Business Validation | EXCELLENT -- includes "PIVOT verdict" (specific, compelling) | GOOD -- "business validation," "AI gates" | Present, 3 questions |
| Competitive Intelligence | GOOD -- "17 competitors," "battlecards" (concrete numbers) | MODERATE -- "competitive intelligence" present, "AI competitor analysis" absent | Not verified |
| Legal Document Generation | EXCELLENT -- "9 documents," "17,761 words," "dual-jurisdiction" (specificity) | GOOD -- "AI legal documents," "compliance suite" | Present, 3 questions |
| Operations Management | GOOD -- specific operational functions mentioned | MODERATE -- "operations," "expense tracking" present | Not verified |

**Shared issues across all case studies:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | No "Case Study" in titles | Titles are narrative ("How We Generated 9 Legal Documents...") which is engaging but misses the search query "AI agent case study." Adding "Case Study:" prefix or appending "[Case Study]" would capture this intent. |
| IMPROVEMENT | No internal cross-links between case studies | Each case study is isolated. Adding a "Related case studies" section or inline links between them would strengthen internal link architecture and keep readers on-site. |
| IMPROVEMENT | Cost comparison sections lack citations | Statements like "a startup strategy consultant charges $4,000-$16,000" are presented without source attribution. Adding citations to Clutch, Glassdoor, or industry reports would strengthen authority signals. |
| IMPROVEMENT | Case studies do not link back to the department pages they demonstrate | The brand guide case study should link to the agents page (marketing department). The legal case study should link to agents page (legal department). This pillar/cluster linking is absent. |

---

## 4. Cross-Site Issues

### 4.1 Brand Voice Compliance

| Issue | Severity | Pages Affected |
|---|---|---|
| "Plugin" used in meta descriptions | CRITICAL | Homepage, Getting Started |
| "Plugin" used in body text | IMPROVEMENT | Getting Started subtitle |
| "Synthetic labor" not in brand vocabulary | IMPROVEMENT | Vision page |
| "CEO Dashboard" undefined term | IMPROVEMENT | Vision page |
| "Soloentrepreneurs" (nonstandard) vs "solo founders" | IMPROVEMENT | Vision page |
| "AI Agent Swarms" -- jargon without context | IMPROVEMENT | Vision page |

The vision page is the primary source of brand voice violations. All other pages (homepage, agents, skills, blog posts) maintain strong brand voice alignment -- declarative, bold, forward-looking, no hedging.

### 4.2 Keyword Consistency

| Term | Homepage | Getting Started | Agents | Skills | Vision | Blog Posts |
|---|---|---|---|---|---|---|
| company-as-a-service | Yes | Yes | Yes | No | Yes | Yes (all) |
| AI agents | Yes | Yes | Yes | No | Yes | Yes (all) |
| solo founders | Yes | Yes | No | No | Yes | Yes (most) |
| open source | No | FAQ only | No | No | No | Some comparisons |
| solopreneur | No | No | No | No | Yes (once) | No |
| agentic engineering | No | No | Intro | Yes (H1) | No | Plateau post |
| compound knowledge | No | No | Intro | Intro | No | Plateau post, comparisons |
| free | FAQ only | FAQ only | No | No | No | Comparisons (pricing) |

**Gaps:** "Open source," "solopreneur," and "free" are underrepresented despite being strong differentiators. These terms appear only in FAQ sections or deep body copy, never in meta descriptions or headings where they carry the most SEO weight.

### 4.3 Internal Linking Assessment

| Link Pattern | Status |
|---|---|
| Homepage to all nav pages | Present |
| Blog posts to Getting Started | Present (CTA in each post) |
| Blog posts to Agents page | Present in some |
| Blog posts to CaaS pillar | Present in comparisons |
| Case studies to each other | MISSING |
| Case studies to department pages | MISSING |
| Comparison posts to each other | MISSING |
| Vision page to blog posts | MISSING |
| Skills page to relevant blog posts | MISSING |

The site has a hub-and-spoke structure radiating from the homepage but lacks lateral linking between related content. Blog posts link to the homepage and getting-started page but rarely to each other or to the specific product pages they reference.

---

## 5. Issues Summary (Prioritized)

### Critical Issues (Block Discoverability)

| # | Page | Issue | Impact | Status vs. 2026-03-17 |
|---|---|---|---|---|
| C1 | Homepage | Meta description uses "plugin" (brand guide violation) | Highest-impression meta text misrepresents product category | REPEAT from 2026-03-17 (C5) -- unfixed |
| C2 | Getting Started | Meta description uses "plugin" (brand guide violation) | Primary transactional page misrepresents product category | REPEAT from 2026-03-17 (C5) -- unfixed |
| C3 | Vision page | H1 is "Vision" -- zero keyword value | Most content-rich page has a 1-word H1 that provides no search signal | REPEAT from 2026-03-17 (C4) -- unfixed |

### Improvement Issues (Enhance Ranking)

| # | Page | Issue | Impact |
|---|---|---|---|
| I1 | Homepage | H1 has zero target keywords | H1 "Build a Billion-Dollar Company. Alone." -- no indexable terms |
| I2 | Homepage | "Open source" not mentioned | Misses "open source AI agent platform" commercial query |
| I3 | Homepage | "Solopreneur" absent | Misses high-volume variant of "solo founders" |
| I4 | Homepage | Agent count mismatch with brand guide (63 vs 61) | Trust signal inconsistency |
| I5 | Getting Started | No time-to-value in meta description | Competitors lead with "in 5 minutes" claims |
| I6 | Getting Started | Subtitle says "plugin" | Body text brand guide violation |
| I7 | Agents page | "Agentic engineering" used without definition | Misses extractable definition for AI engines |
| I8 | Agents page | "Open source" absent | Key differentiator missing from commercial page |
| I9 | Skills page | H1/title tag mismatch | "Agentic Engineering Skills" (H1) vs "Soleur Skills" (title) -- mixed signal |
| I10 | Skills page | Missing "AI workflow automation" keyword | Commercial search term absent |
| I11 | Vision page | Brand vocabulary violations ("synthetic labor," "soloentrepreneurs") | Off-brand terminology on a public page |
| I12 | Vision page | "Billion-Dollar Solopreneur" vs. "solo founders" inconsistency | Keyword targeting split |
| I13 | Blog index | H1 is "Blog" | Generic, zero keyword value |
| I14 | Plateau post | Missing "vibe coding vs agentic engineering" heading | Misses comparative search query |
| I15 | Comparison posts (all 3) | Titles missing "(2026)" | Comparison articles expire; dated queries are high-intent |
| I16 | Cowork comparison | "Claude Cowork" query variant not captured | Searchers use "Claude Cowork" not just "Anthropic Cowork" |
| I17 | Notion comparison | Pricing data will become stale (beta ends May 2026) | Requires freshness update |
| I18 | All case studies | No "Case Study" in titles | Misses "AI agent case study" search query |
| I19 | All case studies | No cross-links between case studies | Missed internal link value |
| I20 | All case studies | No links to department pages they demonstrate | Pillar/cluster linking absent |
| I21 | All case studies | Cost comparisons lack source citations | Authority signals weakened |
| I22 | Cross-site | "Open source" and "free" underrepresented in headings and meta | Two strongest differentiators buried in FAQ text |
| I23 | Cross-site | No lateral linking between comparison posts | Three comparison posts are isolated from each other |

---

## 6. Rewrite Suggestions

All suggestions aligned with brand voice: bold, declarative, forward-looking, precise. No hedging, no "just" or "simply," no "AI-powered" (redundant per brand guide).

### RS-1: Homepage Meta Description

**Current:** "The company-as-a-service platform. A Claude Code plugin that gives solo founders a full AI organization across every business department."

**Suggested:** "The open-source company-as-a-service platform. 63 AI agents across every business department -- engineering, marketing, legal, finance, and more. Built for solo founders."

**Rationale:** Removes "Claude Code plugin" (brand guide violation). Adds "open-source" (differentiator). Adds concrete agent count (authority signal). Adds "solo founders" at end for keyword proximity. 155 characters -- within SERP display limit.

---

### RS-2: Getting Started Meta Description

**Current:** "Install the Soleur Claude Code plugin and start running your company-as-a-service -- AI agents for engineering, marketing, legal, finance, and more."

**Suggested:** "Get started with Soleur in one command. Deploy 63 AI agents across engineering, marketing, legal, finance, and every business department. Free and open source."

**Rationale:** Removes "Claude Code plugin." Adds time-to-value ("one command"). Adds "free and open source" -- both strong CTR signals. Maintains keyword density for "AI agents."

---

### RS-3: Getting Started Subtitle

**Current:** "Install the Claude Code plugin that gives you a full AI organization."

**Suggested:** "One command. A full AI organization across every department."

**Rationale:** Removes "plugin" (brand guide). Leads with the speed claim. Declarative, matches brand voice.

---

### RS-4: Vision Page H1

**Current:** "Vision"

**Suggested:** "The Soleur Vision: Company-as-a-Service for the Solo Founder"

**Rationale:** Adds brand name, primary keyword, and target audience to H1. Maintains the declarative tone. Search engines can now associate this page with "company-as-a-service" and "solo founder" queries.

---

### RS-5: Skills Page H1

**Current:** "Agentic Engineering Skills"

**Suggested:** "Soleur Skills: Agentic Engineering Workflows"

**Rationale:** Aligns H1 with title tag pattern ("Soleur Skills"). "Workflows" is more commercially searchable than "Skills" alone. Maintains "agentic engineering" keyword.

---

### RS-6: Blog Index H1

**Current:** "Blog"

**Suggested:** "Soleur Blog"

**Rationale:** Minimal change. Adds brand name to H1 for keyword association. Keeps clean, simple branding.

---

### RS-7: Agents Page -- Agentic Engineering Definition

**Current:** No standalone definition. Term used in passing in intro paragraph.

**Suggested insertion after first mention of "agentic engineering":**

"Agentic engineering is a development methodology where specialized AI agents -- each with domain expertise, defined responsibilities, and shared institutional knowledge -- execute complex business workflows autonomously under human oversight."

**Rationale:** Provides a clear, quotable, self-contained definition. AI engines can extract and cite this directly. Hits "agentic engineering" keyword while also covering "AI agents," "business workflows," and "human oversight."

---

### RS-8: Comparison Post Titles (all three)

**Current:**
- "Soleur vs. Cursor: When an AI Coding Tool Becomes an Agent Platform"
- "Soleur vs. Anthropic Cowork: Which AI Agent Platform Is Right for Solo Founders?"
- "Soleur vs. Notion Custom Agents: Company-as-a-Service vs. Workspace Automation"

**Suggested:**
- "Soleur vs. Cursor (2026): When an AI Coding Tool Becomes an Agent Platform"
- "Soleur vs. Anthropic Cowork (2026): Which AI Agent Platform Is Right for Solo Founders?"
- "Soleur vs. Notion Custom Agents (2026): Company-as-a-Service vs. Workspace Automation"

**Rationale:** Captures dated search queries. Signals freshness. Standard practice for comparison content.

---

### RS-9: Cowork Comparison Meta Description

**Current:** "Soleur and Anthropic Cowork both deploy multi-domain AI agents. A direct comparison of knowledge architecture, workflow depth, cross-domain coherence, and pricing."

**Suggested:** "Soleur vs. Claude Cowork (Anthropic) in 2026 -- a direct comparison of AI agent architecture, cross-domain knowledge, workflow depth, and pricing for solo founders."

**Rationale:** Adds "Claude Cowork" keyword variant. Adds "(2026)" freshness signal. Adds "solo founders" for audience targeting.

---

### RS-10: Case Study Title Pattern

**Current example:** "How We Generated 9 Legal Documents in Days, Not Months"

**Suggested pattern:** "AI Legal Document Generation: 9 Documents in Days, Not Months [Case Study]"

**Rationale:** Leads with the searchable keyword ("AI Legal Document Generation"), retains the compelling specificity, and appends "[Case Study]" to capture that query class. Apply this pattern to all five case studies:

- "AI Brand Guide Creation: From Scattered Positioning to Full Brand Guide [Case Study]"
- "AI Business Validation: A 6-Gate Workshop That Changed Our Direction [Case Study]"
- "AI Competitive Intelligence: 17 Competitors Tracked in One Session [Case Study]"
- "AI Legal Document Generation: 9 Documents in Days, Not Months [Case Study]"
- "AI Operations Management: Building an Ops Department for a One-Person Company [Case Study]"

---

## 7. Priority Fix Matrix

| Fix | Effort | Impact | Priority | Addresses |
|---|---|---|---|---|
| Remove "plugin" from homepage meta description | Low | High | **P1** | C1 |
| Remove "plugin" from getting-started meta description | Low | High | **P1** | C2 |
| Remove "plugin" from getting-started subtitle | Low | High | **P1** | I6 |
| Rewrite vision page H1 | Low | Medium-High | **P1** | C3 |
| Add "open source" to homepage body text | Low | Medium | **P2** | I2, I22 |
| Add agentic engineering definition to agents page | Low | Medium | **P2** | I7 |
| Align skills page H1 with title tag | Low | Medium | **P2** | I9 |
| Add "(2026)" to all comparison post titles | Low | Medium | **P2** | I15 |
| Add "Claude Cowork" keyword to Cowork comparison | Low | Medium | **P2** | I16 |
| Add internal cross-links between case studies | Medium | Medium | **P2** | I19 |
| Add links from case studies to department pages | Medium | Medium | **P2** | I20 |
| Add cross-links between comparison posts | Low | Medium | **P2** | I23 |
| Rewrite case study titles with keyword-first pattern | Low | Medium | **P2** | I18 |
| Add "solopreneur" to homepage | Low | Low-Medium | **P3** | I3 |
| Update brand guide agent/skill counts (63/59) | Low | Low-Medium | **P3** | I4 |
| Rewrite blog index H1 | Low | Low | **P3** | I13 |
| Add "vibe coding vs agentic engineering" heading to plateau post | Low | Low-Medium | **P3** | I14 |
| Update Notion comparison pricing to evergreen phrasing | Low | Low | **P3** | I17 |
| Add source citations to case study cost comparisons | Medium | Low-Medium | **P3** | I21 |
| Replace "synthetic labor" and "soloentrepreneurs" on vision page | Low | Low | **P3** | I11 |

---

## 8. Progress Since Last Audit (2026-03-17)

### Fixed Since Last Audit

| 2026-03-17 Issue | Status |
|---|---|
| C1: Agents page FAQ missing JSON-LD schema | **FIXED** -- FAQ now present on agents page |
| C2: Plateau post FAQ missing JSON-LD schema | **FIXED** -- FAQ confirmed present |
| C3: Case studies lacking FAQ sections | **FIXED** -- All case studies now have FAQ sections with 3 questions each |
| I3: No FAQ on getting-started page | **FIXED** -- 5 FAQ questions now present |
| I5: No FAQ on skills page | **FIXED** -- 4 FAQ questions now present |

### Still Open

| 2026-03-17 Issue | Status | Current Issue # |
|---|---|---|
| C4: Vision H1 is "Vision" | UNFIXED | C3 |
| C5: "Plugin" in homepage and getting-started meta | UNFIXED | C1, C2 |
| I1: Homepage H1 has zero keywords | UNFIXED | I1 |
| I2: "Open source" missing from homepage | UNFIXED | I2 |
| I3: "Solopreneur" missing from homepage | UNFIXED | I3 |
| I4: Skills H1 generic | UNFIXED | I9 |
| I7: No case study cross-links | UNFIXED | I19 |
| I9: Cowork comparison missing "(2026)" | UNFIXED | I15 |

### New Issues Since Last Audit

| Issue | Source |
|---|---|
| I4: Agent count mismatch (63 on site vs 61 in brand guide) | Site updated, brand guide not |
| I15: All three comparison posts missing "(2026)" | Two new comparison posts added without year |
| I16: "Claude Cowork" keyword variant not captured | New observation |
| I17: Notion comparison pricing will become stale | Beta end date approaching |
| I23: No lateral linking between comparison posts | Three comparison posts now exist but don't reference each other |

---

## 9. Readability Assessment Summary

| Page | Readability Grade | Notes |
|---|---|---|
| Homepage | EXCELLENT | Short sentences, declarative tone, generous whitespace. Matches brand voice perfectly. |
| Getting Started | GOOD | Clear step-by-step. Code blocks for commands. Workflow stages well-enumerated. |
| Agents | GOOD | Scannable department sections. Intro could be tighter. |
| Skills | GOOD | Compound lifecycle well-explained. Category organization clear. |
| Vision | MODERATE | Dense paragraphs in places. Jargon-heavy ("AI Agent Swarms," "Recursive Dogfooding," "synthetic labor"). |
| Community | GOOD | Clean card layout. Minimal text -- appropriate for a navigation page. |
| Blog Index | GOOD | Clean article cards with dates and summaries. |
| CaaS Pillar Post | EXCELLENT | Best educational content. Clear definitions, comparison table, structured FAQ. |
| Plateau Post | EXCELLENT | Best analytical content. Data tables, concrete percentages, three-era framework. |
| Comparison Posts | GOOD-EXCELLENT | Consistent structure. Side-by-side tables. Honest assessments. |
| Case Studies | GOOD | Consistent 5-section structure. Specific numbers. Cost comparisons add value. |

Overall site readability is strong. The vision page is the only page with readability concerns, primarily due to undefined jargon and dense paragraphs.
