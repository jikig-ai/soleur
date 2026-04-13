# Soleur.ai Prioritized Content Plan

**Date:** 2026-04-13
**Inputs:** Content audit (2026-04-13), AEO audit (2026-04-13), SEO audit (2026-04-13), keyword research (2026-04-13), competitor analysis
**Previous plan:** `knowledge-base/marketing/audits/soleur-ai/2026-03-25-content-plan.md`
**Brand guide:** `knowledge-base/marketing/brand-guide.md` (last reviewed 2026-03-26)

---

## Table of Contents

1. [Key Findings Summary](#1-key-findings-summary)
2. [Keyword Research Results](#2-keyword-research-results)
3. [Competitive Gap Analysis](#3-competitive-gap-analysis)
4. [Content Architecture (Pillar/Cluster Model)](#4-content-architecture-pillarcluster-model)
5. [Prioritized Content Actions](#5-prioritized-content-actions)
6. [Scoring Matrix](#6-scoring-matrix)
7. [Searchable vs. Shareable Content Balance](#7-searchable-vs-shareable-content-balance)
8. [Methodology](#8-methodology)

---

## 1. Key Findings Summary

### 1.1 Content Audit Findings (Score: 6/10)

| Dimension | Score | Key Issue |
|---|---|---|
| Keyword Alignment | 5/10 | Core brand terms well-used; commercial/transactional keywords missing from headings and titles |
| Search Intent Match | 6/10 | Blog posts match informational intent; core pages miss navigational/commercial intent |
| Readability | 8/10 | Clear, direct prose; appropriate for target audience |
| Content Depth | 8/10 | Blog posts substantive (2,000-3,000 words); case studies effective but shorter |
| Internal Linking | 4/10 | No pillar/cluster structure; no topic hubs; blog posts link to core pages but not to each other |
| FAQ/AEO Readiness | 7/10 | FAQ sections on most pages; some answers too long for AI extraction |
| E-E-A-T Signals | 4/10 | No author bylines, no expert credentials, no external citations on most core pages |

**Critical blockers identified:**

- C1: Homepage title tag is a tagline, not a keyword-bearing title
- C2: Homepage H1 targets no search query
- C3: "Company-as-a-Service" absent from homepage title, H1, and meta description
- C4: Blog index has no categorization, tags, or topic clusters
- C5: No author bylines or expert attribution on blog posts
- C6: No internal linking strategy between related blog posts

### 1.2 AEO Audit Findings (Score: 66/100, Grade C+)

| Category | Score | Grade |
|---|---|---|
| FAQ Structure & Schema | 88 | A |
| Source Citations | 62 | D |
| Statistics & Specificity | 75 | B |
| Conversational Readiness | 60 | D |
| Definition Extractability | 72 | B- |
| Summary Quality | 58 | D |
| Authority Signals (E-E-A-T) | 52 | F |
| Presence & Third-Party Mentions | 40 | F |

**Core-vs-blog quality gap:** Blog posts average 69/100; core pages average 46/100. This 23-point gap means AI engines will cite blog posts and ignore the primary site pages.

**Worst performers:** About page (32/F), Blog index (30/F), Community (37/F), Changelog (41/F).

**Best performers:** "What Is CaaS?" blog (92/A), "AI Agents for Solo Founders" (90/A), "Why Most Agentic Tools Plateau" (85/A).

### 1.3 SEO Audit Findings (Score: 91/100, Grade A)

**Major improvement:** Score jumped from 72 (B-) to 91 (A) since the 2026-03-25 audit. The critical meta tag rendering issue is fully resolved. Structured data, meta tags, AI discoverability, sitemap, and Core Web Vitals all score 5/5.

**Remaining issues:**

- About page lacks author credentials and bio (Medium severity)
- Only 1 of 16 blog posts has distinct dateModified (Medium-Low)
- Heading hierarchy issues on homepage and getting-started page (Low-Medium)
- `<base href="/">` tag still present (Low)
- `<html lang="en">` vs `en-US` inconsistency (Low)
- All blog posts use same generic OG image (Low)
- No visible contact information on main pages (Low)

### 1.4 Cross-Audit Synthesis

The three audits converge on five themes:

| Theme | Content Audit | AEO Audit | SEO Audit |
|---|---|---|---|
| **Homepage keyword void** | H1 and title miss all target keywords | No extractable product definition for AI models | Title tag functional but wastes keyword space |
| **E-E-A-T deficit** | No author bylines on blog posts | Authority signals score 52/F | About page lacks bio/credentials |
| **Core page weakness** | Core pages thin on depth, keywords | Core pages average 46/100 vs. blog 69/100 | Heading hierarchy issues on 2 core pages |
| **No third-party validation** | All case studies are self-referential | Presence score 40/F; zero external reviews | No press section, no contact info |
| **Missing internal linking** | No pillar/cluster structure | Blog index scores 30/F with no topic organization | Blog index has no structured navigation |

---

## 2. Keyword Research Results

### 2.1 Primary Keywords

| Keyword / Phrase | Search Intent | Volume Signal | Relevance | Competition | Status on Site |
|---|---|---|---|---|---|
| claude code plugin | Navigational / Commercial | HIGH | HIGH | Medium-High | Present in meta descriptions only. Brand guide prohibits "plugin" in marketing copy (exception: CLI commands, legal, technical docs). 101 plugins in ecosystem (33 Anthropic, 68 partner). Multiple "best plugins 2026" listicles -- Soleur absent from all. |
| agentic engineering | Informational | VERY HIGH | HIGH | High | Skills page H1, plateau blog post, vibe coding comparison. Mainstream in 2026: dedicated ICSE workshop (AGENT 2026), AgentEng 2026 conference in London, ACM CAIS 2026. 96% of organizations using AI agents. CIO: "shift from prompt engineering to orchestration." |
| AI company automation | Commercial | HIGH | HIGH | Medium | Concept described across pages but exact phrase absent from any heading. 41.8M solopreneurs in US contributing $1.3T. 64% say business would not have grown without AI. $3K-12K/year typical stack cost. |
| solo founder AI tools | Commercial | HIGH | HIGH | High | "Solo founder" used consistently; "AI tools" phrasing absent from headings. 12+ listicle articles in SERP. Typical recommended stack: Cursor + Claude + ChatGPT + Canva + Zapier at $300-500/mo. Soleur appears on zero listicles. |
| company-as-a-service | Informational | Low-Medium | HIGH | Very Low | Strong coverage (pillar post, homepage, vision, comparisons). Soleur still owns this term. SERP returns AIaaS/SaaS content from Microsoft, IBM, Zendesk -- no competing CaaS product. Window remains open but narrowing as Polsia, Twin, Junior emerge. |
| one person billion dollar company | Informational | VERY HIGH | HIGH | High | Discussed in vision and homepage but no dedicated page targeting this exact query. Dario Amodei gave 70-80% odds for 2026. Fortune, TechCrunch, NxCode all published dedicated articles. Base44 sold to Wix for $80M in 6 months as a solo operation. |
| vibe coding vs agentic engineering | Informational / Commercial | HIGH | HIGH | Medium | Dedicated blog post exists. Karpathy coined both terms. The New Stack, NxCode, Turing College, arXiv papers (GLM-5) cover the topic. Soleur post exists but lacks inline source citations. |
| open source AI agent platform | Commercial | MEDIUM-HIGH | HIGH | High | "Open source" barely appears on site. CrewAI (44.3K stars, 5.2M monthly downloads), LangGraph (24.8K stars), AutoGen (54.6K stars) dominate. Soleur is Apache 2.0 but does not position in this category. |

### 2.2 Secondary Keywords

| Keyword / Phrase | Search Intent | Volume Signal | Relevance | Competition |
|---|---|---|---|---|
| AI agents for small business | Commercial | HIGH | MEDIUM | High |
| how to run a company with AI | Informational | HIGH | HIGH | High |
| AI co-founder tools | Commercial | MEDIUM | HIGH | Medium |
| solopreneur tech stack 2026 | Commercial | MEDIUM-HIGH | HIGH | Medium |
| AI business operations platform | Commercial | MEDIUM | HIGH | Medium |
| compound engineering | Informational | MEDIUM-HIGH | HIGH | Low-Medium |
| self-running company AI | Informational | Low-Medium | HIGH | Low |
| context engineering | Informational | MEDIUM-HIGH | HIGH | Medium |
| AI workflow automation | Commercial | VERY HIGH | MEDIUM | Very High |
| best Claude Code plugins 2026 | Commercial | MEDIUM | HIGH | Medium |
| Soleur vs Devin | Commercial | Low-Medium | HIGH | Very Low |
| Soleur vs GitHub Copilot | Commercial | Low-Medium | HIGH | Very Low |
| AI agent framework comparison | Commercial | MEDIUM | MEDIUM | Medium |
| revenue per employee AI | Informational | MEDIUM | HIGH | Low |

### 2.3 Emerging Keywords (Monitor)

| Keyword / Phrase | Search Intent | Notes |
|---|---|---|
| agent sandboxing 2026 | Informational | Anthropic "year of trust." 80% adoption but trust dropped to 29%. |
| agentic AI cost optimization | Commercial | Heterogeneous model architectures becoming standard. |
| multi-agent orchestration | Commercial | Gartner: 1,445% surge in inquiries. CrewAI and LangGraph lead. |
| PEV loop (Plan Execute Verify) | Informational | Competing with compound engineering's Plan-Work-Review-Compound loop. |
| AI native SaaS | Informational | SaaS-to-AI transformation. Adjacent to CaaS positioning. |
| one person unicorn | Informational | Variant of "one person billion dollar company." Fortune, NxCode use this phrase. |

### 2.4 Intent Classification Summary

| Intent Type | Keywords Count | Site Coverage | Gap |
|---|---|---|---|
| Informational | 9 | 6 partially covered | "How to run a company with AI," "context engineering" unaddressed |
| Commercial / Investigation | 10 | 5 partially covered | "Best Claude Code plugins," "AI agent framework comparison," "Soleur vs Devin," "Soleur vs Copilot" unaddressed |
| Navigational | 2 | 1 partially covered | "Claude code plugin" underoptimized; "Soleur review" unaddressed |
| Transactional | 1 | 1 (pricing page) | Pricing page functional but all tiers "Coming Soon" |

---

## 3. Competitive Gap Analysis

### 3.1 Direct Competitors

| Competitor | Content Strength | Content Weakness | Soleur's Opportunity |
|---|---|---|---|
| **Polsia** | "AI that runs your company while you sleep." Product Hunt presence. $29/mo. Alternatives articles on SourceForge, Toolify, Slashdot, Findstack. Review ecosystem forming. | Fully autonomous (no human-in-the-loop). No educational content. No blog. Trust concerns from reviewers. | Soleur comparison post exists. Human-in-the-loop differentiator is strong. Update post with current Polsia reviews citing trust issues. New competitors Twin, Junior, Viktor, OctoClaw entering CaaS space -- Soleur should cover these emerging entrants. |
| **Cursor** | $2B+ ARR. 30+ marketplace plugins. Parallel agents. Multiple "vs" articles from third parties. | Coding-only. No cross-department capability. No knowledge compounding. Billing trust issues. | Comparison post exists and is strong. Update with $2B ARR milestone and parallel agent capabilities. |
| **Anthropic Cowork** | TechCrunch, The Decoder coverage. Enterprise-focused. Microsoft Copilot Cowork partnership. Department-specific plugins. | No blog. No educational content. No solo founder messaging. No open-source story. | Comparison post exists. Update with department-specific plugin additions. |
| **CrewAI / LangGraph / AutoGen** | Dominant in open-source agent SERP. CrewAI: 44.3K stars, 5.2M monthly downloads. LangGraph: 24.8K stars. AutoGen: 54.6K stars (now maintenance mode, merged into Microsoft Agent Framework). | Developer frameworks, not business platforms. No solo founder targeting. 4-8 weeks to production. | "AI Agent Platform vs Framework" explainer is a major gap. Soleur: one command install. Frameworks: months of integration. AutoGen's deprecation creates an opening. |
| **Twin / Junior / Viktor / OctoClaw** | Emerging CaaS competitors. Twin enables "fully autonomous agents" for business operations. Junior creates AI "employees" with own email accounts. Viktor lives in Slack. | New entrants, small user bases. Limited content/SEO presence. No established brand. | Cover in a "CaaS Landscape 2026" roundup. Position Soleur as the open-source, human-in-the-loop alternative to fully autonomous competitors. |
| **Lindy AI / Gumloop** | Rank for "AI agent platform." Lindy: no-code, top-ranked for small business. Gumloop: $17M Series A with 2 staff. | No compound knowledge. Individual task agents, not departmental orchestration. | Include in comparison tables. Gumloop's story validates solo-operator-at-scale thesis. |
| **Make / Zapier / n8n** | Dominate "AI workflow automation." Zapier: 7,000+ app integrations. Make: added agentic automation features. n8n: open source. | Workflow automation, not agentic intelligence. No learning/compounding. Rule-based at core. | Content distinguishing agent orchestration from workflow automation. |

### 3.2 Listicle Presence Gap (CRITICAL -- unchanged since March 17)

Soleur appears on **zero** of the following high-traffic listicle types:

- "Best AI agents for solo founders 2026" (Entrepreneur, SiliconIndia, GREY Journal, NxCode, EntrepreneurLoop)
- "Best Claude Code plugins 2026" (Felo, DevOps Daily, self.md, buildtolaunch)
- "Best AI agent platforms 2026" (Gumloop, Marketer Milk, Kore.ai, Lindy, Vellum)
- "AI tools for solopreneurs 2026" (browse-ai.tools, soloa.ai, creativetoolsai)
- "Solopreneur tech stack 2026" (PrometAI, DEV Community, EntrepreneurLoop)
- "One person company AI tools" (Taskade, NxCode, solobusinesshub)

**Impact:** High-intent commercial queries route entirely to competitors. Soleur is invisible in the discovery phase where buyers evaluate options.

**Recommended action:** Outreach to listicle authors (see P1-10 below). Simultaneously create own "Best X" content to compete in SERP.

### 3.3 Content Volume Comparison

| Competitor | Blog Posts | Comparison Posts | Case Studies | Technical Guides |
|---|---|---|---|---|
| Soleur | 16 | 5 | 5 | 2 |
| Cursor (blog.cursor.com) | 30+ | 0 | 3 | 10+ |
| CrewAI (crewai.com/blog) | 50+ | 5+ | 10+ | 20+ |
| Lindy (lindy.ai/blog) | 40+ | 10+ | 5+ | 15+ |
| Polsia | 0 | 0 | 0 | 0 |

Soleur's content volume is competitive given team size (1 founder). Quality is high. The gap is in coverage breadth (missing keyword targets) and distribution (zero listicle presence).

---

## 4. Content Architecture (Pillar/Cluster Model)

### Pillar 1: Company-as-a-Service (CaaS)

**Pillar page:** "What Is Company-as-a-Service?" (existing, `/blog/what-is-company-as-a-service/`)

| Cluster Page | Status | Target Keyword | Link to Pillar | Link to Sibling |
|---|---|---|---|---|
| AI Agents for Solo Founders | Existing | AI agents solo founders | Yes (add) | Link to CaaS pillar, vibe coding post |
| Soleur vs. Polsia | Existing | CaaS comparison | Yes (add) | Link to CaaS pillar, vs. Paperclip |
| Soleur vs. Paperclip | Existing | zero-human company | Yes (add) | Link to CaaS pillar, vs. Polsia |
| How to Run a Company with AI [NEW] | To create | how to run company with AI | Yes | Link to AI Agents guide, CaaS pillar |
| CaaS Landscape 2026 [NEW] | To create | company-as-a-service platforms | Yes | Link to each vs. post |
| The One-Person Billion-Dollar Company [NEW] | To create | one person billion dollar company | Yes | Link to AI Agents guide, vision page |

### Pillar 2: Agentic Engineering

**Pillar page:** "Vibe Coding vs Agentic Engineering" (existing, `/blog/vibe-coding-vs-agentic-engineering/`)

| Cluster Page | Status | Target Keyword | Link to Pillar | Link to Sibling |
|---|---|---|---|---|
| Why Most Agentic Tools Plateau | Existing | agentic engineering tools | Yes (add) | Link to pillar, compound engineering |
| Credential Helper Isolation | Existing | agent sandboxing | Yes (add) | Link to pillar, codebase integration |
| Codebase Integration | Existing | AI team codebase | Yes (add) | Link to pillar, credential helper |
| Agentic Engineering: The Definitive Guide [NEW] | To create | agentic engineering guide 2026 | Yes | Link to all cluster pages |
| Context Engineering for Solo Founders [NEW] | To create | context engineering | Yes | Link to pillar, compound engineering post |
| AI Agent Platform vs Framework [NEW] | To create | AI agent framework comparison | Yes | Link to pillar, getting started |

### Pillar 3: Soleur vs. Competitors

**Pillar page:** Blog index with "Soleur vs. Competitors" category section (to create)

| Cluster Page | Status | Target Keyword | Link to Pillar | Link to Sibling |
|---|---|---|---|---|
| Soleur vs. Cursor | Existing | Soleur vs Cursor | Yes (add) | Link to vs. Copilot |
| Soleur vs. Anthropic Cowork | Existing | Soleur vs Cowork | Yes (add) | Link to vs. Cursor |
| Soleur vs. Notion Custom Agents | Existing | Soleur vs Notion | Yes (add) | Link to vs. Cowork |
| Soleur vs. Polsia | Existing | Soleur vs Polsia | Yes (add) | Link to vs. Paperclip |
| Soleur vs. Paperclip | Existing | Soleur vs Paperclip | Yes (add) | Link to vs. Polsia |
| Soleur vs. Devin [NEW] | To create | Soleur vs Devin | Yes | Link to vs. Cursor, vs. Copilot |
| Soleur vs. GitHub Copilot [NEW] | To create | Soleur vs Copilot | Yes | Link to vs. Cursor, vs. Devin |

---

## 5. Prioritized Content Actions

### P0: Critical Fixes (Blocking discoverability or AI citation)

These items block the site from being discovered by search engines and cited by AI models. Each represents a failure in the most fundamental content requirements.

| ID | Action | Page(s) | Expected Impact | Effort | Source |
|---|---|---|---|---|---|
| P0-1 | **Rewrite homepage title tag.** Change from "Soleur - Stop Hiring. Start Delegating." to "Soleur -- Company-as-a-Service Platform for Solo Founders". Places category term and audience in the title. Keep tagline in H2 or subheading. Note: brand guide says to lead with platform vision, not plugin description -- "Company-as-a-Service Platform" aligns with this. | Homepage | HIGH -- Title tag is the single most weighted on-page element. Currently contains zero target keywords. | Low (1 line) | Content audit C1, C3 |
| P0-2 | **Rewrite homepage H1.** Change from "Build a Billion-Dollar Company. Alone." to "The AI Organization for Solo Founders" or similar keyword-bearing heading. Move current H1 to a subheading or hero tagline position. | Homepage | HIGH -- H1 is the second most weighted on-page element. Currently targets no search query. | Low (1 line) | Content audit C2 |
| P0-3 | **Add canonical product definition paragraph to homepage.** Insert as the first body paragraph: a 2-3 sentence factual description of what Soleur is, what it does, who it serves. Must be self-contained (no context dependency) so AI models can extract it. Example: "Soleur is an open-source Company-as-a-Service platform that deploys 65 AI agents across 8 business departments -- engineering, marketing, legal, finance, operations, product, sales, and support. It gives solo founders the operational capacity of a full organization through a compounding knowledge base that remembers everything about the business." | Homepage, About, Getting Started | HIGH -- AI models asked "What is Soleur?" currently have no clean extractable answer from any core page. AEO audit: homepage conversational readiness scored "Medium" and summary quality scored 58/D. | Medium (3 pages) | AEO audit P0-1 |
| P0-4 | **Add author bylines to all blog posts.** Include author name (Jean Deruelle), role (Founder, Soleur), link to About page, and publication date on every blog post. | All 16 blog posts | HIGH -- E-E-A-T gap. Named attribution increases trust signals for both traditional search and AI citation. Content audit scored E-E-A-T at 4/10. AEO Authority Signals scored 52/F. | Medium (template change + 16 posts) | Content audit C5, AEO audit P1-6 |
| P0-5 | **Expand About page with founder credentials.** Add: professional background (2-3 paragraphs), founding timeline with dates, verifiable metrics (GitHub stars, PR count, release count), FAQ section (4-5 questions about founder and company), and contact information. Currently scores 32/F in AEO with zero citations, zero statistics, and no FAQ. | About page | HIGH -- This single page underlies E-E-A-T signals for all 16 blog posts via `rel="author"` links. SEO audit Priority 1. AEO audit P0-2. | Medium | SEO audit W1, AEO audit P0-2, Content audit I1 |
| P0-6 | **Add source citations to core pages.** Homepage, Skills, Vision, and Community currently average 0.7 citations per page vs. blog posts at 3.1. Add at least 2 verifiable external citations per core page. For homepage: cite Amodei source (Inc.com interview), cite cost comparison methodology. For Skills: cite Karpathy's agentic engineering definition. | Homepage, Skills, Vision, Community | HIGH -- Source citations are the #1 GEO impact factor. Core pages scoring D in citations means AI engines will never cite them over blog content. | Medium | AEO audit P0-3 |
| P0-7 | **Organize blog index with topic categories.** Group posts under: "What is Company-as-a-Service?" (pillar + cluster), "Soleur vs. Competitors" (5 comparison posts), "Case Studies" (5 case studies), "Engineering Deep Dives" (4 technical posts). Add featured/pinned posts. | Blog index | HIGH -- Blog index scores 30/F in AEO. No categorization means search engines cannot identify topic authority clusters. | Medium | Content audit C4 |

### P1: High-Impact Improvements (Within 2 weeks)

| ID | Action | Page(s) | Expected Impact | Effort | Source |
|---|---|---|---|---|---|
| P1-1 | **Standardize "compounding knowledge base" definition.** Choose one canonical definition and use identical wording on homepage, about, agents, skills, and getting-started. Currently defined differently on 6+ pages. | Homepage, About, Agents, Skills, Getting Started | MEDIUM-HIGH -- AI models may produce conflicting citations from different pages. | Low | AEO audit P1-2 |
| P1-2 | **Add definition paragraphs for key terms on core pages.** "Agentic engineering" on Skills page (used in H1, never defined). "Human-in-the-loop" on homepage (used without definition). "Agent" vs "Skill" distinction on Getting Started. "Company-as-a-Service" on homepage. | Skills, Homepage, Getting Started | MEDIUM-HIGH -- Definition extractability scored 72/B-. Undefined terms in headings confuse both users and AI models. | Medium | AEO audit P1-3, Content audit I2 |
| P1-3 | **Fix Skills page H1 mismatch.** Change from "Agentic Engineering Skills" to "Soleur Skills: 64 Workflow Automations Across 8 Departments" (or similar) to match actual page content covering all categories. | Skills page | MEDIUM -- H1 says "Agentic Engineering" but page covers content, workflow, review skills. Mismatch confuses search intent. | Low (1 line) | Content audit I2 |
| P1-4 | **Add summary comparison table to top of each comparison post.** All 5 existing "vs." posts start with narrative. Users scanning for quick answers leave before reaching detailed comparison. Add a 4-5 row feature comparison table in the first 300 words. | 5 comparison blog posts | MEDIUM -- Comparison posts score B-B+ in AEO. Summary tables at top improve both SERP snippets and AI extraction. | Medium | Content audit I10 |
| P1-5 | **Rename case study titles to include "Soleur".** Apply pattern "How Soleur [achieved X]" to all 5 case studies. Current titles like "From Scattered Positioning to a Full Brand Guide in Two Sessions" do not mention the tool used. | 5 case study blog posts | MEDIUM -- Misses branded search queries like "Soleur brand guide" or "Soleur legal documents." | Low | Content audit I9 |
| P1-6 | **Vary case study heading structures.** All 5 use identical "The AI Approach / The Result / The Cost Comparison / The Compound Effect" headings. Diversify heading patterns to avoid template content signals. | 5 case study blog posts | MEDIUM-LOW -- Template patterns may be flagged as thin/duplicate structure by search engines. | Medium | Content audit I8 |
| P1-7 | **Fix heading hierarchy on homepage and getting-started page.** Homepage: promote "The Workflow" from h3 to h2. Getting-started: promote "The Workflow", "Commands", "Example Workflows", "Learn More" from h3 to h2. | Homepage, Getting Started | MEDIUM -- Content structure signals for crawlers and screen readers. | Low | SEO audit W3 |
| P1-8 | **Add FAQ to About page.** Include 4-5 questions: "Who founded Soleur?", "What is Soleur?", "When was Soleur founded?", "Is Soleur open source?", "How is Soleur built?" | About page | MEDIUM -- About page has no FAQ and scores 35/F in AEO. These are high-intent navigational queries. | Low | AEO audit gap |
| P1-9 | **Rewrite homepage meta description.** Change from "One command center. 8 departments. AI agents that remember everything about your business." to: "Deploy 65 AI agents across 8 business departments -- engineering, marketing, legal, finance, sales, operations, product, and support. A compounding knowledge base that learns your business. Free and open source." | Homepage | MEDIUM -- Current meta description is clever but misses primary keywords. New version adds "AI agents," department names, "compounding knowledge base," and "free and open source." | Low (1 line) | Content audit RS3 |
| P1-10 | **Begin listicle outreach campaign.** Identify and contact authors of the top 10 "best AI tools for solo founders 2026" and "best Claude Code plugins 2026" listicles. Soleur appears on zero listicles despite being a mature product. Provide a brief (product name, one-line description, differentiator, link). | N/A (outreach) | HIGH -- Listicle presence is the primary commercial keyword discovery channel. This is the single most impactful distribution action. | Medium (ongoing) | Competitive gap 3.2 |
| P1-11 | **Write "Soleur vs. Devin" comparison post.** Devin slashed pricing to $20/mo + $2.25/ACU. Devin 2.0 launched Interactive Planning and Wiki. Cognition acquired Windsurf. High-intent commercial query with very low competition. | New blog post | MEDIUM-HIGH -- No existing content targets this query. Devin is the highest-profile AI coding agent. | Medium (2,000-word post) | Keyword gap |
| P1-12 | **Write "Soleur vs. GitHub Copilot" comparison post.** Copilot at $10/mo with Agent Mode (assigns issues autonomously). Deep GitHub integration. Incumbent with massive adoption. | New blog post | MEDIUM-HIGH -- No existing content targets this query. Copilot is the most widely adopted AI coding tool. | Medium (2,000-word post) | Keyword gap |
| P1-13 | **Align `<html lang>` with og:locale and JSON-LD.** Change `<html lang="en">` to `<html lang="en-US">`. One-line fix. | base.njk template | LOW -- Minor inconsistency signal. Trivial effort justifies immediate fix. | Trivial | SEO audit W5 |

### P2: Medium-Impact Improvements (Within 1 month)

| ID | Action | Page(s) | Expected Impact | Effort | Source |
|---|---|---|---|---|---|
| P2-1 | **Write "The One-Person Billion-Dollar Company" pillar content.** Target "one person billion dollar company" (VERY HIGH volume). Cite Dario Amodei prediction (70-80% odds for 2026), Base44 $80M exit, Danny Postma $3.6M ARR, Gumloop $17M raise with 2 staff. Position Soleur as the infrastructure for this thesis. | New blog post (3,000+ words) | HIGH -- Highest-volume keyword Soleur has no dedicated content for. Fortune, TechCrunch, NxCode already published. | High (pillar content) | Keyword research 2.1 |
| P2-2 | **Write "AI Agent Platform vs. AI Agent Framework" explainer.** Differentiate turnkey platforms (Soleur, Lindy, Gumloop) from developer frameworks (CrewAI, LangGraph, AutoGen). Soleur: one command install, 65 agents. Frameworks: 4-8 weeks to production. AutoGen now in maintenance mode after Microsoft merger. | New blog post (2,500 words) | MEDIUM-HIGH -- Captures "AI agent framework comparison" commercial queries. Positions Soleur against indirect competitors. | Medium | Keyword gap, Competitive gap 3.1 |
| P2-3 | **Write "How to Run a Company with AI in 2026" guide.** Target "how to run a company with AI" (HIGH volume, HIGH competition). Practical guide structure: 8 departments, what to automate first, tool stack, cost comparison. Naturally positions Soleur as the integrated solution. | New blog post (3,000+ words) | MEDIUM-HIGH -- Major content gap. Entrepreneur, Growrai, PiXENDA rank. Soleur has no content targeting this directly. | High | Keyword research 2.2 |
| P2-4 | **Expand community page with statistics and depth.** Add: Discord member count, GitHub star count, contributor count, featured community contributions, "Getting Involved" guide, recent activity indicators. Currently ~200 words. | Community page | MEDIUM -- Thin pages hurt domain authority. Community page scores 37/F in AEO. | Medium | Content audit I5, AEO audit |
| P2-5 | **Add Changelog meta description and narrative summaries.** Current changelog is auto-generated version numbers only. Add: meta description targeting "Soleur changelog" / "Soleur updates", narrative highlights for major releases. | Changelog page | LOW-MEDIUM -- Missed navigational queries. Currently no meta description detected. | Medium | Content audit I6 |
| P2-6 | **Add "Key Concepts" glossary to Getting Started page.** Canonical definitions for: Agent, Skill, Compound knowledge, Human-in-the-loop, Company-as-a-Service, Agentic engineering, Knowledge base, Cross-domain coherence, Department, Session. | Getting Started page | MEDIUM -- A canonical glossary is a high-value AI citation target. Terms currently defined inconsistently across pages. | Medium | AEO audit P2-6 |
| P2-7 | **Update existing comparison posts with fresh data.** Cursor: $2B+ ARR, parallel agents. Polsia: new competitors (Twin, Junior, Viktor). Cowork: department plugins. Add `updated` frontmatter field to trigger dateModified in structured data. | 5 comparison blog posts | MEDIUM -- Content freshness signals. Only 1 of 16 blog posts has distinct dateModified. | Medium | SEO audit W2, Competitive gap |
| P2-8 | **Create 3-5 unique OG images for top blog posts.** Target: "What Is CaaS?", "AI Agents for Solo Founders", "Vibe Coding vs Agentic Engineering", "Soleur vs Cursor." Infrastructure exists (pricing page already has custom ogImage). | Blog post frontmatter + images | LOW-MEDIUM -- Social sharing differentiation. Currently all posts use generic og-image.png. | Medium | SEO audit W6 |
| P2-9 | **Add internal links between all related blog posts.** Implement cross-linking: comparison posts link to each other, case studies link to the definitive guide, pillar content links to cluster pages, cluster pages link back to pillar and to at least one sibling. | All 16 blog posts | MEDIUM-HIGH -- Internal linking scored 4/10 in content audit. No pillar/cluster link structure exists. | Medium (16 posts) | Content audit C6 |
| P2-10 | **Expand top 10 agent descriptions.** CTO, CMO, CLO, CFO, CRO, COO, CCO, code-reviewer, architect, copywriter descriptions expanded from 1-2 sentences to 2-3 sentences with example use cases. | Agents page | LOW-MEDIUM -- Agent descriptions too brief for AI extraction. | Medium | AEO audit P2-1 |
| P2-11 | **Add citations to Credential Helper blog post.** Currently zero external citations despite referencing Git internals, GitHub APIs, JWT authentication. Cite: Git credential helper docs, GitHub App token documentation, JWT RFC 7519. | Credential Helper blog post | LOW -- Technical deep-dive that would benefit from source credibility. | Low | AEO audit P2-3 |
| P2-12 | **Add statistics to Vibe Coding vs Agentic Engineering post.** Only 2 data points in 2,100 words. Add: TELUS 500,000+ hours saved, Zapier 89% AI adoption, Stripe Minions 1,000+ merged PRs/week, 96% of organizations using AI agents (OutSystems 2026). | Vibe Coding blog post | LOW-MEDIUM -- Comparison content performs better with benchmarks. | Low | AEO audit P2-4 |

### P3: Nice-to-Have Optimizations (Backlog)

| ID | Action | Page(s) | Expected Impact | Effort | Source |
|---|---|---|---|---|---|
| P3-1 | **Write "Agentic Engineering: The Definitive Guide 2026."** Comprehensive guide (4,000+ words) targeting "agentic engineering" as primary keyword. Cover: definition, history (Karpathy coinage), methodology, tools, frameworks, case studies, comparison with vibe coding, best practices. | New blog post | MEDIUM-HIGH -- VERY HIGH volume keyword. Multiple competitors have published guides. Soleur has expertise but no definitive guide. | Very High | Keyword research 2.1 |
| P3-2 | **Write "Context Engineering for Solo Founders" guide.** Target emerging "context engineering" keyword. Map to Soleur's CLAUDE.md and knowledge base architecture as a working implementation. Cite Martin Fowler endorsement. | New blog post | MEDIUM -- Emerging keyword with growing volume. Soleur has a genuine implementation story. | High | Keyword research 2.2 |
| P3-3 | **Write "The CaaS Landscape 2026" roundup.** Cover Polsia, Twin, Junior, Viktor, OctoClaw, Cowork.ink alongside Soleur. Position as the definitive comparison of all CaaS-adjacent platforms. | New blog post | MEDIUM -- No one has written this roundup. First-mover advantage. Emerging competitor category. | High | Competitive gap 3.1 |
| P3-4 | **Write "Best Claude Code Plugins for Solo Founders 2026" listicle.** Self-hosted listicle targeting "best Claude Code plugins 2026." Include Soleur plus genuine recommendations for complementary plugins (MemClaw, VoltAgent, etc.). | New blog post | MEDIUM -- Captures commercial query. Multiple listicles exist but none from a solo-founder perspective. | Medium | Keyword research 2.2 |
| P3-5 | **Submit Soleur to AI tool directories.** Product Hunt, AlternativeTo, G2, SourceForge, Toolify. Build third-party review presence. Currently zero external reviews. | N/A (outreach) | MEDIUM-HIGH -- Third-party mentions score 40/F. AI models cannot validate claims without external sources. | Medium (ongoing) | AEO audit P0-4 |
| P3-6 | **Implement citation monitoring process.** Monthly manual checks: search "Soleur AI agents" and "company-as-a-service platform" in ChatGPT, Perplexity, Claude, Google AI Overviews. Track whether Soleur appears and which pages are cited. | Operational process | LOW -- Monitoring enables measurement of AEO improvements. No current visibility into AI citations. | Low (recurring) | AEO audit P2-7 |
| P3-7 | **Trim FAQ answers exceeding 3 sentences.** Audit all FAQ answers sitewide. Condense any exceeding 3 sentences to improve AI extraction. Vision FAQ "What is the Soleur roadmap?" answer is the primary offender. | Multiple pages | LOW -- Long FAQ answers are harder for AI engines to extract. Most are already concise. | Low | Content audit I11 |
| P3-8 | **Add "last updated" dates to core pages.** Homepage, agents, skills, pricing, community currently show no last-updated indicator. Add `dateModified` to structured data. | Core pages | LOW -- Content freshness signal for AI models. | Low | AEO audit P2-5 |
| P3-9 | **Remove `<base href="/">` tag.** Legacy pattern, redundant with existing absolute/root-relative paths. Low risk but technically unnecessary. | base.njk template | VERY LOW -- Edge-case crawler issues. Unlikely to cause actual problems. | Low (requires link verification) | SEO audit W4 |
| P3-10 | **Separate Vision page near-term roadmap from aspirational content.** "Multiplanetary Companies" and "spacefleet integration" sections may cause AI models to discount the entire page as speculative. Restructure to clearly delineate factual roadmap from long-term vision. | Vision page | LOW-MEDIUM -- Credibility risk for a pre-revenue platform. AI models prefer factual, measured statements. | Medium | AEO audit P1-4, Content audit I7 |
| P3-11 | **Add self-hosted case studies disclaimer.** All 5 case studies describe Soleur building Soleur. Add: "This case study documents Soleur's internal usage during product development." When external users exist, create case studies with their outcomes. | 5 case study blog posts | LOW -- Transparency improves trust. Self-referential case studies are weaker than customer outcomes. | Low | AEO audit P2-2 |

---

## 6. Scoring Matrix

Each content action is scored on four dimensions (1-5 scale). Actions are ranked by total score within their priority tier.

### P0 Actions (Critical)

| ID | Customer Impact | Content-Market Fit | Search Potential | Resource Cost (5=low) | Total | Rank |
|---|---|---|---|---|---|---|
| P0-1 | 5 | 5 | 5 | 5 | 20 | 1 |
| P0-2 | 5 | 5 | 5 | 5 | 20 | 1 |
| P0-3 | 5 | 5 | 5 | 4 | 19 | 3 |
| P0-5 | 5 | 5 | 4 | 3 | 17 | 4 |
| P0-4 | 4 | 5 | 4 | 3 | 16 | 5 |
| P0-6 | 4 | 4 | 5 | 3 | 16 | 5 |
| P0-7 | 4 | 4 | 4 | 3 | 15 | 7 |

### P1 Actions (High Impact)

| ID | Customer Impact | Content-Market Fit | Search Potential | Resource Cost (5=low) | Total | Rank |
|---|---|---|---|---|---|---|
| P1-10 | 5 | 5 | 5 | 3 | 18 | 1 |
| P1-11 | 4 | 5 | 4 | 3 | 16 | 2 |
| P1-12 | 4 | 5 | 4 | 3 | 16 | 2 |
| P1-9 | 4 | 5 | 4 | 5 | 18 | 1 |
| P1-4 | 4 | 4 | 4 | 3 | 15 | 5 |
| P1-5 | 3 | 5 | 4 | 5 | 17 | 3 |
| P1-1 | 3 | 5 | 4 | 4 | 16 | 2 |
| P1-2 | 3 | 5 | 4 | 3 | 15 | 5 |
| P1-3 | 3 | 5 | 3 | 5 | 16 | 2 |
| P1-7 | 3 | 4 | 3 | 5 | 15 | 5 |
| P1-8 | 3 | 4 | 3 | 5 | 15 | 5 |
| P1-6 | 2 | 4 | 3 | 3 | 12 | 12 |
| P1-13 | 2 | 3 | 2 | 5 | 12 | 12 |

### P2 Actions (Medium Impact)

| ID | Customer Impact | Content-Market Fit | Search Potential | Resource Cost (5=low) | Total | Rank |
|---|---|---|---|---|---|---|
| P2-1 | 5 | 5 | 5 | 2 | 17 | 1 |
| P2-9 | 4 | 5 | 4 | 3 | 16 | 2 |
| P2-3 | 4 | 4 | 5 | 2 | 15 | 3 |
| P2-2 | 4 | 5 | 4 | 3 | 16 | 2 |
| P2-7 | 3 | 5 | 4 | 3 | 15 | 3 |
| P2-4 | 3 | 4 | 3 | 3 | 13 | 6 |
| P2-6 | 3 | 4 | 4 | 3 | 14 | 5 |
| P2-12 | 3 | 4 | 3 | 4 | 14 | 5 |
| P2-8 | 2 | 3 | 2 | 3 | 10 | 9 |
| P2-10 | 2 | 4 | 3 | 3 | 12 | 8 |
| P2-5 | 2 | 3 | 2 | 3 | 10 | 9 |
| P2-11 | 2 | 4 | 2 | 4 | 12 | 8 |

---

## 7. Searchable vs. Shareable Content Balance

### Current Content Classification

| Type | Count | Examples |
|---|---|---|
| Searchable (targets search traffic) | 14 | Pillar posts, comparison posts, case studies, technical guides |
| Shareable (targets social distribution) | 2 | "Vibe Coding vs Agentic Engineering" (timely topic), "Why Most Agentic Tools Plateau" (contrarian thesis) |

**Assessment:** The content mix is heavily skewed toward searchable content (88% searchable, 12% shareable). This is common for early-stage technical products but limits distribution reach.

**FLAG: Shareable content is underrepresented.** The plan needs content designed for social virality, not just search ranking.

### Planned Content Classification

| Content Piece | Type | Rationale |
|---|---|---|
| The One-Person Billion-Dollar Company (P2-1) | **Shareable** | Taps into trending narrative. Citable data points (Amodei prediction, Base44 exit). High social shareability. |
| AI Agent Platform vs Framework (P2-2) | Searchable | Commercial comparison query. Decision-making content. |
| How to Run a Company with AI (P2-3) | Searchable | Practical guide targeting informational intent. |
| Soleur vs. Devin (P1-11) | Searchable | Commercial comparison query. |
| Soleur vs. GitHub Copilot (P1-12) | Searchable | Commercial comparison query. |
| Agentic Engineering Guide (P3-1) | Searchable | Definitive guide targeting high-volume keyword. |
| Context Engineering for Solo Founders (P3-2) | **Shareable** | Emerging concept. Novel angle (solo founder context engineering vs. enterprise). |
| CaaS Landscape 2026 (P3-3) | **Shareable** | First-of-kind roundup. Industry mapping. Highly linkable. |
| Best Claude Code Plugins (P3-4) | Searchable | Listicle targeting commercial query. |

### Updated Balance After Plan Execution

| Type | Current | After P0-P2 | Target |
|---|---|---|---|
| Searchable | 88% (14/16) | 79% (19/24) | 70-75% |
| Shareable | 12% (2/16) | 21% (5/24) | 25-30% |

The plan moves the ratio from 88/12 to 79/21. To reach the 70/30 target, additional shareable content should be added in future planning cycles: founder journey posts, original research/data, and industry opinion pieces.

---

## 8. Methodology

### Data Sources

- **Content audit:** 26 pages analyzed via WebFetch on 2026-04-13 against keyword alignment, search intent match, readability, content depth, E-E-A-T, and internal linking criteria
- **AEO audit:** Same 26 pages scored against the SAP framework (Structure/Authority/Presence) with GEO impact prioritization
- **SEO audit:** Full 36-page technical SEO analysis covering structured data, meta tags, AI discoverability, E-E-A-T, sitemap, content quality, Core Web Vitals, and technical SEO
- **Keyword research:** WebSearch queries across 8 keyword clusters on 2026-04-13, supplemented by competitive SERP analysis
- **Brand guide:** `knowledge-base/marketing/brand-guide.md` consulted for voice alignment, positioning constraints, and audience segmentation

### Scoring Methodology

- **Customer impact (1-5):** Does this topic matter to the ICP (technical solo founders building at scale)?
- **Content-market fit (1-5):** Can Soleur write this credibly given its product, expertise, and dogfooding data?
- **Search potential (1-5):** Volume signal multiplied by inverse of keyword difficulty. High-volume + low-competition = 5.
- **Resource cost (1-5, inverted):** 5 = trivial (one-line change), 1 = very high (4,000+ word pillar content). Inverted so higher score = less effort.

### Brand Guide Alignment Notes

- "Company-as-a-Service Platform" used in title recommendations (aligns with brand tagline)
- "Plugin" avoided in marketing copy per brand guide prohibition (exception noted for technical docs)
- Rewrite suggestions use "platform" not "tool" per brand guide voice rules
- Audience framing uses "solo founders" consistently (primary ICP per brand guide)
- All content recommendations assume the bold, forward-looking, mission-driven voice described in the brand guide

### Limitations

- Search volume data is directional (signal-based), not absolute numbers. WebSearch provides relative volume indicators but not exact monthly search volumes.
- Competitor content counts are estimates based on visible blog archives; some content may be gated or unlisted.
- Listicle presence was verified via search results on 2026-04-13; new listicles may have been published since.
- AEO scoring is based on current best practices for AI citation behavior as documented in 2025-2026 research; AI engine behavior evolves rapidly.
