# Soleur.ai Content Audit Report

**Date:** 2026-03-17
**Scope:** 7 site pages + 8 blog posts (full site coverage excluding legal documents, which are compliance content and not subject to keyword optimization)
**Brand Guide:** `/home/runner/work/soleur/soleur/knowledge-base/marketing/brand-guide.md` (last updated 2026-02-21, last reviewed 2026-03-02)
**Note:** WebFetch returned 403 for all soleur.ai URLs (likely Cloudflare bot protection). Audit was performed against the local source files in `/home/runner/work/soleur/soleur/plugins/soleur/docs/`.

---

## 1. Target Keyword Universe

Keywords were derived from brand positioning, competitor landscape research, and search intent analysis.

| Keyword / Phrase | Search Intent | Relevance | Notes |
|---|---|---|---|
| company-as-a-service | Informational | HIGH | Category-defining term Soleur owns. Low competition -- emerging category. |
| CaaS platform | Informational / Navigational | HIGH | Abbreviation variant. Used in pillar article. |
| AI agents for solo founders | Commercial | HIGH | High-volume query in 2026. Direct ICP match. |
| AI agents for business | Commercial | HIGH | Broader version. Aligns with agents page. |
| one person billion dollar company | Informational | HIGH | Aspirational search tied to Amodei/Altman predictions. |
| Claude Code plugin | Navigational / Commercial | HIGH | Direct product discovery query. |
| agentic engineering | Informational | HIGH | Coined by Karpathy Feb 2026. Rising search volume. |
| compound engineering | Informational | MEDIUM | Niche but relevant. Every Inc. coined the term. |
| compound knowledge base | Informational | MEDIUM | Differentiator keyword. Low competition. |
| AI business operations platform | Commercial | MEDIUM | Broader commercial query. |
| open source AI agent platform | Commercial | MEDIUM | Competitive differentiator (vs. Cowork, Polsia). |
| Soleur vs Cowork | Commercial / Navigational | HIGH | Comparison query. Already has dedicated article. |
| Soleur vs Cursor | Commercial | HIGH | Competitor comparison. Partially addressed in FAQ. |
| AI legal document generator | Commercial | MEDIUM | Case study keyword. |
| AI competitive intelligence | Commercial | MEDIUM | Case study keyword. |
| solopreneur AI tools 2026 | Commercial | HIGH | High-volume trend query. Not targeted anywhere on site. |
| AI marketing for startups | Commercial | MEDIUM | Relevant but not addressed on site. |
| business validation AI | Commercial | MEDIUM | Case study keyword. |

---

## 2. Per-Page Analysis

### 2.1 Homepage (`/home/runner/work/soleur/soleur/plugins/soleur/docs/index.njk`)

**URL:** `https://soleur.ai/` (renders as `index.html`)

| Attribute | Assessment |
|---|---|
| **Title tag** | `Soleur - The Company-as-a-Service Platform` |
| **Meta description** | "Soleur is the company-as-a-service platform -- a Claude Code plugin that gives solo founders a full AI organization across every business department." |
| **H1** | "Build a Billion-Dollar Company. Alone." |
| **Detected target keywords** | company-as-a-service, solo founders, AI agents, Claude Code plugin, AI organization |
| **Keyword alignment** | STRONG. Meta description hits primary keyword, product type, and audience in one sentence. H1 captures aspirational search intent. |
| **Search intent match** | Mixed navigational/commercial. Correctly addresses "what is this product and who is it for." |
| **Readability** | STRONG. Short sentences, punchy copy, declarative tone. Matches brand voice exactly. |
| **FAQ section** | Present. 6 questions with FAQPage JSON-LD schema. Questions align well with common queries. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | H1 is aspirational but not keyword-rich | H1 "Build a Billion-Dollar Company. Alone." is powerful brand copy but contains zero target keywords. Search engines weight H1 heavily. The keyword "company-as-a-service" appears only in H2 and meta description, not H1. |
| IMPROVEMENT | "Claude Code plugin" in meta description violates brand guide | Brand guide explicitly says: "Do not call it a 'plugin' or 'tool' in public-facing content -- it is a platform." The meta description says "a Claude Code plugin." This is the highest-traffic meta description on the site. |
| IMPROVEMENT | Missing keyword: "solopreneur" | The word "solopreneur" does not appear anywhere on the homepage despite being a high-volume search term in 2026 (41.8M solopreneurs in the US). "Solo founders" is used, but "solopreneur" captures a broader audience. |
| IMPROVEMENT | Missing keyword: "open source" | The homepage does not mention that Soleur is open source. This is a key differentiator against Cowork, Polsia, and Cursor. Searchers query "open source AI agent platform." |

---

### 2.2 Getting Started (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/getting-started.md`)

**URL:** `https://soleur.ai/pages/getting-started.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Getting Started with Soleur - Soleur` |
| **Meta description** | "Install the Soleur Claude Code plugin and start running your company-as-a-service -- AI agents for engineering, marketing, legal, finance, and more." |
| **H1** | "Getting Started with Soleur" |
| **Detected target keywords** | company-as-a-service, Claude Code plugin, AI agents, AI organization |
| **Keyword alignment** | GOOD. Meta description is keyword-rich. Body content covers key terms naturally. |
| **Search intent match** | Transactional (how to install/use). Correct match. |
| **Readability** | GOOD. Clear step-by-step structure. Code blocks for install commands. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | Meta description says "Claude Code plugin" | Same brand guide violation. This is the transactional landing page -- the page most likely to be the entry point from search. |
| IMPROVEMENT | Subtitle says "Install the Claude Code plugin" | Line 12: "Install the Claude Code plugin that gives you a full AI organization." Brand guide violation. |
| IMPROVEMENT | No FAQ section | The getting-started page answers implicit questions ("what is Soleur?", "how do I install it?", "what can it do?") but does not structure them as FAQs. Adding FAQPage schema would increase SERP real estate. |
| IMPROVEMENT | Missing time-to-value statement in meta description | Meta description does not communicate speed. Adding "in under 5 minutes" or "one command" would improve CTR from search results. |

---

### 2.3 Agents (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/agents.njk`)

**URL:** `https://soleur.ai/pages/agents.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Soleur AI Agents - Soleur` |
| **Meta description** | "AI agents for business -- engineering, marketing, legal, finance, operations, product, sales, and support. Each agent is a specialist in the Soleur company-as-a-service platform." |
| **H1** | "Soleur AI Agents" |
| **Detected target keywords** | AI agents, AI agents for business, company-as-a-service, agentic engineering |
| **Keyword alignment** | STRONG. Meta description is the best on the site -- keyword-rich, specific, hits "AI agents for business" exactly. |
| **Search intent match** | Commercial investigation. Someone researching AI agent platforms. Correct match. |
| **Readability** | GOOD. Intro paragraph explains agentic engineering and cross-domain coherence clearly. |
| **FAQ section** | Present. 3 questions with relevant content. Missing JSON-LD FAQPage schema. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | FAQ section missing JSON-LD schema | The agents page has an FAQ section (3 questions) but no `<script type="application/ld+json">` block for FAQPage. The homepage and blog posts have this schema. This page is the most commercially valuable -- FAQ rich snippets would increase SERP visibility. |
| IMPROVEMENT | Missing keyword: "open source AI agents" | The agents page does not mention that these agents are open source and inspectable. This differentiates from Cowork and is a search query ("open source AI agents"). |
| IMPROVEMENT | Body text uses "agentic engineering" without defining it | The term "agentic engineering" is used in the intro but not defined. A clear one-sentence definition near first usage would improve AI-extractability and serve the informational search intent for this term. |

---

### 2.4 Skills (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/skills.njk`)

**URL:** `https://soleur.ai/pages/skills.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Agentic Engineering Skills - Soleur` |
| **Meta description** | "Multi-step workflow skills for the Soleur platform -- from feature development and code review to content writing, deployment, and agentic engineering." |
| **H1** | "Agentic Engineering Skills" |
| **Detected target keywords** | agentic engineering, workflow skills, code review, deployment |
| **Keyword alignment** | MODERATE. Targets "agentic engineering" well but misses commercial keywords. Someone searching "AI workflow automation" or "AI business workflows" would not find this page. |
| **Search intent match** | Informational / navigational. Correct for product documentation. |
| **Readability** | GOOD. Clear compound engineering lifecycle explanation. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title and H1 say "Agentic Engineering Skills" -- generic | The H1 does not include "Soleur" or "AI" which are necessary for SERP differentiation. "Agentic Engineering Skills" as a standalone title could describe any product. |
| IMPROVEMENT | No FAQ section | No FAQ content or schema. Common questions like "What is a skill in Soleur?" or "How do skills differ from agents?" are not addressed. |
| IMPROVEMENT | Missing keyword: "AI workflow automation" | The concept of multi-step automated workflows is described but the commercially-searched term "AI workflow automation" is absent. |

---

### 2.5 Vision (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/vision.njk`)

**URL:** `https://soleur.ai/pages/vision.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Vision - Soleur` |
| **Meta description** | "Where Soleur is headed. The Company-as-a-Service platform that gives solo founders the leverage of a full organization." |
| **H1** | "Vision" |
| **Detected target keywords** | company-as-a-service, solo founder, model-agnostic, AI organization |
| **Keyword alignment** | MODERATE. Meta description is good. H1 is a single generic word with no keyword value. |
| **Search intent match** | Navigational (existing users). This page does not capture search traffic. |
| **Readability** | MODERATE. Dense paragraphs. Some sentences are long and complex. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | H1 is "Vision" -- zero keyword value | A one-word H1 provides no search signal. This should be descriptive: "Soleur Vision: The Company-as-a-Service Platform for Solo Founders" or similar. |
| IMPROVEMENT | Uses terms not aligned with brand voice | "Soloentrepreneurs" (not standard), "synthetic labor", "CEO Dashboard" -- none of these appear in the brand guide. "Synthetic labor" in particular may alienate the target audience. |
| IMPROVEMENT | No FAQ section | Vision content would benefit from FAQs: "What is Soleur's roadmap?", "Is Soleur model-agnostic?", "What is company-as-a-service?" |
| IMPROVEMENT | "Billion-Dollar Solopreneur" card title | Good keyword inclusion but inconsistent with homepage which uses "solo founders" exclusively. |

---

### 2.6 Community (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/community.njk`)

**URL:** `https://soleur.ai/pages/community.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Community - Soleur` |
| **Meta description** | "Join the Soleur community. Connect on Discord, contribute on GitHub, get help, and learn about our community guidelines." |
| **H1** | "Community" |
| **Detected target keywords** | Soleur (only) |
| **Keyword alignment** | WEAK. No target keywords in H1 or meta description besides brand name. |
| **Search intent match** | Navigational. Correct for existing users. |
| **Readability** | GOOD. Clear structure with cards. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | No keywords in content | Community page is pure navigation. Adding a paragraph about "the Soleur open-source community for solo founders building with AI agents" would add keyword context without changing the page's purpose. |

---

### 2.7 Changelog (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/changelog.njk`)

**URL:** `https://soleur.ai/pages/changelog.html`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Changelog - Soleur` |
| **Meta description** | "Changelog - All notable changes to Soleur." |
| **H1** | "Changelog" |
| **Readability** | Content is dynamically generated from `changelog.js` |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Meta description is a repeat of the title | "Changelog - All notable changes to Soleur" is identical to the title. This wastes the meta description's SERP real estate. |

---

### 2.8 Blog Index (`/home/runner/work/soleur/soleur/plugins/soleur/docs/pages/blog.njk`)

**URL:** `https://soleur.ai/blog/`

| Attribute | Assessment |
|---|---|
| **Title tag** | `Blog - Soleur` |
| **Meta description** | "Insights on agentic engineering, company-as-a-service, and building at scale with AI teams." |
| **H1** | "Blog" |
| **Keyword alignment** | MODERATE. Meta description hits key terms. H1 is generic. |
| **Readability** | N/A -- listing page. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | H1 is "Blog" -- no keyword value | Should be "Soleur Blog: Agentic Engineering and Company-as-a-Service" or similar. |

---

## 3. Blog Post Analysis

### 3.1 "What Is Company-as-a-Service?" (`what-is-company-as-a-service.md`)

| Attribute | Assessment |
|---|---|
| **Meta description** | "Company-as-a-Service is a new model where AI agents run every business department. Learn what CaaS means, how it works, and why it matters for solo founders." |
| **Keyword alignment** | EXCELLENT. Pillar content. Targets "company-as-a-service", "CaaS", "AI agents", "solo founders". |
| **Search intent** | Informational. Perfectly matches "what is company-as-a-service" query. |
| **Readability** | EXCELLENT. Well-structured with H2/H3 hierarchy, comparison table, FAQ section with JSON-LD. |
| **Citations** | STRONG. Bureau of Labor Statistics, TechCrunch, CNBC, VentureBeat, Inc.com, Fortune -- 10+ authoritative external citations. |
| **FAQ** | 5 questions with JSON-LD schema. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Missing keyword: "one person billion dollar company" | The article discusses this concept at length but the exact phrase does not appear as a heading or in the first paragraph. This is a high-volume search query. |

---

### 3.2 "Why Most Agentic Engineering Tools Plateau" (`why-most-agentic-tools-plateau.md`)

| Attribute | Assessment |
|---|---|
| **Meta description** | "Most AI coding tools stop getting better after week two. The missing layer is compound knowledge -- a system that learns from every task and feeds those learnings back into its own rules, agents, and workflows." |
| **Keyword alignment** | STRONG. Targets "agentic engineering", "compound knowledge", "AI coding tools". |
| **Search intent** | Informational. Matches "why AI coding tools plateau" and "compound engineering." |
| **Readability** | EXCELLENT. Best-written article on the site. Data tables, concrete examples, comparison matrix. |
| **Citations** | STRONG. Karpathy tweets, GitHub repos, Tessl funding, competitor products cited. |
| **FAQ** | 3 FAQs at bottom but NO JSON-LD FAQPage schema. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | FAQ section missing JSON-LD schema | Three well-written FAQ entries exist but lack the JSON-LD block. The CaaS article and Cowork comparison have it. This is the second-most important blog post. |
| IMPROVEMENT | Comparison table missing Polsia and Tanka | New competitors have emerged since publication. |
| IMPROVEMENT | Missing keywords: "vibe coding vs agentic engineering" | The article explains both but does not use the exact comparison phrase as a heading. |

---

### 3.3 "Soleur vs. Anthropic Cowork" (`2026-03-16-soleur-vs-anthropic-cowork.md`)

| Attribute | Assessment |
|---|---|
| **Meta description** | "Soleur and Anthropic Cowork both deploy multi-domain AI agents. A direct comparison of knowledge architecture, workflow depth, cross-domain coherence, and pricing." |
| **Keyword alignment** | STRONG. Targets "Soleur vs Cowork", "AI agent platform", "solo founders". |
| **Search intent** | Commercial comparison. Correct match. |
| **Readability** | EXCELLENT. Side-by-side table, clear sections, honest assessment of both platforms. |
| **Citations** | STRONG. TechCrunch, The Decoder, Claude pricing page cited. |
| **FAQ** | 5 questions with JSON-LD schema. |

**Issues:**

| Priority | Issue | Detail |
|---|---|---|
| IMPROVEMENT | Title does not include "2026" | Comparison articles date quickly. Including "2026" captures dated search queries and signals freshness. |

---

### 3.4 Case Studies (5 posts)

All five case studies follow the same structure: problem, AI approach, result, cost comparison, compound effect. Consistent, well-written, on-brand.

**Shared issues across all case studies:**

| Priority | Issue | Detail |
|---|---|---|
| CRITICAL | No FAQ sections on any case study | All 5 case studies lack FAQ sections and JSON-LD schema. Each case study naturally invites questions. Adding 3-5 FAQs per post would significantly increase SERP real estate. |
| IMPROVEMENT | No "Case Study" in titles | The frontmatter tags include "case-study" but the titles do not contain the phrase. Searchers query "AI agent case study." |
| IMPROVEMENT | Missing internal links between case studies | Case studies do not link to each other. |

---

## 4. Issues Summary (Prioritized)

### Critical Issues (Block Discoverability)

| # | Page | Issue | Impact |
|---|---|---|---|
| C1 | Agents page | FAQ section missing JSON-LD schema | Loses FAQ rich snippets on the most commercially valuable product page |
| C2 | "Why Most Agentic Tools Plateau" | FAQ section missing JSON-LD schema | Loses FAQ rich snippets on the highest-authority blog post |
| C3 | All 5 case studies | No FAQ sections at all | 5 pages with zero chance of FAQ rich snippets |
| C4 | Vision page | H1 is "Vision" -- zero keyword value | Largest content page has a 1-word H1 |
| C5 | Homepage + Getting Started | Meta description and subtitle use "plugin" | Highest-traffic pages violate brand guide |

### Improvement Issues (Enhance Ranking)

| # | Page | Issue | Impact |
|---|---|---|---|
| I1 | Homepage | H1 has zero target keywords | Search engines do not weight the aspirational headline |
| I2 | Homepage | "open source" not mentioned | Misses "open source AI agent platform" search query |
| I3 | Homepage | "solopreneur" not mentioned | Misses high-volume variant of "solo founder" |
| I4 | Skills page | H1 has no brand identifier | Generic, could describe any product |
| I5 | Blog index | H1 is "Blog" | Generic |
| I6 | Changelog | Meta description duplicates title | Wasted SERP real estate |
| I7 | Case studies | No internal cross-links | Misses internal linking value |
| I8 | "Agentic Tools Plateau" | Comparison table missing Polsia, Tanka | Table appears dated |
| I9 | Cowork comparison | Title missing "2026" | Comparison articles expire |
| I10 | Case study titles | Missing "AI" and "Case Study" | Titles are narrative, not search-optimized |
| I11 | Vision page | Uses "synthetic labor," "soloentrepreneurs" | Not in brand guide vocabulary |
| I12 | Community page | No keyword context | Pure navigation with no keyword-bearing text |

---

## 5. Rewrite Suggestions

All suggestions aligned with the brand voice: bold, declarative, forward-looking, precise.

### RS-1: Homepage Meta Description

**Current:** "Soleur is the company-as-a-service platform -- a Claude Code plugin that gives solo founders a full AI organization across every business department."

**Suggested:** "Soleur is the open-source company-as-a-service platform -- a full AI organization that gives solo founders and solopreneurs agents across every business department."

**Rationale:** Removes "Claude Code plugin" (brand guide violation). Adds "open source" and "solopreneurs."

### RS-2: Getting Started Meta Description

**Current:** "Install the Soleur Claude Code plugin and start running your company-as-a-service -- AI agents for engineering, marketing, legal, finance, and more."

**Suggested:** "Get started with Soleur in one command. Deploy AI agents for engineering, marketing, legal, finance, and every business department -- the company-as-a-service platform for solo founders."

### RS-3: Getting Started Subtitle

**Current:** "Install the Claude Code plugin that gives you a full AI organization."

**Suggested:** "One command. A full AI organization across every department."

### RS-4: Vision Page H1

**Current:** "Vision"

**Suggested:** "The Soleur Vision: Building the Company-as-a-Service Platform"

### RS-5: Skills Page H1

**Current:** "Agentic Engineering Skills"

**Suggested:** "Soleur Skills: Agentic Engineering Workflows"

### RS-6: Blog Index H1

**Current:** "Blog"

**Suggested:** "Soleur Blog"

### RS-7: Changelog Meta Description

**Current:** "Changelog - All notable changes to Soleur."

**Suggested:** "Every release, feature, and fix in the Soleur company-as-a-service platform. Track what shipped across agents, skills, and workflows."

### RS-8: Cowork Comparison Title

**Current:** "Soleur vs. Anthropic Cowork: Which AI Agent Platform Is Right for Solo Founders?"

**Suggested:** "Soleur vs. Anthropic Cowork (2026): Which AI Agent Platform Is Right for Solo Founders?"

---

## 6. Priority Fix Matrix

| Fix | Effort | Impact | Priority |
|---|---|---|---|
| Add JSON-LD FAQPage schema to agents page | Low | High | P1 |
| Add JSON-LD FAQPage schema to agentic tools blog post | Low | High | P1 |
| Remove "plugin" from homepage and getting-started meta descriptions | Low | High | P1 |
| Add FAQ sections to all 5 case studies | Medium | High | P1 |
| Rewrite Vision page H1 | Low | Medium | P2 |
| Add "open source" to homepage | Low | Medium | P2 |
| Add agentic engineering definition to agents page | Low | Medium | P2 |
| Rewrite Skills page H1 | Low | Low-Medium | P2 |
| Add "(2026)" to Cowork comparison title | Low | Low-Medium | P3 |
| Add internal cross-links between case studies | Medium | Medium | P2 |
| Rewrite changelog meta description | Low | Low | P3 |
| Add keyword context to community page subtitle | Low | Low | P3 |
| Add "solopreneur" to homepage | Low | Low-Medium | P3 |

---

**Sources consulted for keyword research and competitive landscape:**
- [How AI Tools Are Letting Solo Founders Build Empires in 2026](https://www.siliconindia.com/news/startups/how-ai-tools-are-letting-solo-founders-build-empires-in-2026-nid-238909-cid-19.html)
- [Polsia: Solo Founder Hits $1M ARR](https://www.teamday.ai/ai/polsia-solo-founder-million-arr-self-running-companies)
- [Best AI Agents for Solo Founders in 2026](https://www.tldl.io/resources/best-ai-agents-for-solo-founders)
- [Compound Engineering by Every Inc.](https://every.to/guides/compound-engineering)
- [2026 Agentic Coding Trends Report - Anthropic](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf?hsLang=en)
- [What is Agentic Engineering - Glide](https://www.glideapps.com/blog/what-is-agentic-engineering)
- [The One-Person Unicorn Guide 2026](https://www.nxcode.io/resources/news/one-person-unicorn-context-engineering-solo-founder-guide-2026)
- [AI Tools for Solo Founders: Complete Stack Guide](https://padron.sh/blog/ai-tools-solo-founders-complete-stack-guide/)
