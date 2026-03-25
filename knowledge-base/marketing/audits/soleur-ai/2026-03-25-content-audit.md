# Soleur.ai Content Audit Report

**Date:** 2026-03-25
**Scope:** 8 site pages + 12 blog posts (full site coverage excluding legal documents, which are compliance content not subject to keyword optimization)
**Brand Guide:** `knowledge-base/marketing/brand-guide.md` (last updated 2026-03-22, last reviewed 2026-03-22)
**Method:** Live site fetched via WebFetch against `https://soleur.ai`. All content reflects the published state as of 2026-03-25.
**Previous Audit:** `knowledge-base/marketing/audits/soleur-ai/2026-03-23-content-audit.md`

---

## 1. Target Keyword Universe

Keywords derived from brand positioning, competitor landscape, and search intent analysis. Updated from 2026-03-23 audit to reflect two new blog posts (AI Agents for Solo Founders, Vibe Coding vs Agentic Engineering) and updated agent count (63).

| Keyword / Phrase | Search Intent | Relevance | Status on Site |
|---|---|---|---|
| company-as-a-service | Informational | HIGH | Strong coverage -- homepage, vision, pillar blog post, all comparisons |
| CaaS platform | Informational / Navigational | HIGH | Used in pillar article. Abbreviation indexed. |
| AI agents for solo founders | Commercial | HIGH | Now a dedicated blog post title AND meta descriptions across multiple pages |
| AI agents for business | Commercial | HIGH | Used as agents page meta description keyword |
| one person billion dollar company | Informational | HIGH | Concept discussed extensively; exact phrase still missing from headings |
| Claude Code plugin | Navigational / Commercial | HIGH | Present in meta descriptions (brand guide violation -- REPEAT) |
| agentic engineering | Informational | HIGH | Used on skills page H1, plateau blog post, and new vibe-coding comparison post |
| compound engineering | Informational | MEDIUM | Core concept in plateau article. New vibe-coding post reinforces. |
| compound knowledge base | Informational | MEDIUM | Differentiator keyword. Used in comparisons and plateau post. |
| vibe coding vs agentic engineering | Informational / Commercial | HIGH | NEW dedicated blog post published 2026-03-24. Exact phrase now targeted. |
| solopreneur AI tools 2026 | Commercial | HIGH | "Solopreneur" now appears in the AI Agents for Solo Founders post FAQ. Still absent from homepage. |
| AI business operations platform | Commercial | MEDIUM | Concept described; exact phrase absent |
| open source AI agent platform | Commercial | MEDIUM | Homepage still does not mention "open source" prominently |
| Soleur vs Cursor | Commercial | HIGH | Dedicated blog post (2026-03-19) |
| Soleur vs Cowork | Commercial / Navigational | HIGH | Dedicated blog post (2026-03-16) |
| Soleur vs Notion | Commercial | MEDIUM | Dedicated blog post (2026-03-17) |
| AI legal document generator | Commercial | MEDIUM | Case study addresses this. No dedicated landing page. |
| AI competitive intelligence | Commercial | MEDIUM | Case study addresses this. |
| business validation AI | Commercial | MEDIUM | Case study addresses this. |
| AI brand guide generator | Commercial | LOW-MEDIUM | Case study addresses this. Niche query. |
| AI workflow automation | Commercial | MEDIUM | Skills page describes concept; exact keyword absent |
| how to run a company with AI | Informational | HIGH | The new "AI Agents for Solo Founders" post partially covers this but no page directly targets the query |

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
| **Keyword alignment** | STRONG. Meta description contains primary keyword and audience. H1 captures aspirational search intent. Body text hits key terms naturally. Stats section (8 Departments, 63 AI Agents, 59 Skills) adds authority. |
| **Search intent match** | Mixed navigational/commercial. Correctly answers "what is this product and who is it for." |
| **Readability** | EXCELLENT. Short, declarative sentences. Punchy copy aligned with brand voice. Generous whitespace. Stats presented as monumental numbers. Section headings use brand voice ("This Is the Way," "Your AI Organization"). |
| **FAQ section** | Present under "Common Questions." Covers what/how/who/pricing/comparison topics. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | Meta description says "Claude Code plugin" | Brand guide (line 82): "Do not call it a 'plugin' or 'tool' in public-facing content -- it is a platform." The meta description is the single highest-impression text on the site. **REPEAT from 2026-03-17 (C5) and 2026-03-23 (C1) -- unfixed for 8 days.** |
| IMPROVEMENT | H1 contains zero target keywords | "Build a Billion-Dollar Company. Alone." is powerful brand copy but contains no indexable terms. The primary keyword "company-as-a-service" appears only in meta description and subheadline, not H1. |
| IMPROVEMENT | "Open source" absent from homepage | Soleur is Apache-2.0 licensed -- a key differentiator vs. Cowork ($20/mo), Notion ($10/1000 credits), and Cursor ($20-200/mo). The phrase "open source" does not appear on the homepage above the fold or in any heading. |
| IMPROVEMENT | "Solopreneur" absent from homepage | The word "solopreneur" does not appear despite being a high-volume search term. "Solo founders" captures the brand voice but "solopreneur" captures a broader audience in SERP. The new "AI Agents for Solo Founders" blog post includes "solopreneur" in an FAQ answer, proving the term is compatible with brand voice. |
| IMPROVEMENT | Agent count mismatch with brand guide (63 vs 61) | Homepage shows "63 AI Agents" but brand guide (line 26) says "61 agents, 59 skills." The brand guide is stale -- the site count is likely correct -- but this creates a trust signal mismatch when both are visible. |

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
| **Readability** | GOOD. Clear step-by-step structure with code blocks. Workflow stages (brainstorm, plan, work, review, compound) clearly enumerated. Example workflows provide concrete entry points. |
| **FAQ section** | Present. 5 questions covering requirements, platform support, pricing, commands, and existing projects. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | Meta description says "Claude Code plugin" | Same brand guide violation as homepage. This is the primary transactional landing page. **REPEAT from 2026-03-17 (C5) and 2026-03-23 (C2) -- unfixed for 8 days.** |
| IMPROVEMENT | No time-to-value claim in meta description | One-command installation is demonstrated in body but not communicated in meta. Adding "in one command" or "in under 5 minutes" would improve CTR from SERP. |
| IMPROVEMENT | Body text says "plugin" in subtitle | The "What Is Soleur?" section describes it as "a Claude Code plugin providing AI agents." Brand guide violation in visible body text. |
| IMPROVEMENT | Missing "free" or "open source" above fold | FAQ mentions both, but neither appears in the meta description or opening paragraph where search engines weight them most. |

---

### 2.3 Agents

**URL:** `https://soleur.ai/pages/agents.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Soleur AI Agents - Soleur" |
| **Meta description** | "AI agents for business -- engineering, marketing, legal, finance, operations, product, sales, and support." |
| **H1** | "Soleur AI Agents" |
| **Detected target keywords** | AI agents, AI agents for business, company-as-a-service, agentic engineering |
| **Keyword alignment** | STRONG. Meta description hits "AI agents for business" directly. H1 includes brand name and primary term. Body introduces "agentic engineering" and "cross-domain coherence." |
| **Search intent match** | Commercial investigation. Correct match for someone evaluating AI agent platforms. |
| **Readability** | GOOD. 8 department sections with agent counts are scannable. Philosophy section ("agentic engineering") is clear. 63 agents across 8 departments -- concrete numbers throughout. |
| **FAQ section** | Present. 4 questions on what agents are, customization, activation, and coverage. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | "Agentic engineering" used without standalone definition | The term appears in the intro philosophy section but lacks a self-contained, quotable definition sentence. Adding one improves AI-extractability for informational queries. |
| IMPROVEMENT | "Open source" absent | The agents page does not mention agents are open source and inspectable. This differentiates from Cowork (closed) and Cursor (closed). |
| IMPROVEMENT | Department descriptions lack brand voice energy | Descriptions like "Code review, architecture, security, quality testing" are functional lists. Compare to homepage's "You decide. Agents execute. Knowledge compounds." The agent descriptions could carry more of the brand's declarative energy. |

---

### 2.4 Skills

**URL:** `https://soleur.ai/pages/skills.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Soleur Skills - Soleur" |
| **Meta description** | "Multi-step workflow skills for the Soleur platform -- from feature development and code review to content writing, deployment, and agentic engineering." |
| **H1** | "Agentic Engineering Skills" |
| **Detected target keywords** | agentic engineering, workflow skills, code review, deployment |
| **Keyword alignment** | MODERATE. Targets "agentic engineering" well. Misses "AI workflow automation" and "AI business workflows" -- commercially-searched phrases. |
| **Search intent match** | Informational / navigational. Correct for product documentation. |
| **Readability** | GOOD. Clear compound engineering lifecycle (brainstorm, plan, implement, review, compound). 5 skill categories well-organized with counts. |
| **FAQ section** | Present. 4 questions on skill definition, invocation, lifecycle, and count. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | H1/title tag mismatch | Title tag = "Soleur Skills - Soleur"; H1 = "Agentic Engineering Skills." Search engines flag title/H1 mismatch as a mixed signal. These should be aligned. |
| IMPROVEMENT | Missing keyword: "AI workflow automation" | The concept of multi-step automated workflows is described extensively but the commercially-searched phrase "AI workflow automation" is absent from headings, meta, and body text. |
| IMPROVEMENT | No "company-as-a-service" keyword | The skills page does not reference the primary platform keyword "company-as-a-service" anywhere. Even one contextual mention would strengthen keyword consistency. |

---

### 2.5 Pricing

**URL:** `https://soleur.ai/pages/pricing.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Pricing - Soleur" |
| **Meta description** | "Soleur is free and open source. You pay only for Claude usage. See how Soleur compares to Cursor, Devin, and GitHub Copilot." |
| **H1** | "Every department. One price." |
| **Detected target keywords** | free, open source, Claude, Cursor, Devin, GitHub Copilot |
| **Keyword alignment** | GOOD. Meta description captures "free and open source" and competitor names for comparison queries. H1 is creative but keyword-light. |
| **Search intent match** | Transactional / commercial investigation. Correct for pricing evaluation. |
| **Readability** | EXCELLENT. Two clear tiers (Open Source $0 / Hosted Pro $49). Comparison table against Cursor, Devin, GitHub Copilot. Pricing FAQ addresses key objections. |
| **FAQ section** | Present. 4 questions covering "Is Soleur really free?", Claude costs, pricing philosophy, and future paid versions. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | H1 "Every department. One price." lacks keywords | Creative but no indexable terms. "Soleur Pricing" or "Soleur Pricing: Free and Open Source" would capture pricing-intent queries. |
| IMPROVEMENT | Hosted Pro at $49/mo plus 10% revenue share -- no timeline | "Coming Soon / Join the Waitlist" is acceptable for now, but the pricing page does not indicate when Hosted Pro launches. This creates ambiguity for commercial-intent visitors. |
| IMPROVEMENT | Devin and GitHub Copilot in meta description but no dedicated comparison posts | The meta description promises comparison with Devin and GitHub Copilot, but the comparison table is the only coverage. Dedicated blog posts would capture "Soleur vs Devin" and "Soleur vs GitHub Copilot" queries. |
| IMPROVEMENT | "AI agents for business" absent from pricing page | This commercial keyword should appear somewhere on the pricing page to associate pricing content with the agent platform concept. |

---

### 2.6 Vision

**URL:** `https://soleur.ai/pages/vision.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Vision - Soleur" |
| **Meta description** | "Where Soleur is headed. The Company-as-a-Service platform that gives solo founders the leverage of a full organization." |
| **H1** | "Vision" |
| **Detected target keywords** | company-as-a-service, solo founder, model-agnostic, AI organization |
| **Keyword alignment** | WEAK. Meta description is acceptable. H1 is a single generic word with zero keyword value. Body text is rich with keywords but the heading hierarchy does not surface them. |
| **Search intent match** | Navigational (existing users seeking roadmap). Does not capture informational traffic. |
| **Readability** | MODERATE. Some sections are dense ("Strategic Architecture," "Revenue Philosophy"). Milestone 3 ("spacefleets and multiplanetary operations") may confuse visitors expecting a near-term product roadmap. |
| **FAQ section** | Present. 4 questions covering thesis, CaaS definition, model-agnostic status, and roadmap. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | H1 is "Vision" -- zero keyword value | A one-word H1 provides no search signal. This is the most content-rich page on the site with substantial keyword-bearing body copy, but the H1 wastes the primary heading signal. **REPEAT from 2026-03-17 (C4) and 2026-03-23 (C3) -- unfixed for 8 days.** |
| IMPROVEMENT | "Synthetic labor" not in brand vocabulary | The phrase "synthetic labor" appears on the vision page but is absent from the brand guide. It frames AI agents as labor replacement rather than an organization the founder commands -- counter to the brand's positioning ("You decide. Agents execute."). |
| IMPROVEMENT | "CEO Dashboard" referenced but not explained | The vision page mentions a "CEO Dashboard" under Model-Agnostic Architecture without defining it or linking to it. Creates unresolved references. |
| IMPROVEMENT | Master Plan milestones 2 and 3 are vague | Milestone 1 (automate software operations) is concrete and actionable. Milestones 2 (hardware/robots/manufacturing) and 3 (spacefleets/multiplanetary) are aspirational without specifics. Vague claims reduce authority signals for AI extraction. |
| IMPROVEMENT | Brand vocabulary inconsistency | "Billion-Dollar Solopreneur" vs. "solo founders" and "soloentrepreneurs" -- three different terms for the target audience on one page. All other pages use "solo founders" consistently. |

---

### 2.7 Community

**URL:** `https://soleur.ai/pages/community.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Community - Soleur" |
| **Meta description** | "Join the Soleur community. Connect on Discord, contribute on GitHub, get help, and learn about our community guidelines." |
| **H1** | "Community" |
| **Detected target keywords** | Soleur (brand name only) |
| **Keyword alignment** | WEAK. No target keywords in H1, meta description, or body beyond the brand name. This is a navigation page, so low keyword density is expected, but minimal context-setting text is missing. |
| **Search intent match** | Navigational. Correct for existing users seeking community links. Not designed for search traffic capture. |
| **Readability** | GOOD. Clean card-based layout with five channels (Discord, X/Twitter, LinkedIn, Bluesky, GitHub). Contributing and Getting Help sections are clear and actionable. |
| **FAQ section** | Present. 4 questions on contributing, help channels, CLA requirements, and community presence. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | No keyword context in introductory text | The community page jumps straight to channel links. Adding a one-sentence intro like "The open-source Soleur community for solo founders building with AI agents" would add keyword context without changing the page purpose. |

---

### 2.8 Changelog

**URL:** `https://soleur.ai/pages/changelog.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | "Changelog - Soleur" |
| **Meta description** | "Changelog - All notable changes to Soleur." |
| **H1** | "Changelog" |
| **Detected target keywords** | Soleur (brand name only) |
| **Keyword alignment** | MINIMAL. This is a technical reference page, so low keyword density is expected. |
| **Search intent match** | Navigational. Correct for existing users tracking releases. |
| **Readability** | GOOD. Chronological version entries (v3.26.5 down to earlier versions). Bullet-point format for each release. FAQ section present. |
| **FAQ section** | Present. Covers update frequency, upgrade procedures, and versioning practices. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Meta description is generic | "Changelog - All notable changes to Soleur" adds no keyword value. Could be "Soleur changelog -- release notes for the company-as-a-service platform, including new agents, skills, and features." |

---

## 3. Blog Post Analysis

### 3.1 "What Is Company-as-a-Service?" (Pillar)

**Published:** 2026-03-05
**URL:** `https://soleur.ai/blog/what-is-company-as-a-service/`

| Attribute | Assessment |
|---|---|
| **Meta description** | "Company-as-a-Service is a new model where AI agents run every business department. Learn what CaaS means, how it works, and why it matters for solo founders." |
| **Keyword alignment** | EXCELLENT. Targets "company-as-a-service," "CaaS," "AI agents," "solo founders." Category-defining pillar content. |
| **Search intent** | Informational. Matches "what is company-as-a-service" query directly. |
| **Readability** | EXCELLENT. Clear H2/H3 hierarchy. CaaS vs. SaaS vs. AIaaS vs. BPaaS comparison table. Structured definitions. Industry data (Cursor $1B ARR, Lovable $200M ARR, Amodei/Altman predictions). |
| **Authority signals** | STRONG. Cites Bureau of Labor Statistics, TechCrunch, CNBC, VentureBeat, Inc.com, Fortune. Specific market data and CEO quotes. |
| **FAQ section** | Present. 5 questions with clear, self-contained answers. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Missing heading for "one person billion dollar company" | The article discusses this concept extensively but the exact high-volume phrase does not appear as a heading. An H2 or H3 would capture this informational query. |
| IMPROVEMENT | Opening definition could be more concise for AI extraction | The first sentence is strong but runs long. A 1-2 sentence standalone definition followed by expansion would be more extractable by AI engines. |

---

### 3.2 "Why Most Agentic Engineering Tools Plateau"

**Published:** 2026-03-14
**URL:** `https://soleur.ai/blog/why-most-agentic-tools-plateau/`

| Attribute | Assessment |
|---|---|
| **Meta description** | "Most AI coding tools stop getting better after week two. The missing layer is compound knowledge -- a system that learns from every task and feeds those learnings back into its own rules, agents, and workflows." |
| **Keyword alignment** | STRONG. Targets "agentic engineering," "compound knowledge," "AI coding tools," "compound engineering." Three-era framework (vibe coding, spec-driven, compound engineering) captures multiple search queries. |
| **Search intent** | Informational. Matches "why AI coding tools plateau" and "compound engineering" queries. |
| **Readability** | EXCELLENT. Best-structured article on the site. Data tables with concrete reduction percentages (30-96%), comparison matrix, three-era framework. Specific governance growth data (26 to 200+ rules). |
| **Authority signals** | STRONG. References Karpathy, specific GitHub repos (Spec Kit 76,000+ stars), names competitors with specifics. Original data throughout. |
| **FAQ section** | Present. 3 questions covering compound engineering, knowledge compounding, and vibe coding vs agentic engineering distinction. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Comparison matrix may need update | The competitive landscape moves fast. New entrants since publication should be assessed for inclusion. Stale comparison tables reduce perceived authority. |

---

### 3.3 "AI Agents for Solo Founders: The Definitive Guide" (NEW)

**Published:** 2026-03-24
**URL:** `https://soleur.ai/blog/ai-agents-for-solo-founders/`

| Attribute | Assessment |
|---|---|
| **Meta description** | "The complete guide to AI agents for solo founders in 2026. What makes a true AI agent, the 8 domains every company needs, and why compound knowledge is the only path to solo-founder scale." |
| **Keyword alignment** | EXCELLENT. Title directly targets "AI agents for solo founders" -- a high-volume commercial query. Meta description adds "2026" for freshness. Body covers "solopreneur" (in FAQ), "compound knowledge," "AI organization." |
| **Search intent** | Informational / commercial. Matches "AI agents for solo founders" and "solopreneur AI tools" queries. |
| **Readability** | EXCELLENT. Clear four-property framework for "what makes a true agent." Eight-domain breakdown is systematic. Getting-started steps provide actionable guidance. |
| **Authority signals** | GOOD. Defines terms precisely (4 properties of agents). Makes categorical distinctions (agents vs chatbots). Cross-references internal concepts (CaaS). |
| **FAQ section** | Present. 6 questions covering definition, differentiation from chatbots, solopreneur tools, compound knowledge, technical requirements, and getting started. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Agent count inconsistency within post | Body text says "61 agents across 8 departments" while the homepage and other pages say "63 AI Agents." This inconsistency within the same site harms trust signals. |
| IMPROVEMENT | No external source citations | Unlike the CaaS pillar post (which cites TechCrunch, CNBC, etc.), this post makes market claims without external attribution. Adding industry citations would strengthen authority. |
| IMPROVEMENT | Missing internal link to comparison posts | The post discusses "point solution" limitations but does not link to the three comparison posts (vs Cursor, vs Cowork, vs Notion) which demonstrate the specific failures of point solutions. |

---

### 3.4 "Vibe Coding vs Agentic Engineering: What Solo Founders Need to Know" (NEW)

**Published:** 2026-03-24
**URL:** `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/`

| Attribute | Assessment |
|---|---|
| **Meta description** | Inferred from site-level description. The page inherits the site meta but should have its own. |
| **Keyword alignment** | EXCELLENT. Title directly targets the growing comparison query "vibe coding vs agentic engineering." Body defines both terms precisely. "Solo founders" in title captures audience keyword. |
| **Search intent** | Informational. Matches "vibe coding vs agentic engineering" and "what is agentic engineering" queries. |
| **Readability** | EXCELLENT. Clear side-by-side contrast (conversational vs specification-driven, single-session vs persistent memory, manual QA vs automated gates). FAQ reinforces key definitions. |
| **Authority signals** | GOOD. Precise terminology. Connects to CaaS concept. References compound engineering lifecycle. |
| **FAQ section** | Present. 5 questions with concise, standalone answers. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Meta description may be missing or generic | The fetched content showed the site-level meta description rather than a page-specific one. If the page lacks its own meta description, it will display the site default in SERP, which does not capture "vibe coding" or "agentic engineering" keywords. |
| IMPROVEMENT | No link to the Plateau post | The vibe coding vs agentic engineering distinction was first introduced in the Plateau post. This new post should link to it for deeper context and internal link value. |
| IMPROVEMENT | Missing external citations | No references to Karpathy (who coined "vibe coding"), Andrej's original blog post, or industry commentary on agentic engineering. The Plateau post includes these; this post should at minimum link to it or cite independently. |

---

### 3.5 "Soleur vs. Cursor"

**Published:** 2026-03-19
**URL:** `https://soleur.ai/blog/soleur-vs-cursor/`

| Attribute | Assessment |
|---|---|
| **Meta description** | "Cursor shipped Automations and a Marketplace in March 2026, becoming an agent platform. A direct comparison with Soleur's Company-as-a-Service platform for solo founders." |
| **Keyword alignment** | STRONG. Targets "Soleur vs Cursor," "AI coding tool," "agent platform," "solo founders." Includes specific market data (Cursor $2B ARR, 30% autonomous PRs). |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | GOOD. Clear "Where They Differ" subsections covering domain coverage, knowledge architecture, workflow orchestration, and pricing. |
| **Authority signals** | GOOD. References specific Cursor features (Automations, Marketplace, Cloud Agents) with timeline and revenue data. |
| **FAQ section** | Present. 4 questions addressing coexistence, memory comparison, marketplace comparison, and revenue interpretation. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title missing "(2026)" | Comparison articles date rapidly. Including the year captures dated search queries ("Soleur vs Cursor 2026") and signals freshness. |
| IMPROVEMENT | No lateral link to Cowork or Notion comparisons | Three comparison posts exist but do not reference each other. A "See also" section or inline link would strengthen internal architecture. |

---

### 3.6 "Soleur vs. Anthropic Cowork"

**Published:** 2026-03-16
**URL:** `https://soleur.ai/blog/soleur-vs-anthropic-cowork/`

| Attribute | Assessment |
|---|---|
| **Meta description** | "Soleur and Anthropic Cowork both deploy multi-domain AI agents. A direct comparison of knowledge architecture, workflow depth, cross-domain coherence, and pricing." |
| **Keyword alignment** | STRONG. Targets "Soleur vs Cowork," "AI agent platform," "solo founders." Includes Microsoft Copilot Cowork as bonus coverage -- captures a three-way comparison. |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | EXCELLENT. Three-platform side-by-side table. Clear sections. Honest assessment of when each platform is the right choice. |
| **Authority signals** | STRONG. Cites TechCrunch, The Decoder, Claude pricing page. Specific feature comparison with pricing details. |
| **FAQ section** | Present. 5 questions including Microsoft Copilot Cowork coverage. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title missing "(2026)" | Same as Cursor comparison. |
| IMPROVEMENT | "Claude Cowork" keyword variant not captured in title or meta | Many searchers will query "Claude Cowork" or "Soleur vs Claude Cowork" rather than "Anthropic Cowork." Neither the title nor meta description includes "Claude Cowork." |
| IMPROVEMENT | "Terminal-first" language in FAQ answer 5 | FAQ says "Soleur is terminal-first, running inside Claude Code." Brand guide (updated 2026-03-22) prohibits "terminal-first" as a positioning advantage. The delivery pivot requires device-agnostic language. |

---

### 3.7 "Soleur vs. Notion Custom Agents"

**Published:** 2026-03-17
**URL:** `https://soleur.ai/blog/soleur-vs-notion-custom-agents/`

| Attribute | Assessment |
|---|---|
| **Meta description** | "Notion Custom Agents automate recurring workspace tasks. Soleur runs a full AI organization with compounding knowledge. A direct comparison for solo founders." |
| **Keyword alignment** | GOOD. Targets "Soleur vs Notion," "Notion Custom Agents," "solo founders." |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | GOOD. Clear structure with side-by-side comparison table and pricing breakdown. |
| **Authority signals** | GOOD. Specific Notion data (21,000 beta agents built, 2,800 internal). Pricing details. |
| **FAQ section** | Present. 5 questions with actionable answers. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title missing "(2026)" | Same as other comparisons. |
| IMPROVEMENT | Notion pricing will become stale | The article references "Free beta until May 3, 2026." That date is 39 days away. After it passes, the pricing section becomes inaccurate. Needs evergreen phrasing or a planned update. |
| IMPROVEMENT | Missing "Notion AI" keyword variant | Many searchers will use "Notion AI" rather than "Notion Custom Agents." Neither title nor meta captures this variant. |
| IMPROVEMENT | "Terminal-first" used in "Who each platform is for" section | Same brand guide violation as Cowork comparison. "Soleur suits users who: Work in terminal via Claude Code." |

---

### 3.8 Case Studies (5 posts)

All five case studies follow a consistent, strong structure: problem statement, AI approach, result, cost comparison, compound effect, FAQ. This is good content architecture.

| Case Study | URL | Meta Description Quality | Keyword Alignment | FAQ |
|---|---|---|---|---|
| Brand Guide Creation | `/blog/case-study-brand-guide-creation/` | GOOD -- specific outcome | MODERATE -- "AI brand guide" present, "brand workshop" absent | 3 Qs |
| Business Validation | `/blog/case-study-business-validation/` | EXCELLENT -- "PIVOT verdict" | GOOD -- "business validation," "AI gates" | 3 Qs |
| Competitive Intelligence | `/blog/case-study-competitive-intelligence/` | GOOD -- "17 competitors," "battlecards" | MODERATE -- "competitive intelligence" present, "AI competitor analysis" absent | 3 Qs |
| Legal Document Generation | `/blog/case-study-legal-document-generation/` | EXCELLENT -- "9 documents," "17,761 words" | GOOD -- "AI legal documents" | 3 Qs |
| Operations Management | `/blog/case-study-operations-management/` | GOOD -- specific functions | MODERATE -- "operations," "expense tracking" | 3 Qs |

**Shared issues across all case studies:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | No "Case Study" in titles | Titles are narrative ("How We Generated 9 Legal Documents...") which is engaging but misses the "AI agent case study" search query class. A "[Case Study]" suffix or keyword-first prefix would capture this traffic. |
| IMPROVEMENT | No internal cross-links between case studies | Each case study is isolated. A "Related case studies" section would strengthen internal link architecture and keep readers on-site. |
| IMPROVEMENT | No links back to department pages they demonstrate | The brand guide case study should link to the agents page (marketing department). The legal case study should link to agents page (legal department). This pillar/cluster linking is absent. |
| IMPROVEMENT | Cost comparison sections lack citations | Statements like "a startup strategy consultant charges $4,000-$16,000" are presented without source attribution. Adding citations (Clutch, Glassdoor, industry reports) would strengthen authority signals. |

---

## 4. Cross-Site Issues

### 4.1 Brand Voice Compliance

| Issue | Severity | Pages Affected |
|---|---|---|
| "Plugin" used in meta descriptions | CRITICAL | Homepage, Getting Started |
| "Plugin" used in body text | IMPROVEMENT | Getting Started subtitle, Getting Started body |
| "Terminal-first" used as positioning | IMPROVEMENT | Cowork comparison (FAQ), Notion comparison ("Who each platform is for") |
| "Synthetic labor" not in brand vocabulary | IMPROVEMENT | Vision page |
| "CEO Dashboard" undefined term | IMPROVEMENT | Vision page |
| "Soloentrepreneurs" (nonstandard) vs "solo founders" | IMPROVEMENT | Vision page |

**Assessment:** The two newest blog posts (AI Agents for Solo Founders, Vibe Coding vs Agentic Engineering) maintain strong brand voice alignment -- declarative, bold, forward-looking, no hedging. The "plugin" violations remain concentrated in meta descriptions and the Getting Started page. The "terminal-first" violations in comparison posts reflect pre-2026-03-22 brand guide language and need updating.

### 4.2 Keyword Consistency Matrix

| Term | Homepage | Getting Started | Agents | Skills | Pricing | Vision | Blog Posts |
|---|---|---|---|---|---|---|---|
| company-as-a-service | Yes | Yes | Yes | No | No | Yes | Yes (all) |
| AI agents | Yes | Yes | Yes | No | Yes | Yes | Yes (all) |
| solo founders | Yes | Yes | No | No | No | Yes | Yes (most) |
| open source | No | FAQ only | No | No | Meta only | No | Some comparisons |
| solopreneur | No | No | No | No | No | Yes (once) | Solo Founders post FAQ |
| agentic engineering | No | No | Intro | Yes (H1) | No | No | Plateau, Vibe Coding posts |
| compound knowledge | No | No | Intro | Intro | No | No | Plateau, comparisons |
| free | FAQ only | FAQ only | No | No | H2, meta | No | Comparisons (pricing) |
| vibe coding | No | No | No | No | No | No | Vibe Coding post, Plateau post |

**Key gaps:** "Open source" and "free" are the two strongest competitive differentiators (Soleur is free; Cursor is $20-200/mo; Cowork is $20/mo) but appear only in FAQ sections, pricing meta, and deep body copy -- never in homepage headings or main page meta descriptions. "Solopreneur" has been partially addressed by the new blog post but remains absent from all site pages.

### 4.3 Internal Linking Assessment

| Link Pattern | Status |
|---|---|
| Homepage to all nav pages | Present |
| Blog posts to Getting Started | Present (CTA in each post) |
| Blog posts to Agents page | Present in some |
| Blog posts to CaaS pillar | Present in comparisons and new posts |
| Case studies to each other | MISSING |
| Case studies to department pages | MISSING |
| Comparison posts to each other | MISSING |
| Vibe Coding post to Plateau post | MISSING |
| Solo Founders post to comparison posts | MISSING |
| Vision page to blog posts | MISSING |
| Skills page to relevant blog posts | MISSING |
| Pricing page to comparison posts | MISSING |

The site has a hub-and-spoke structure radiating from the homepage but lacks lateral linking between related content. The three comparison posts are isolated from each other. The two newest posts (Solo Founders guide, Vibe Coding comparison) do not link to related existing content.

### 4.4 Agent Count Inconsistency

| Source | Agent Count | Skill Count |
|---|---|---|
| Brand guide (2026-03-22) | 61 | 59 |
| Homepage (2026-03-25) | 63 | 59 |
| Agents page | 63 | -- |
| AI Agents for Solo Founders post | 61 | -- |
| Comparison posts (all 3) | 63 | -- |
| CaaS pillar post | 63 | -- |

The blog post "AI Agents for Solo Founders" says "61 agents" while every other page says "63." The brand guide says "61." This creates internal inconsistency that erodes trust signals. The brand guide should be updated to 63 (or whatever the current count is), and all content should be synchronized.

---

## 5. Issues Summary (Prioritized)

### Critical Issues (Block Discoverability)

| # | Page | Issue | Impact | Status vs. 2026-03-23 |
|---|---|---|---|---|
| C1 | Homepage | Meta description uses "plugin" (brand guide violation) | Highest-impression meta text misrepresents product category | REPEAT -- unfixed since 2026-03-17 |
| C2 | Getting Started | Meta description uses "plugin" (brand guide violation) | Primary transactional page misrepresents product category | REPEAT -- unfixed since 2026-03-17 |
| C3 | Vision page | H1 is "Vision" -- zero keyword value | Most content-rich page has a 1-word H1 with no search signal | REPEAT -- unfixed since 2026-03-17 |

### Improvement Issues (Enhance Ranking)

| # | Page | Issue | Impact |
|---|---|---|---|
| I1 | Homepage | H1 has zero target keywords | "Build a Billion-Dollar Company. Alone." -- no indexable terms |
| I2 | Homepage | "Open source" not mentioned | Misses "open source AI agent platform" commercial query |
| I3 | Homepage | "Solopreneur" absent | Misses high-volume variant of "solo founders" |
| I4 | Cross-site | Agent count mismatch (63 vs 61) | Trust signal inconsistency across pages and brand guide |
| I5 | Getting Started | No time-to-value in meta description | Competitors lead with "in 5 minutes" claims |
| I6 | Getting Started | Body text says "plugin" | Brand guide violation in visible body text |
| I7 | Agents page | "Agentic engineering" used without definition | Misses extractable definition for AI engines |
| I8 | Agents page | "Open source" absent | Key differentiator missing from commercial page |
| I9 | Skills page | H1/title tag mismatch | "Agentic Engineering Skills" (H1) vs "Soleur Skills" (title) -- mixed signal |
| I10 | Skills page | Missing "AI workflow automation" keyword | Commercial search term absent |
| I11 | Pricing page | H1 lacks keywords | "Every department. One price." -- creative but not indexable |
| I12 | Pricing page | No comparison blog post links | Pricing mentions Cursor/Devin/Copilot but does not link to comparison content |
| I13 | Vision page | Brand vocabulary violations ("synthetic labor," "soloentrepreneurs") | Off-brand terminology on public page |
| I14 | Vision page | "Billion-Dollar Solopreneur" vs "solo founders" inconsistency | Keyword targeting split |
| I15 | Community page | No keyword context in intro | Navigation page lacks basic keyword context |
| I16 | Changelog | Generic meta description | Misses "company-as-a-service" keyword opportunity |
| I17 | Blog index | H1 is "Blog" | Generic, zero keyword value |
| I18 | Solo Founders post | Agent count says "61" (inconsistent with site) | Internal data contradiction |
| I19 | Solo Founders post | No external source citations | Market claims without attribution |
| I20 | Solo Founders post | No link to comparison posts | Missed internal link opportunity |
| I21 | Vibe Coding post | Possible missing page-specific meta description | May display site default in SERP |
| I22 | Vibe Coding post | No link to Plateau post | Missed internal link to related content |
| I23 | Vibe Coding post | No external citations (e.g., Karpathy) | "Vibe coding" origin not attributed |
| I24 | Comparison posts (all 3) | Titles missing "(2026)" | Comparison articles expire; dated queries are high-intent |
| I25 | Cowork comparison | "Claude Cowork" query variant not captured | Searchers use "Claude Cowork" not "Anthropic Cowork" |
| I26 | Notion comparison | Pricing data will become stale (beta ends May 2026) | Requires freshness update in 39 days |
| I27 | Notion comparison | Missing "Notion AI" keyword variant | Broader query not captured |
| I28 | Cowork + Notion comparisons | "Terminal-first" used as positioning | Brand guide (2026-03-22) prohibits this language |
| I29 | All case studies (5) | No "Case Study" in titles | Misses "AI agent case study" search query class |
| I30 | All case studies (5) | No cross-links between case studies | Missed internal link value |
| I31 | All case studies (5) | No links to department pages they demonstrate | Pillar/cluster linking absent |
| I32 | All case studies (5) | Cost comparisons lack source citations | Authority signals weakened |
| I33 | Cross-site | "Open source" and "free" underrepresented in headings and meta | Two strongest differentiators buried in FAQ text |
| I34 | Cross-site | No lateral linking between comparison posts | Three comparison posts isolated from each other |
| I35 | Cross-site | Two new posts not cross-linked to existing content | Solo Founders and Vibe Coding posts are orphaned from related blog content |

---

## 6. Rewrite Suggestions

All suggestions aligned with brand voice: bold, declarative, forward-looking, precise. No hedging, no "just" or "simply," no "AI-powered" (redundant per brand guide). No "plugin" or "tool" in public-facing copy. No "terminal-first" as positioning advantage.

### RS-1: Homepage Meta Description

**Current:** "The company-as-a-service platform. A Claude Code plugin that gives solo founders a full AI organization across every business department."

**Suggested:** "The open-source company-as-a-service platform. 63 AI agents across every business department -- engineering, marketing, legal, finance, and more. Built for solo founders."

**Rationale:** Removes "Claude Code plugin" (brand guide violation). Adds "open-source" (differentiator). Adds concrete agent count (authority signal). Adds "solo founders" at end for keyword proximity. 155 characters -- within SERP display limit.

---

### RS-2: Getting Started Meta Description

**Current:** "Install the Soleur Claude Code plugin and start running your company-as-a-service -- AI agents for engineering, marketing, legal, finance, and more."

**Suggested:** "Get started with Soleur in one command. Deploy 63 AI agents across engineering, marketing, legal, finance, and every business department. Free and open source."

**Rationale:** Removes "Claude Code plugin." Adds time-to-value ("one command"). Adds "free and open source" -- both strong CTR signals. Maintains keyword density for "AI agents." 156 characters.

---

### RS-3: Getting Started Body Subtitle

**Current:** "Install the Claude Code plugin that gives you a full AI organization." (inferred from page content describing Soleur as "a Claude Code plugin providing AI agents")

**Suggested:** "One command. A full AI organization across every department."

**Rationale:** Removes "plugin" (brand guide). Leads with speed claim. Declarative, matches brand voice. No hedging.

---

### RS-4: Vision Page H1

**Current:** "Vision"

**Suggested:** "The Soleur Vision: Company-as-a-Service for the Solo Founder"

**Rationale:** Adds brand name, primary keyword, and target audience to H1. Maintains declarative tone. Search engines now associate this page with "company-as-a-service" and "solo founder" queries. This has been suggested in the last two audits and remains unfixed.

---

### RS-5: Skills Page H1

**Current:** "Agentic Engineering Skills"

**Suggested:** "Soleur Skills: Agentic Engineering Workflows"

**Rationale:** Aligns H1 with title tag pattern ("Soleur Skills"). "Workflows" is more commercially searchable than "Skills" alone. Maintains "agentic engineering" keyword. Resolves H1/title mismatch (I9).

---

### RS-6: Blog Index H1

**Current:** "Blog"

**Suggested:** "Soleur Blog"

**Rationale:** Minimal change. Adds brand name to H1 for keyword association.

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

**Rationale:** Captures dated search queries ("Soleur vs Cursor 2026"). Signals freshness. Standard practice for comparison content.

---

### RS-9: Cowork Comparison Meta Description

**Current:** "Soleur and Anthropic Cowork both deploy multi-domain AI agents. A direct comparison of knowledge architecture, workflow depth, cross-domain coherence, and pricing."

**Suggested:** "Soleur vs. Claude Cowork (Anthropic) in 2026 -- a direct comparison of AI agent architecture, cross-domain knowledge, workflow depth, and pricing for solo founders."

**Rationale:** Adds "Claude Cowork" keyword variant. Adds "(2026)" freshness signal. Adds "solo founders" for audience targeting. 152 characters.

---

### RS-10: Case Study Title Pattern

**Current example:** "How We Generated 9 Legal Documents in Days, Not Months"

**Suggested pattern:** "AI Legal Document Generation: 9 Documents in Days, Not Months [Case Study]"

**Rationale:** Leads with searchable keyword, retains compelling specificity, appends "[Case Study]" to capture that query class. Apply to all five:

- "AI Brand Guide Creation: From Scattered Positioning to Full Brand Guide [Case Study]"
- "AI Business Validation: A 6-Gate Workshop That Changed Our Direction [Case Study]"
- "AI Competitive Intelligence: 17 Competitors Tracked in One Session [Case Study]"
- "AI Legal Document Generation: 9 Documents in Days, Not Months [Case Study]"
- "AI Operations Management: Building an Ops Department for a One-Person Company [Case Study]"

---

### RS-11: Pricing Page H1

**Current:** "Every department. One price."

**Suggested:** "Soleur Pricing: Free and Open Source"

**Rationale:** Captures "Soleur pricing" navigational query. "Free and open source" are the two most compelling differentiators against paid competitors ($20-200/mo). Declarative, matches brand voice.

---

### RS-12: Changelog Meta Description

**Current:** "Changelog - All notable changes to Soleur."

**Suggested:** "Soleur changelog -- release notes for the company-as-a-service platform. New agents, skills, and features."

**Rationale:** Adds "company-as-a-service" keyword. Describes what the changelog contains. Minimal effort, low risk.

---

### RS-13: Cowork Comparison -- Remove "Terminal-First" Positioning

**Current (FAQ answer 5):** "Soleur is terminal-first, running inside Claude Code."

**Suggested:** "Soleur runs inside Claude Code. For M365-centered workflows, Microsoft Copilot Cowork is the better choice."

**Rationale:** Removes "terminal-first" positioning language per brand guide update (2026-03-22). States the fact without framing it as a positioning advantage.

---

### RS-14: Notion Comparison -- Remove "Terminal-First" Positioning

**Current ("Who each platform is for"):** "Work in terminal via Claude Code"

**Suggested:** "Build with Claude Code"

**Rationale:** Same brand guide compliance as RS-13. Device-agnostic language.

---

### RS-15: Solo Founders Post -- Agent Count Fix

**Current:** "61 agents across 8 departments"

**Suggested:** "63 agents across 8 departments"

**Rationale:** Aligns with current homepage count and all other content. Resolves I18.

---

## 7. Priority Fix Matrix

| Fix | Effort | Impact | Priority | Addresses |
|---|---|---|---|---|
| Remove "plugin" from homepage meta description (RS-1) | Low | High | **P1** | C1 |
| Remove "plugin" from getting-started meta description (RS-2) | Low | High | **P1** | C2 |
| Remove "plugin" from getting-started body text (RS-3) | Low | High | **P1** | I6 |
| Rewrite vision page H1 (RS-4) | Low | Medium-High | **P1** | C3 |
| Fix agent count in Solo Founders post (RS-15) | Low | Medium | **P1** | I18, I4 |
| Remove "terminal-first" from Cowork comparison (RS-13) | Low | Medium | **P1** | I28 |
| Remove "terminal-first" from Notion comparison (RS-14) | Low | Medium | **P1** | I28 |
| Add "open source" to homepage body text | Low | Medium | **P2** | I2, I33 |
| Add agentic engineering definition to agents page (RS-7) | Low | Medium | **P2** | I7 |
| Align skills page H1 with title tag (RS-5) | Low | Medium | **P2** | I9 |
| Rewrite pricing page H1 (RS-11) | Low | Medium | **P2** | I11 |
| Add "(2026)" to all comparison post titles (RS-8) | Low | Medium | **P2** | I24 |
| Add "Claude Cowork" keyword to Cowork comparison (RS-9) | Low | Medium | **P2** | I25 |
| Add internal cross-links between case studies | Medium | Medium | **P2** | I30 |
| Add links from case studies to department pages | Medium | Medium | **P2** | I31 |
| Add cross-links between comparison posts | Low | Medium | **P2** | I34 |
| Link new posts (Solo Founders, Vibe Coding) to existing content | Low | Medium | **P2** | I20, I22, I35 |
| Rewrite case study titles with keyword-first pattern (RS-10) | Low | Medium | **P2** | I29 |
| Update changelog meta description (RS-12) | Low | Low-Medium | **P2** | I16 |
| Add "solopreneur" to homepage | Low | Low-Medium | **P3** | I3 |
| Update brand guide agent count to 63 | Low | Low-Medium | **P3** | I4 |
| Rewrite blog index H1 (RS-6) | Low | Low | **P3** | I17 |
| Update Notion comparison pricing to evergreen phrasing | Low | Low | **P3** | I26 |
| Add "Notion AI" keyword to Notion comparison | Low | Low-Medium | **P3** | I27 |
| Add source citations to case study cost comparisons | Medium | Low-Medium | **P3** | I32 |
| Add external citations to Solo Founders post | Medium | Low-Medium | **P3** | I19 |
| Add Karpathy attribution to Vibe Coding post | Low | Low | **P3** | I23 |
| Replace "synthetic labor" and "soloentrepreneurs" on vision page | Low | Low | **P3** | I13, I14 |
| Add link from pricing page to comparison blog posts | Low | Low | **P3** | I12 |

---

## 8. Progress Since Last Audit (2026-03-23)

### New Content Since Last Audit

| Content | Assessment |
|---|---|
| "AI Agents for Solo Founders: The Definitive Guide" (2026-03-24) | EXCELLENT keyword targeting. Captures "AI agents for solo founders" -- a high-value commercial query. First appearance of "solopreneur" on the site (in FAQ). Strong structure with 6-question FAQ. |
| "Vibe Coding vs Agentic Engineering" (2026-03-24) | EXCELLENT keyword targeting. Directly captures the growing comparison query. Well-structured contrast format. Fills a gap identified in previous audits (I14 from 2026-03-23). |

### Fixed Since Last Audit

| 2026-03-23 Issue | Status |
|---|---|
| I14: Missing "vibe coding vs agentic engineering" heading/content | **ADDRESSED** -- Dedicated blog post now exists targeting this exact query |

### Still Open (Carried Over)

| 2026-03-23 Issue | Status | Current Issue # |
|---|---|---|
| C1: Homepage meta uses "plugin" | UNFIXED (8 days) | C1 |
| C2: Getting Started meta uses "plugin" | UNFIXED (8 days) | C2 |
| C3: Vision H1 is "Vision" | UNFIXED (8 days) | C3 |
| I1: Homepage H1 has zero keywords | UNFIXED | I1 |
| I2: "Open source" missing from homepage | UNFIXED | I2 |
| I3: "Solopreneur" missing from homepage | UNFIXED (partially addressed via blog) | I3 |
| I9: Skills H1/title mismatch | UNFIXED | I9 |
| I15 (now I24): Comparison titles missing "(2026)" | UNFIXED | I24 |
| I16 (now I25): "Claude Cowork" variant not captured | UNFIXED | I25 |
| I17 (now I26): Notion pricing will become stale | UNFIXED (39 days remain) | I26 |
| I18 (now I29): Case study titles lack "[Case Study]" | UNFIXED | I29 |
| I19 (now I30): No case study cross-links | UNFIXED | I30 |
| I20 (now I31): No case-study-to-department links | UNFIXED | I31 |
| I23 (now I34): No lateral linking between comparisons | UNFIXED | I34 |

### New Issues Since Last Audit

| Issue | Source |
|---|---|
| I18: Solo Founders post says "61 agents" (inconsistent with 63 elsewhere) | New post published with stale count |
| I19: Solo Founders post lacks external citations | New post observation |
| I20: Solo Founders post does not link to comparison posts | New post observation |
| I21: Vibe Coding post may lack page-specific meta description | New post observation |
| I22: Vibe Coding post does not link to Plateau post | New post observation |
| I23: Vibe Coding post lacks Karpathy attribution for "vibe coding" term | New post observation |
| I28: "Terminal-first" positioning in Cowork and Notion comparisons | Brand guide updated 2026-03-22; comparison posts not updated |
| I35: Two new posts orphaned from existing blog content | New content not cross-linked |

---

## 9. Readability Assessment Summary

| Page | Readability Grade | Notes |
|---|---|---|
| Homepage | EXCELLENT | Short sentences, declarative tone, generous whitespace. Brand voice at peak. Stats (8/63/59/infinity) are monumental. |
| Getting Started | GOOD | Clear step-by-step with code blocks. Workflow stages (brainstorm/plan/work/review/compound) well-enumerated. Example workflows helpful. |
| Agents | GOOD | Scannable 8-department sections with agent counts. Philosophy intro is clear. Department descriptions could carry more brand energy. |
| Skills | GOOD | Compound lifecycle well-explained. 5 category organization with counts. |
| Pricing | EXCELLENT | Two clear tiers. Competitor comparison table. FAQ addresses key objections directly. "Soleur is free. You pay for Claude. That's it." -- perfect brand voice. |
| Vision | MODERATE | Dense in places. Jargon-heavy ("AI Agent Swarms," "Recursive Dogfooding," "synthetic labor"). Milestones 2-3 shift from concrete to aspirational without transition. |
| Community | GOOD | Clean card layout with five channels. Contributing and Help sections actionable. |
| Changelog | GOOD | Chronological, bullet-point format. Frequent updates demonstrate active development. |
| Blog Index | GOOD | Clean article cards with dates and summaries. Chronological order. |
| CaaS Pillar Post | EXCELLENT | Best educational content. Clear definitions, comparison table, structured FAQ, industry citations. |
| Plateau Post | EXCELLENT | Best analytical content. Data tables, concrete percentages (30-96% reductions), three-era framework. |
| Solo Founders Guide (NEW) | EXCELLENT | Clear four-property framework. Eight-domain breakdown. Actionable getting-started steps. Strong FAQ. |
| Vibe Coding Comparison (NEW) | EXCELLENT | Clean side-by-side contrast. FAQ reinforces definitions. Accessible to non-technical readers. |
| Comparison Posts (3) | GOOD-EXCELLENT | Consistent structure. Side-by-side tables. Honest, non-adversarial assessments. |
| Case Studies (5) | GOOD | Consistent 5-section structure. Specific numbers throughout. Cost comparisons add concrete value. |

---

## 10. Overall Assessment

**Site content quality: HIGH.** The writing is consistently strong, on-brand, and well-structured. The two newest blog posts demonstrate excellent keyword targeting and fill previously identified gaps. The CaaS pillar post and Plateau post are standout content for both search and AI extraction.

**Primary concern: Three critical issues remain unfixed for 8+ days.** The "plugin" meta description violation on the two highest-traffic pages (homepage and Getting Started) directly contradicts the brand guide and misrepresents the product category in search results. The Vision page H1 wastes the most content-rich page's primary heading signal. These are low-effort, high-impact fixes.

**Secondary concern: Internal linking is the largest structural gap.** Content quality is high, but pages are isolated. Case studies do not link to each other or to department pages. Comparison posts do not link to each other. The two newest blog posts are not connected to the existing content they naturally relate to. Fixing internal linking requires no new content -- only adding contextual links between existing pages.

**Positive trend: Content velocity is increasing.** Two high-quality blog posts published on 2026-03-24. Both directly address keyword gaps identified in previous audits. The "AI Agents for Solo Founders" guide is the first page to use "solopreneur" -- a term absent from the entire site previously. The "Vibe Coding vs Agentic Engineering" comparison fills a gap flagged in the 2026-03-23 audit.

**Brand voice compliance: STRONG overall, with exceptions.** Homepage, agents, skills, pricing, and all blog posts maintain excellent brand voice alignment. Violations are concentrated in: (1) meta descriptions using "plugin," (2) the Vision page (off-brand vocabulary), and (3) two comparison posts using "terminal-first" positioning that was deprecated in the 2026-03-22 brand guide update.
