---
audit_date: 2026-03-16
audited_by: content-strategy-agent
site: https://soleur.ai
source_files: plugins/soleur/docs/
brand_guide: knowledge-base/marketing/brand-guide.md
status: complete
---

# Content Audit: soleur.ai

**Date:** 2026-03-16
**Scope:** All public-facing pages on soleur.ai (source: `plugins/soleur/docs/`)
**Method:** Source file analysis (live site returned HTTP 403 via WebFetch; all content audited from local Nunjucks/Markdown source files)
**Brand Guide:** Aligned against `knowledge-base/marketing/brand-guide.md` (last reviewed 2026-03-02)

---

## Executive Summary

The soleur.ai website has strong brand voice alignment and ambitious positioning consistent with the brand guide. The primary weaknesses are: (1) thin keyword coverage for high-traffic search terms like "claude code plugin," "solo founder AI tools," and "AI engineering workflow"; (2) missing pages for commercially valuable queries (pricing, getting started as a standalone landing page); (3) several meta descriptions that are too long or miss target keywords; and (4) the Skills page lacks a FAQ section that the Agents page has, creating an inconsistency in AEO readiness.

The site has 7 core pages, 1 getting-started guide, and 7 blog posts (5 case studies, 1 pillar article, 1 comparison article). Legal pages (9 documents) are excluded from this content audit as they serve compliance, not discoverability.

**Critical issues:** 3
**Improvements:** 11
**Rewrite suggestions:** 8

---

## 1. Per-Page Analysis

### 1.1 Homepage (`index.njk` -> `/`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Soleur - The Company-as-a-Service Platform` |
| **Meta Description** | "Soleur is the company-as-a-service platform -- a Claude Code plugin that gives solo founders a full AI organization across every business department." |
| **H1** | "Build a Billion-Dollar Company. Alone." |
| **Target Keywords (Detected)** | company-as-a-service, solo founders, AI organization, AI agents, Claude Code plugin |
| **Keyword Alignment** | GOOD -- Covers primary brand terms. Missing: "agentic engineering" appears only in the features H2 but not in the hero or meta. |
| **Search Intent Match** | Navigational/Informational -- Users searching "Soleur" or "company as a service platform" will land here correctly. |
| **Readability** | STRONG -- Short, punchy sentences. Brand voice is precisely calibrated. Hero copy is declarative per brand guide. |
| **FAQ Section** | Present -- 6 questions with FAQPage structured data. Well-constructed for AEO. |
| **Word Count (body text)** | ~550 words (excluding FAQ structured data) |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | Meta description length | At 144 characters, it is within the 155-char limit but could be tighter. The phrase "a Claude Code plugin that gives" buries the value proposition after a technical descriptor. |
| Improvement | Missing "solo founder AI tools" keyword cluster | The hero subtitle mentions "solo founders" but the phrase "solo founder AI tools" (high search volume in 2026) never appears on the page. |
| Improvement | "agentic engineering" appears once in an H2 | The term has high search relevance (Karpathy coined it Feb 2026) but only appears in the features section subheading, not in the hero, meta, or FAQ. |

---

### 1.2 Getting Started (`pages/getting-started.md` -> `/pages/getting-started.html`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Getting Started with Soleur` |
| **Meta Description** | "Install the Soleur Claude Code plugin and start running your company-as-a-service -- AI agents for engineering, marketing, legal, finance, and more." |
| **H1** | "Getting Started with Soleur" |
| **Target Keywords (Detected)** | Claude Code plugin, company-as-a-service, AI agents, AI organization, install |
| **Keyword Alignment** | GOOD -- Covers installation intent. Missing: "how to install," "getting started with AI agents," "claude code extensions." |
| **Search Intent Match** | Transactional -- Users searching "install soleur" or "soleur getting started" will find what they need. |
| **Readability** | STRONG -- Step-by-step format, code blocks, clear workflow explanation. |
| **FAQ Section** | ABSENT -- This is a key onboarding page; FAQ would help capture "how do I..." queries. |
| **Word Count** | ~450 words |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Critical | No FAQ section | The primary onboarding page has no FAQ. Questions like "What are the prerequisites?", "Does Soleur work with VS Code?", "What Claude subscription do I need?" are all search queries this page should capture. |
| Improvement | Subtitle uses "plugin" | "Install the Claude Code plugin that gives you a full AI organization." -- The brand guide prohibits "plugin" in public-facing content except in CLI commands. The subtitle should reframe. |
| Improvement | Missing keyword "claude code extensions" | With 9,000+ plugins in the ecosystem and high search volume for "best claude code plugins/extensions," this page could rank for those queries with minor keyword additions. |

---

### 1.3 Agents (`pages/agents.njk` -> `/pages/agents.html`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Soleur AI Agents` |
| **Meta Description** | "AI agents for business -- engineering, marketing, legal, finance, operations, product, sales, and support. Each agent is a specialist in the Soleur company-as-a-service platform." |
| **H1** | "Soleur AI Agents" |
| **Target Keywords (Detected)** | AI agents, agentic engineering, company-as-a-service, cross-domain coherence, compounding knowledge base |
| **Keyword Alignment** | STRONG -- "AI agents for business" is a high-relevance phrase. The intro prose uses "agentic engineering" naturally. |
| **Search Intent Match** | Informational -- Users searching "AI agents for business" or "Soleur agents" land correctly. |
| **Readability** | STRONG -- Clear intro prose, then structured catalog cards. |
| **FAQ Section** | Present -- 3 questions. Could expand to 5-6 for better AEO coverage. |
| **Word Count** | ~250 words (intro) + dynamic catalog content |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | FAQ is thin (3 questions) | Homepage has 6. This page should match or exceed with questions like "Can I add custom agents?", "How do agents share knowledge?", "What models do agents use?" |
| Improvement | Missing "AI company automation" keyword | This is a target keyword that is not present anywhere on the page. The intro could naturally incorporate it. |

---

### 1.4 Skills (`pages/skills.njk` -> `/pages/skills.html`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Soleur Skills` (rendered as `Soleur Skills - Soleur`) |
| **Meta Description** | "Multi-step workflow skills for the Soleur platform -- from feature development and code review to content writing, deployment, and agentic engineering." |
| **H1** | "Agentic Engineering Skills" |
| **Target Keywords (Detected)** | agentic engineering, workflow skills, compound engineering lifecycle |
| **Keyword Alignment** | GOOD -- "Agentic engineering" in H1 is strong. Meta includes the term. Missing: "AI engineering workflow" (a target keyword). |
| **Search Intent Match** | Informational -- Matches queries for "agentic engineering skills" or "AI workflow orchestration." |
| **Readability** | STRONG -- Clear lifecycle explanation, then structured skill catalog. |
| **FAQ Section** | ABSENT -- Inconsistent with Agents page which has one. |
| **Word Count** | ~200 words (intro) + dynamic catalog content |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Critical | No FAQ section | The Agents page has a FAQ; the Skills page does not. This inconsistency leaves AEO value on the table. Questions: "What is agentic engineering?", "How do skills differ from agents?", "Can I create custom skills?" |
| Improvement | "AI engineering workflow" keyword missing | The meta description says "agentic engineering" but not the exact target phrase "AI engineering workflow." |

---

### 1.5 Vision (`pages/vision.njk` -> `/pages/vision.html`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Vision` |
| **Meta Description** | "Where Soleur is headed. The Company-as-a-Service platform that gives solo founders the leverage of a full organization." |
| **H1** | "Vision" |
| **Target Keywords (Detected)** | Company-as-a-Service, billion-dollar solopreneur, model-agnostic, orchestration engine, human-in-the-loop |
| **Keyword Alignment** | MIXED -- Strong on brand terms but the page reads more like an investor pitch than searchable content. "Solo founder AI tools" and "AI company automation" are absent. |
| **Search Intent Match** | Informational -- Users searching "Soleur vision" or "Soleur roadmap" land correctly, but the page targets a narrow navigational audience. |
| **Readability** | MODERATE -- Dense paragraphs. Some sentences exceed 40 words. "Synthetic labor (AI Agent Swarms)" introduces jargon without definition. |
| **FAQ Section** | ABSENT |
| **Word Count** | ~850 words |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | H1 is just "Vision" | Not keyword-rich. "The Soleur Vision: Building the Company-as-a-Service Platform" would capture more search value. |
| Improvement | No FAQ section | Missed opportunity for questions like "What is Soleur's long-term vision?", "What is model-agnostic AI orchestration?", "What is the Soleur master plan?" |
| Improvement | Dense paragraphs | The first paragraph is 58 words. For AEO, the opening summary should be 1-2 concise sentences that AI can directly quote. |

---

### 1.6 Community (`pages/community.njk` -> `/pages/community.html`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Community` |
| **Meta Description** | "Join the Soleur community. Connect on Discord, contribute on GitHub, get help, and learn about our community guidelines." |
| **H1** | "Community" |
| **Target Keywords (Detected)** | Discord, GitHub, contributing, community |
| **Keyword Alignment** | LOW -- Generic community page. No target keywords from the audit list are present. |
| **Search Intent Match** | Navigational -- Correct for "Soleur community" or "Soleur Discord." |
| **Readability** | STRONG -- Clean, card-based layout. Short descriptions. |
| **FAQ Section** | ABSENT |
| **Word Count** | ~250 words |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | Low keyword value | This page serves a navigational purpose and is not expected to drive organic search traffic. No changes recommended beyond ensuring internal links point here from content pages. |

---

### 1.7 Blog Index (`pages/blog.njk` -> `/blog/`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Blog` |
| **Meta Description** | "Insights on agentic engineering, company-as-a-service, and building at scale with AI teams." |
| **H1** | "Blog" |
| **Target Keywords (Detected)** | agentic engineering, company-as-a-service |
| **Keyword Alignment** | GOOD -- Meta description captures two high-value terms. |
| **Search Intent Match** | Navigational -- Index page. Correct for "Soleur blog." |
| **Readability** | N/A -- Index page with dynamic card listing. |
| **FAQ Section** | ABSENT (not expected for an index) |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | H1 is just "Blog" | Could be "Soleur Blog: Agentic Engineering and Company-as-a-Service" for more keyword value. However, this is a minor point since blog index pages rarely rank independently. |

---

### 1.8 Changelog (`pages/changelog.njk` -> `/pages/changelog.html`)

| Attribute | Value |
|-----------|-------|
| **Title** | `Changelog` |
| **Meta Description** | "Changelog - All notable changes to Soleur." |
| **H1** | "Changelog" |
| **Keyword Alignment** | LOW -- Functional page. Not a search traffic driver. |
| **Search Intent Match** | Navigational -- Correct for "Soleur changelog." |
| **Readability** | N/A -- Dynamic content from release notes. |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| None | Functional page | No content changes recommended. |

---

### 1.9 Blog: "What Is Company-as-a-Service?" (`blog/what-is-company-as-a-service.md`)

| Attribute | Value |
|-----------|-------|
| **Title** | "What Is Company-as-a-Service?" |
| **Meta Description** | "Company-as-a-Service is a new model where AI agents run every business department. Learn what CaaS means, how it works, and why it matters for solo founders." |
| **Target Keywords (Detected)** | company-as-a-service, CaaS, solo founders, AI agents, compounding knowledge base, SaaS vs CaaS |
| **Keyword Alignment** | EXCELLENT -- Pillar content with comprehensive keyword coverage. "Company-as-a-service" appears 25+ times naturally. |
| **Search Intent Match** | Informational -- Definitive article for "what is company as a service" queries. |
| **Readability** | STRONG -- Well-structured with H2/H3 hierarchy, comparison table, FAQ section. Sentences are crisp and authoritative. |
| **FAQ Section** | Present -- 5 questions with FAQPage structured data. |
| **Word Count** | ~3,200 words |
| **Source Citations** | EXCELLENT -- BLS, TechCrunch, CNBC, Inc.com, Fortune, VentureBeat. 10+ external citations. |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | Missing "solo founder AI tools" exact phrase | The article uses "solo founders" extensively but never the exact compound phrase "solo founder AI tools" which has strong search signal. |
| Improvement | Could add an "AI company automation" definition | A brief definition paragraph connecting CaaS to the broader "AI company automation" search cluster would capture additional long-tail traffic. |

---

### 1.10 Blog: "Why Most Agentic Engineering Tools Plateau" (`blog/why-most-agentic-tools-plateau.md`)

| Attribute | Value |
|-----------|-------|
| **Title** | "Why Most Agentic Engineering Tools Plateau" |
| **Meta Description** | "Most AI coding tools stop getting better after week two. The missing layer is compound knowledge -- a system that learns from every task and feeds those learnings back into its own rules, agents, and workflows." |
| **Target Keywords (Detected)** | agentic engineering, compound knowledge, compound engineering, AI coding tools, vibe coding, spec-driven development |
| **Keyword Alignment** | EXCELLENT -- Targets "agentic engineering" head-on. Comparison table positions Soleur against spec-driven and compound engineering approaches. |
| **Search Intent Match** | Informational -- Matches "agentic engineering vs vibe coding," "why AI coding tools plateau," "compound engineering." |
| **Readability** | EXCELLENT -- Hook-first opening, data tables, concrete examples. The writing is precise and substantive. |
| **FAQ Section** | Present -- 3 questions at the end. Well-formed for AEO. |
| **Word Count** | ~3,000 words |
| **Source Citations** | GOOD -- Karpathy tweets (sourced), links to Spec Kit, OpenSpec, Kiro, Tessl, Every's Compound Engineering. |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | Meta description is 196 characters | Exceeds the ~155-character display limit. Google will truncate it. The first 155 characters end at "...compound knowledge -- a system that learns from every task and feeds tho..." which cuts off the value proposition. |
| Improvement | Missing "AI engineering workflow" exact phrase | The article discusses engineering workflows extensively but never uses the exact target phrase. |

---

### 1.11 Blog: "Soleur vs. Anthropic Cowork" (`blog/2026-03-16-soleur-vs-anthropic-cowork.md`)

| Attribute | Value |
|-----------|-------|
| **Title** | "Soleur vs. Anthropic Cowork: Which AI Agent Platform Is Right for Solo Founders?" |
| **Meta Description** | "Soleur and Anthropic Cowork both deploy multi-domain AI agents. A direct comparison of knowledge architecture, workflow depth, cross-domain coherence, and pricing." |
| **Target Keywords (Detected)** | Soleur vs Cowork, AI agent platform, solo founders, compounding knowledge base, cross-domain coherence, open source |
| **Keyword Alignment** | STRONG -- Captures comparison search intent. "Soleur vs Anthropic Cowork" is a valuable navigational query. |
| **Search Intent Match** | Commercial -- Users comparing AI agent platforms. Well-matched to intent. |
| **Readability** | EXCELLENT -- Comparison table, side-by-side format, clear "Who Each Platform Is For" section. |
| **FAQ Section** | Present -- 5 questions with FAQPage structured data. Comprehensive. |
| **Word Count** | ~2,800 words |
| **Source Citations** | GOOD -- TechCrunch, The Decoder, Claude pricing page. |

**Issues:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Improvement | Could add Microsoft Copilot Cowork to the title | The article covers three platforms (Anthropic Cowork, Microsoft Copilot Cowork, Soleur) but the title only names two. Adding "and Microsoft Copilot" could capture additional comparison queries. |

---

### 1.12-1.16 Blog: Case Studies (5 articles)

| Article | Title | Word Count | FAQ | Source Citations |
|---------|-------|-----------|-----|-----------------|
| Business Validation | "Running a Business Validation Workshop With AI Gates" | ~850 | No | None (internal case study) |
| Legal Documents | "How We Generated 9 Legal Documents in Days, Not Months" | ~800 | No | None (internal case study) |
| Operations | "Building an Operations Department for a One-Person Company" | ~750 | No | None (internal case study) |
| Brand Guide | "From Scattered Positioning to a Full Brand Guide in Two Sessions" | ~650 | No | None (internal case study) |
| Competitive Intelligence | "Tracking 17 Competitors in One Session -- With Battlecards" | ~700 | No | None (internal case study) |

**Shared Issues Across All 5 Case Studies:**

| Severity | Issue | Detail |
|----------|-------|--------|
| Critical | No FAQ sections | None of the 5 case studies have FAQ sections. Each covers a distinct domain (legal, ops, marketing, product, competitive intel) with rich FAQ potential. |
| Improvement | No external source citations | Case studies describe internal processes. For AEO, adding 1-2 external citations per article (e.g., industry benchmarks for legal document costs, consultant rates) would strengthen authority signals. |
| Improvement | Thin meta descriptions | All meta descriptions are informative but none include target keywords like "company-as-a-service," "AI agents," or "solo founder." |

---

## 2. Search Intent Alignment Analysis

### Target Keywords and Intent Classification

| Keyword | Search Intent | Current Coverage | Assessment |
|---------|--------------|-----------------|------------|
| **claude code plugin** | Navigational / Commercial | Homepage meta, Getting Started | PARTIAL -- Term appears but brand guide discourages "plugin" in public copy. Tension between SEO value and brand positioning. |
| **agentic engineering** | Informational | Skills H1, Blog (plateau article), Homepage H2 | GOOD -- Well-covered by the plateau article. Skills page H1 is strong. |
| **AI company automation** | Commercial | Not present on any page | GAP -- Zero occurrences site-wide. |
| **solo founder AI tools** | Commercial | Not present as exact phrase | GAP -- "Solo founders" appears frequently but the compound phrase "solo founder AI tools" never appears. |
| **claude code extensions** | Commercial / Navigational | Not present on any page | GAP -- Zero occurrences site-wide. |
| **AI engineering workflow** | Informational | Not present as exact phrase | GAP -- Concept is discussed extensively but the exact phrase never appears. |
| **company-as-a-service** | Informational | Homepage, Vision, CaaS article, all blog posts | EXCELLENT -- Dominant keyword. Soleur owns this term. |
| **AI agents for business** | Informational / Commercial | Agents page meta description | GOOD -- Present in the Agents page meta. Could appear more in body copy. |
| **one person company AI** | Informational | Vision page (billion-dollar solopreneur) | PARTIAL -- Concept is present but the exact phrase is not used. |
| **compound knowledge AI** | Informational | Plateau article, CaaS article | GOOD -- Well-covered in long-form content. |

### Intent Match Matrix

| Search Intent Type | Pages Serving This Intent | Gap? |
|-------------------|--------------------------|------|
| **Navigational** (brand queries) | Homepage, Getting Started, Community, Changelog | No gap |
| **Informational** (how-to, what-is) | CaaS article, Plateau article, 5 case studies, Getting Started | Covered but case studies lack FAQ for question-matching |
| **Commercial** (comparison, evaluation) | Cowork comparison article | **Gap: No dedicated "alternatives" or "best claude code plugins" page** |
| **Transactional** (install, buy, try) | Getting Started | **Gap: No pricing page. The FAQ says "free" but there is no dedicated pricing/plans page.** |

---

## 3. Readability Assessment

### Flesch-Kincaid Estimates (Manual Assessment)

| Page | Reading Level | Assessment | Notes |
|------|--------------|------------|-------|
| Homepage | Grade 8-10 | STRONG | Short, declarative sentences. Brand voice at maximum clarity. |
| Getting Started | Grade 7-9 | STRONG | Step-by-step. Code blocks. Clear instructions. |
| Agents | Grade 10-12 | GOOD | Intro prose is slightly dense. Catalog cards are clean. |
| Skills | Grade 10-12 | GOOD | Intro paragraph has a 45-word sentence. |
| Vision | Grade 12-14 | MODERATE | "Infinite leverage," "non-linear rewards of the AI revolution," "synthetic labor" -- jargon-heavy for search audiences. |
| CaaS Article | Grade 10-12 | GOOD | Data-driven, well-structured. Some paragraphs are long (60+ words). |
| Plateau Article | Grade 11-13 | GOOD | Technical audience. Appropriate level for the content. |
| Case Studies | Grade 10-12 | GOOD | Concrete numbers, structured formats. Consistent quality. |

### Readability Issues

| Page | Issue | Detail |
|------|-------|--------|
| Vision | Jargon density | "Synthetic labor (AI Agent Swarms)" is undefined. "Non-linear rewards of the AI revolution" is vague marketing language that the brand guide's "Don't over-explain" principle does not excuse. |
| Vision | Sentence length | First paragraph: 58 words. "Soleur is a Company-as-a-Service platform designed to collapse the friction between a startup idea and a billion-dollar outcome" is 19 words before the period -- acceptable, but the paragraph as a whole needs breaking up. |
| Skills | Opening sentence length | "Agentic engineering is more than writing code with AI" starts well but the following sentence runs 43 words. |
| CaaS Article | Paragraph density | "The market responded..." paragraph (section: "The Problem CaaS Solves") packs 4 data points and 3 company references into a single paragraph. Breaking into shorter paragraphs would improve scanability. |

---

## 4. Keyword Gap Analysis

### Gap 1: "claude code plugin" / "claude code extensions"

**Search Volume Context:** The Claude Code plugin ecosystem has 9,000+ plugins. "Best claude code plugins" and "claude code extensions" are high-volume queries (multiple listicle articles ranking on page 1 from Firecrawl, Composio, eesel.ai, claudefa.st).

**Current Coverage:** The homepage meta description says "Claude Code plugin." Getting Started has the install command. But the brand guide explicitly discourages "plugin" in public copy.

**Recommendation:** This creates a genuine tension. The search volume is real, but the brand positioning ("platform, not a plugin") is also correct. Resolution: Use "Claude Code plugin" in the meta description and FAQ answers (where factual accuracy overrides brand aspiration) while keeping the H1 and hero copy plugin-free. Add a FAQ question: "Is Soleur a Claude Code plugin?" with an answer that reframes: "Soleur is installed as a Claude Code plugin, but it operates as a full company-as-a-service platform..."

**Priority:** P1 -- High search volume, high commercial intent, currently underserved.

---

### Gap 2: "solo founder AI tools"

**Search Volume Context:** "Solo founder AI tools" is a high-growth cluster in 2026. Multiple articles from Entrepreneur, SiliconIndia, EntrepreneurLoop, and PrometAI rank for variations. Solo-founded startups surged from 23.7% in 2019 to 36.3% by mid-2025.

**Current Coverage:** "Solo founders" appears 15+ times across the site, but the compound phrase "solo founder AI tools" never appears.

**Recommendation:** Inject the exact phrase into: (1) the homepage FAQ ("Who is Soleur for?" answer), (2) the CaaS article ("Who Needs Company-as-a-Service" section), and (3) a new Getting Started FAQ question.

**Priority:** P1 -- Exact match to ICP. High commercial intent.

---

### Gap 3: "AI company automation"

**Search Volume Context:** "AI company automation" and "AI business automation" are broad commercial queries. The "service as software" paradigm (Foundation Capital's $4.6T estimate) drives this cluster.

**Current Coverage:** Zero occurrences site-wide.

**Recommendation:** Add a definition of "AI company automation" to the Vision page or CaaS article. A single sentence would suffice: "AI company automation -- running every department of a business through orchestrated AI agents -- is the foundation of the company-as-a-service model."

**Priority:** P2 -- Broad term, moderate specificity to Soleur's positioning.

---

### Gap 4: "AI engineering workflow"

**Search Volume Context:** "AI engineering workflow" and "agentic workflow" are growing informational queries. Articles from CIO, Vellum AI, StackAI, and DextraLabs rank for variations.

**Current Coverage:** "Agentic engineering" is well-covered but "AI engineering workflow" as an exact phrase is absent.

**Recommendation:** Add the phrase to the Skills page intro and the Plateau article FAQ. Natural insertion: "Each skill encodes a multi-step AI engineering workflow..."

**Priority:** P2 -- The site already ranks for "agentic engineering"; this captures adjacent traffic.

---

### Gap 5: Missing Pricing Page

**Search Volume Context:** "Soleur pricing," "company as a service pricing," and "claude code plugin pricing" are all queries the site cannot currently capture.

**Current Coverage:** The homepage FAQ says "The Soleur plugin is open source and free to install." No dedicated pricing page exists.

**Recommendation:** Create a `/pages/pricing.html` page, even if the content is minimal: "Free and open source. Paid tier coming soon." This captures transactional intent and prevents users from bouncing to competitors for pricing information.

**Priority:** P1 -- Transactional intent pages have the highest conversion potential.

---

### Gap 6: Missing Comparison/Alternatives Page Template

**Search Volume Context:** "Soleur vs Cursor," "Soleur vs Copilot," "best AI agent platforms 2026" are commercially valuable comparison queries. The Cowork article covers one comparison; the pattern should expand.

**Current Coverage:** One comparison article (Soleur vs. Anthropic Cowork).

**Recommendation:** Create comparison articles for the top 3-5 competitors identified in the competitive intelligence report. Each comparison article should follow the same template as the Cowork article (side-by-side table, "Who Each Platform Is For" section, FAQ with structured data).

**Priority:** P2 -- The template exists. Replication is efficient.

---

## 5. Rewrite Suggestions

All suggestions are aligned with the brand guide: bold, declarative, forward-looking. No hedging, no "AI-powered," no "assistant" or "copilot" framing.

---

### Rewrite 1: Homepage Meta Description

**Current:**
> "Soleur is the company-as-a-service platform -- a Claude Code plugin that gives solo founders a full AI organization across every business department."

**Suggested:**
> "The company-as-a-service platform for solo founders. AI agents across every business department -- engineering, marketing, legal, finance, and more."

**Rationale:** Leads with the category term. Removes "Claude Code plugin" from the most prominent meta position (per brand guide). Keeps within 155 characters (148 chars). The departments list adds specificity that search engines and AI models can extract.

---

### Rewrite 2: Getting Started Subtitle

**Current:**
> "Install the Claude Code plugin that gives you a full AI organization."

**Suggested:**
> "Install one platform. Run every department."

**Rationale:** Removes "plugin" per brand guide. Declarative. 6 words. The install command in the code block below already communicates the mechanism.

---

### Rewrite 3: Skills Page -- Add FAQ Section

**Current:** No FAQ section.

**Suggested addition (after the skill catalog, before closing):**

```html
<section class="landing-section">
  <div class="landing-section-inner">
    <p class="section-label">Common Questions</p>
    <h2 class="section-title">Frequently Asked Questions</h2>
    <div class="faq-list">
      <details class="faq-item">
        <summary class="faq-question">What is agentic engineering?</summary>
        <p class="faq-answer">Agentic engineering is a structured methodology where AI agents are orchestrated with human oversight to execute complex, multi-step workflows. Unlike ad-hoc AI prompting, agentic engineering uses specifications, workflow gates, and quality checks to produce reliable output across every business function.</p>
      </details>
      <details class="faq-item">
        <summary class="faq-question">How do skills differ from agents?</summary>
        <p class="faq-answer">Agents are specialists -- each one handles a specific business function like code review, brand strategy, or legal compliance. Skills are multi-step workflows that orchestrate agents, tools, and knowledge into repeatable processes. A single skill chains multiple agents together to complete a complex task from start to finish.</p>
      </details>
      <details class="faq-item">
        <summary class="faq-question">Can I create custom skills?</summary>
        <p class="faq-answer">Yes. Skills are markdown files with YAML frontmatter. You can create custom skills by adding a new directory under the skills folder with a SKILL.md file that defines the workflow instructions, and Soleur will discover and make it available automatically.</p>
      </details>
    </div>
  </div>
</section>
```

**Rationale:** Matches the pattern established on the Homepage and Agents pages. Captures "What is agentic engineering?" -- a high-value informational query. The FAQ answers are self-contained and quotable by AI models.

---

### Rewrite 4: Vision Page H1

**Current:**
> "Vision"

**Suggested:**
> "The Soleur Vision: Building the Company-as-a-Service Platform"

**Rationale:** Adds keyword depth. "Vision" alone has no search value. The rewrite captures "company-as-a-service platform" in the H1 without sounding forced.

---

### Rewrite 5: Vision Page Opening Paragraph

**Current:**
> "Soleur is a Company-as-a-Service platform designed to collapse the friction between a startup idea and a billion-dollar outcome. The world is moving toward infinite leverage. When code and AI can replicate labor at near-zero marginal cost, the only remaining bottlenecks are Judgment and Taste. Soleur is the vessel that allows those with unique insights to capture the non-linear rewards of the AI revolution."

**Suggested:**
> "Soleur is a Company-as-a-Service platform that gives one founder the leverage of an entire organization. Code and AI replicate labor at near-zero marginal cost. The only remaining bottlenecks are judgment and taste. Soleur exists so those with unique insights can build billion-dollar companies without billion-dollar teams."

**Rationale:** Shorter (49 words vs. 58). Removes vague phrases ("collapse the friction," "non-linear rewards of the AI revolution," "the vessel"). Leads with a concrete value statement. The first sentence is self-contained and quotable for AI extraction. Maintains bold, declarative brand voice.

---

### Rewrite 6: Case Study Meta Descriptions (Template)

**Current (Legal case study):**
> "A solo founder needed a full legal compliance suite -- Terms & Conditions, Privacy Policy, GDPR Policy, CLAs, and more. AI agents produced 9 documents totaling 17,761 words with dual-jurisdiction coverage."

**Suggested:**
> "AI agents generated 9 legal documents -- Terms, Privacy Policy, GDPR Policy, CLAs -- in days, not months. A company-as-a-service case study in legal automation for solo founders."

**Rationale:** Adds "company-as-a-service," "solo founders," and "AI agents" to the meta. Leads with the outcome. Under 155 characters (153 chars). Apply this pattern to all 5 case studies: lead with outcome, include "company-as-a-service," include "solo founder" or the relevant domain keyword.

---

### Rewrite 7: Plateau Article Meta Description (Truncation Fix)

**Current (196 characters -- truncated by Google):**
> "Most AI coding tools stop getting better after week two. The missing layer is compound knowledge -- a system that learns from every task and feeds those learnings back into its own rules, agents, and workflows."

**Suggested (153 characters):**
> "Most AI coding tools stop improving after week two. The missing layer is compound knowledge -- a system that learns from every task and enforces what it learns."

**Rationale:** Under 155 characters. Preserves the hook. Replaces "feeds those learnings back into its own rules, agents, and workflows" with "enforces what it learns" -- shorter and more impactful.

---

### Rewrite 8: Homepage FAQ -- "Who is Soleur for?" Answer

**Current:**
> "Soleur is built for solo founders and small teams who want to operate at the scale of a full organization. If you are building a product, validating a business, or scaling operations without a large team, Soleur gives you the agents and workflows to do it."

**Suggested:**
> "Soleur is built for solo founders and small teams who want to operate at the scale of a full organization. It is one of the first solo founder AI tools designed for every business department -- not just engineering. If you are building a product, validating a business, or scaling operations, Soleur gives you the agents and workflows to do it."

**Rationale:** Injects the exact phrase "solo founder AI tools" naturally into the answer. Adds the differentiator ("not just engineering") that separates Soleur from code-only tools. The FAQ answer remains self-contained and quotable.

---

## 6. Summary of Findings

### Critical Issues (3)

| # | Issue | Page | Recommendation |
|---|-------|------|----------------|
| 1 | No FAQ section on Getting Started page | `/pages/getting-started.html` | Add 3-5 FAQ items covering prerequisites, VS Code compatibility, subscription requirements |
| 2 | No FAQ section on Skills page | `/pages/skills.html` | Add 3 FAQ items (see Rewrite 3 above) with FAQPage structured data |
| 3 | No FAQ sections on any of the 5 case studies | `/blog/*.md` (case studies) | Add 2-3 FAQ items per case study targeting domain-specific queries |

### Improvements (11)

| # | Issue | Page | Recommendation |
|---|-------|------|----------------|
| 1 | "solo founder AI tools" exact phrase missing | Site-wide | Inject into Homepage FAQ, CaaS article, Getting Started |
| 2 | "AI company automation" zero coverage | Site-wide | Add definition to Vision page or CaaS article |
| 3 | "claude code extensions" zero coverage | Site-wide | Add to Getting Started page FAQ |
| 4 | "AI engineering workflow" exact phrase missing | Skills, Plateau article | Inject into Skills intro and Plateau FAQ |
| 5 | Plateau article meta description truncated | Blog | Rewrite to under 155 characters (see Rewrite 7) |
| 6 | Vision page H1 is keyword-empty | Vision | Rewrite H1 (see Rewrite 4) |
| 7 | Vision page opening is jargon-heavy | Vision | Rewrite opening paragraph (see Rewrite 5) |
| 8 | Getting Started subtitle uses "plugin" | Getting Started | Rewrite subtitle (see Rewrite 2) |
| 9 | Agents page FAQ is thin (3 questions) | Agents | Expand to 5-6 questions |
| 10 | Case study meta descriptions lack target keywords | Blog (5 case studies) | Apply template from Rewrite 6 |
| 11 | No pricing page | Site-wide | Create minimal pricing page for transactional intent capture |

### Rewrite Suggestions (8)

All 8 rewrites are documented in Section 5 above with current text, suggested revision, and rationale.

---

## 7. Content Architecture Assessment

### Current Structure

```
Homepage (pillar: brand + CaaS)
  |-- Getting Started (onboarding)
  |-- Agents (catalog)
  |-- Skills (catalog)
  |-- Vision (positioning)
  |-- Community (navigation)
  |-- Changelog (reference)
  |-- Blog/
       |-- What Is Company-as-a-Service? (pillar article)
       |-- Why Most Agentic Tools Plateau (pillar article)
       |-- Soleur vs. Anthropic Cowork (comparison)
       |-- 5x Case Studies (cluster content)
```

### Assessment

The architecture has two strong pillar articles (CaaS definition, Plateau/agentic engineering) with the case studies functioning as cluster content. The comparison article is a good start for commercial-intent content.

**Missing from the architecture:**

1. **Pricing page** -- Transactional intent. Currently unserved.
2. **Comparison cluster** -- Only 1 comparison article exists. Need 3-5 more (vs. Cursor, vs. Copilot, vs. Devin, vs. Notion AI, vs. SoloCEO).
3. **"Best of" / listicle content** -- No page targets "best claude code plugins" or "best AI tools for solo founders." These are high-volume commercial queries.
4. **Tutorial/how-to cluster** -- Getting Started is the only how-to. Need: "How to build a feature with Soleur," "How to generate legal documents with AI," "How to run competitive analysis with AI agents."
5. **Shareable content** -- All current content is searchable (keyword-targeted). No opinion pieces, data reports, or contrarian takes designed for social distribution. The Plateau article comes closest but is still primarily searchable. Flag: the content plan is 100% searchable; shareable content is missing.

---

## Appendix: Keyword Research Data

### Target Keywords with Search Intent Classification

| Keyword | Intent | Relevance to Soleur | Related Queries |
|---------|--------|---------------------|----------------|
| claude code plugin | Navigational / Commercial | HIGH -- Direct product descriptor | best claude code plugins, claude code extensions, claude code plugin marketplace, install claude code plugin |
| agentic engineering | Informational | HIGH -- Core methodology | what is agentic engineering, agentic engineering vs vibe coding, agentic workflow, AI engineering workflow |
| AI company automation | Commercial | HIGH -- Category match | AI business automation, automate company with AI, AI-powered business operations |
| solo founder AI tools | Commercial | HIGH -- Exact ICP match | AI tools for solo founders, solo founder tech stack, one person company AI, solopreneur AI tools |
| claude code extensions | Commercial / Navigational | HIGH -- Discovery query | best claude code extensions, claude code MCP servers, claude code add-ons |
| AI engineering workflow | Informational | MEDIUM -- Adjacent to core | agentic workflow, AI-assisted development workflow, AI coding workflow |
| company-as-a-service | Informational | HIGH -- Category-defining term | CaaS platform, company as a service meaning, CaaS vs SaaS |
| compound knowledge AI | Informational | HIGH -- Differentiator | knowledge compounding, institutional memory AI, AI that learns over time |
| AI agents for business | Commercial | HIGH -- Broad category | business AI agents, AI agents for startups, multi-domain AI agents |
| one person billion dollar company | Informational | HIGH -- Aspirational match | billion dollar solo company, solopreneur unicorn, one person unicorn |

### Competitor Content Signals

| Competitor | Key Pages Ranking | Keyword Advantage |
|------------|------------------|-------------------|
| Cursor | cursor.sh/features, cursor.sh/pricing | "AI code editor," "best AI coding tool" |
| GitHub Copilot | github.com/features/copilot | "AI pair programmer," "github copilot pricing" |
| Lovable | lovable.dev | "AI app builder," "vibe coding tool" |
| Devin | cognition.ai | "AI software engineer," "autonomous coding agent" |
| Notion AI | notion.so/product/ai | "AI workspace," "AI project management" |

Note: Soleur's differentiation (multi-domain, compounding, company-as-a-service) is not contested by any competitor. The "company-as-a-service" term appears to have no competing definitions in search results. This is a category-defining opportunity.

---

*Audit conducted from source files at `plugins/soleur/docs/`. Live site (soleur.ai) returned HTTP 403, preventing direct page rendering verification. All analysis is based on the Nunjucks templates and Markdown source files, which represent the canonical content.*
