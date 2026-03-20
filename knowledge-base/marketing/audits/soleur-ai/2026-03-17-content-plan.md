# Soleur.ai Prioritized Content Plan

**Date:** 2026-03-17
**Inputs:** Content audit, AEO audit, SEO audit (all 2026-03-17), keyword research, competitor analysis
**Brand guide:** `knowledge-base/marketing/brand-guide.md` (last reviewed 2026-03-02)

---

## 1. Keyword Research Findings

### Primary Keywords

| Keyword / Phrase | Search Intent | Volume Signal | Relevance | Competition | Notes |
|---|---|---|---|---|---|
| company-as-a-service | Informational | Low-Medium | HIGH | Very Low | Category-defining. No competitor owns this term. |
| one person billion dollar company | Informational | HIGH | HIGH | Medium | Massive search volume in 2026. Amodei, Altman predictions. |
| AI agents for solo founders | Commercial | HIGH | HIGH | Medium-High | Listicle-dominated SERP. Soleur does not appear in any lists. |
| AI agents for business | Commercial | HIGH | MEDIUM | High | Broad query. Dominated by Arahi, Lindy, Kore.ai, Make, Gumloop. |
| Claude Code plugin | Navigational | MEDIUM | HIGH | Low | 834+ plugins across 43 marketplaces as of January 2026. |
| agentic engineering | Informational | HIGH | HIGH | Medium | Coined by Karpathy Feb 2025, mainstream by 2026. |
| vibe coding vs agentic engineering | Informational | HIGH | HIGH | Medium | Trending comparison query. |
| solopreneur AI tools 2026 | Commercial | HIGH | HIGH | High | Dominated by listicles. Soleur absent from all. |
| open source AI agent platform | Commercial | MEDIUM | HIGH | Medium | n8n, AutoGen dominate. |
| compound engineering | Informational | Low | HIGH | Very Low | Niche term coined by Every Inc. |
| AI workflow automation | Commercial | HIGH | MEDIUM | High | Dominated by Make, Zapier, n8n, Gumloop. |

### Secondary Keywords

| Keyword / Phrase | Search Intent | Volume Signal | Relevance | Competition |
|---|---|---|---|---|
| Soleur vs Cowork | Commercial | Low-Medium | HIGH | Very Low |
| Soleur vs Cursor | Commercial | Low | HIGH | Very Low |
| Soleur vs Polsia | Commercial | Low | HIGH | Very Low |
| AI legal document generator | Commercial | MEDIUM | MEDIUM | Medium |
| AI competitive intelligence tools | Commercial | MEDIUM | MEDIUM | High |
| AI marketing for startups | Commercial | HIGH | MEDIUM | High |
| business validation AI | Commercial | Low | MEDIUM | Low |
| Claude Code best plugins 2026 | Commercial | MEDIUM | HIGH | Medium |
| agentic coding best practices | Informational | MEDIUM | HIGH | Medium |
| AI co-founder tools | Commercial | MEDIUM | HIGH | Medium |
| self-running company AI | Informational | Low-Medium | HIGH | Low |

---

## 2. Competitor Gap Analysis

### Direct Competitors

| Competitor | Strengths | Weaknesses | Content Gap for Soleur |
|---|---|---|---|
| **Anthropic Cowork** | Massive brand authority. TechCrunch coverage. Non-technical user target. | Closed-source. No compounding knowledge. Single-domain. | No "Cowork alternatives" article to capture that SERP. |
| **Polsia** | Aggressive positioning. Product Hunt presence. $450K+ ARR. | Opaque pricing ($49 for 5 credits). No open-source. No content library. | No comparison article vs Polsia. Same ICP. |
| **Cursor** | $2B+ ARR. Massive developer adoption. | Coding-only. No cross-department capability. | No dedicated comparison article. |
| **Make/Zapier** | Massive integration ecosystems (3000+). | Workflow automation only, not agentic. | No content distinguishing agent orchestration from workflow automation. |
| **Lindy** | Strong positioning as "team of AI assistants." | Expensive. Credit-based pricing. No compound knowledge. | No comparison content exists. |

### Listicle Presence Gap (CRITICAL)

Soleur appears on **zero** of the major "best AI agent" and "solo founder tools" listicles. This is the single largest discoverability gap.

---

## 3. Content Architecture: Pillar/Cluster Model

### Pillar 1: Company-as-a-Service (EXISTS -- needs expansion)

- **Pillar page:** "What Is Company-as-a-Service?" (exists, SAP score 5.0/5.0)
- **Cluster pages needed:**
  - "One-Person Billion-Dollar Company: The Complete Guide" (NEW)
  - "Company-as-a-Service vs SaaS: How CaaS Changes the Game" (NEW)
  - "Self-Running Company: Can AI Actually Run Your Business?" (NEW)

### Pillar 2: Agentic Engineering (EXISTS -- needs expansion)

- **Pillar page:** "Why Most Agentic Engineering Tools Plateau" (exists, SAP score 4.8/5.0)
- **Cluster pages needed:**
  - "Vibe Coding vs Agentic Engineering: The Complete Comparison" (NEW)
  - "Agentic Engineering Best Practices for Solo Founders" (NEW)
  - "Compound Engineering: How Every Project Makes the Next One Easier" (NEW)

### Pillar 3: AI Agents for Solo Founders (DOES NOT EXIST)

- **Pillar page:** "AI Agents for Solo Founders: The Definitive Guide" (NEW)
- **Cluster pages needed:**
  - "Soleur vs Polsia: Open-Source vs Autonomous AI Platforms" (NEW)
  - "Soleur vs Cursor: Full AI Organization vs Code-Only Assistant" (NEW)
  - "Best Claude Code Plugins for Solo Founders in 2026" (NEW)
  - "Solo Founder Tech Stack 2026: AI Tools That Replace a Full Team" (NEW)

---

## 4. Prioritized Content Plan

### P1: CRITICAL -- Fix Immediately for Discoverability

#### P1-1: Add JSON-LD FAQPage schema to agents page and "Why Tools Plateau" blog post

**Type:** Existing content fix
**Target keywords:** AI agents for business, agentic engineering, compound engineering
**Files:** `agents.njk`, `why-most-agentic-tools-plateau.md`
**Rationale:** Lowest-effort, highest-impact fix. Both have FAQ content but no JSON-LD.

#### P1-2: Add FAQ sections with JSON-LD to all 5 case studies

**Type:** Existing content fix
**Target keywords:** AI legal document generator, AI competitive intelligence, business validation AI
**Files:** All 5 `case-study-*.md` files
**Rationale:** Five pages with zero FAQ presence. Adding 3-5 FAQs per post creates 15-25 new FAQ entries.

#### P1-3: Remove "plugin" from homepage and getting-started meta descriptions

**Type:** Existing content fix (brand guide alignment)
**Files:** `index.njk`, `getting-started.md`
**Rationale:** Brand guide violation on the two highest-traffic pages.

**Rewrites:**
- Homepage meta: "Soleur is the open-source company-as-a-service platform -- a full AI organization that gives solo founders and solopreneurs agents across every business department."
- Getting started meta: "Get started with Soleur in one command. Deploy AI agents for engineering, marketing, legal, finance, and every business department -- the company-as-a-service platform for solo founders."

#### P1-4: Rewrite Vision page H1 and add keyword-bearing content

**Type:** Existing content fix
**File:** `vision.njk`
**Rationale:** Largest content page has a one-word H1 ("Vision") with zero keyword value, zero citations, SAP score 1.8/5.0.

#### P1-5: Add `updated` frontmatter and visible "Last Updated" display to blog posts

**Type:** Template and content fix
**Files:** `blog-post.njk` template, all 8 blog posts
**Rationale:** No blog post has `dateModified` signaling. Google uses this for freshness assessment.

#### P1-6: Add "open source" and "solopreneur" to homepage

**Type:** Existing content fix
**File:** `index.njk`
**Rationale:** Key differentiator (open source) and high-volume keyword variant (solopreneur) both missing.

---

### P2: IMPORTANT -- Improve Ranking and AI Citation Probability

#### P2-1: NEW ARTICLE -- "Vibe Coding vs Agentic Engineering: What Solo Founders Need to Know"

**Target keywords:** vibe coding vs agentic engineering, agentic coding, compound engineering
**Scoring:** 18/20 (Customer Impact: 4, Content-Market Fit: 5, Search Potential: 5, Resource Cost: 4)

#### P2-2: NEW ARTICLE -- "AI Agents for Solo Founders: The Definitive Guide (2026)"

**Target keywords:** AI agents for solo founders, solopreneur AI tools 2026, solo founder tech stack
**Scoring:** 18/20
**Note:** Single most important new article. Soleur appears on zero listicles for this query.

#### P2-3: NEW ARTICLE -- "Soleur vs Polsia: Open-Source AI Organization vs Autonomous Operations"

**Target keywords:** Soleur vs Polsia, AI company automation, self-running company
**Scoring:** 16/20

#### P2-4: NEW ARTICLE -- "Soleur vs Cursor (2026): Full AI Organization vs Code-Only Assistant"

**Target keywords:** Soleur vs Cursor, open source alternative to Cursor
**Scoring:** 16/20

#### P2-5: Add external citations to all non-blog pages

**Rationale:** 12 of 15 pages have zero external citations. Stark binary split identified in AEO audit.

#### P2-6: Add definition paragraphs for key terms on catalog pages

**Definitions to add:**
- **Agents page:** "Agentic engineering is the practice of orchestrating AI agents that can execute, test, and refine work autonomously."
- **Skills page:** "In Soleur, a skill is a multi-step workflow that chains agents, tools, and verification loops into a repeatable automation."

#### P2-7: Add FAQ sections to Skills, Getting Started, and Community pages

**Rationale:** 9 of 15 pages have no FAQ section.

#### P2-8: Add internal cross-links between case studies

#### P2-9: Create About/Founder page

**Rationale:** No About page exists. Significant E-E-A-T gap flagged by both AEO and SEO audits.

#### P2-10: Add page-specific OG images for pillar blog posts

---

### P3: NICE-TO-HAVE -- Long-Term Content Strategy

#### P3-1: NEW ARTICLE -- "The One-Person Billion-Dollar Company: A Complete Guide"

**Target keywords:** one person billion dollar company, billion dollar solopreneur
**Classification:** Shareable (high social distribution potential)

#### P3-2: NEW ARTICLE -- "Best Claude Code Plugins for Solo Founders (2026)"

**Target keywords:** best Claude Code plugins, Claude Code plugin marketplace

#### P3-3: NEW ARTICLE -- "Company-as-a-Service vs SaaS: How CaaS Changes Everything"

**Target keywords:** company-as-a-service vs SaaS, CaaS platform, future of SaaS

#### P3-4: NEW ARTICLE -- "Compound Engineering: How Every Project Makes the Next One Easier"

**Target keywords:** compound engineering, compound knowledge base, compounding AI systems

#### P3-5: Update Cowork comparison title to include "(2026)"

#### P3-6: Rewrite changelog meta description

#### P3-7: Add keyword context to community page

#### P3-8: Add explicit AI crawler entries to robots.txt

#### P3-9: Stagger case study publication dates

---

## 5. Off-Site Strategy

### OS-1: Third-Party Listicle Outreach (CRITICAL)

Soleur appears on **zero** listicles. Target publications:
1. TLDL -- "Best AI Agents for Solo Founders in 2026"
2. Entrepreneur.com -- "AI Tools for Solopreneurs" series
3. Taskade -- "12 Best Agentic Engineering Platforms"
4. o-mega.ai -- "Top 10 Claude Cowork Alternatives"
5. AIMultiple -- "Compare 50+ AI Agent Tools"

### OS-2: Product Hunt Launch

### OS-3: Hacker News Submission

### OS-4: Citation Monitoring Protocol

Monthly query test: ChatGPT, Perplexity, Claude, Gemini with target queries.

### OS-5: GitHub Awesome List Submissions

---

## 6. Implementation Timeline

| Week | Actions |
|---|---|
| **Week 1** | P1-1 through P1-6 (all existing content fixes) |
| **Week 2** | P2-1 (Vibe Coding vs Agentic Engineering). P2-5 (citations). P2-6 (definitions). |
| **Week 3** | P2-2 (AI Agents for Solo Founders pillar). P2-7 (FAQ sections). P2-8 (cross-links). |
| **Week 4** | P2-3 (Soleur vs Polsia). P2-9 (About page). OS-1 (listicle outreach). |
| **Week 5** | P2-4 (Soleur vs Cursor). P2-10 (OG images). OS-2 (Product Hunt prep). |
| **Week 6+** | P3 items. OS-3 (HN submission). OS-4 (citation monitoring). |

---

## 7. Success Metrics

| Metric | Current State | Target (90 days) |
|---|---|---|
| Pages with FAQ + JSON-LD | 3 of 15 | 15 of 15 |
| Pages with external citations | 3 of 15 | 12 of 15 |
| AEO SAP score (site average) | 2.8 / 5.0 | 3.8 / 5.0 |
| Third-party listicle appearances | 0 | 3-5 |
| AI citation rate (monthly query test) | Unknown | Baseline established + tracked |
| Blog posts targeting high-volume keywords | 3 | 10 |
| Comparison articles (vs competitors) | 1 | 4 |

---

## Sources Consulted

- [Anthropic 2026 Agentic Coding Trends Report](https://resources.anthropic.com/2026-agentic-coding-trends-report)
- [CIO -- How Agentic AI Will Reshape Engineering Workflows](https://www.cio.com/article/4134741/how-agentic-ai-will-reshape-engineering-workflows-in-2026.html)
- [The New Stack -- From Vibe Coding to Agentic Engineering](https://thenewstack.io/vibe-coding-agentic-engineering/)
- [Addy Osmani -- Agentic Engineering](https://addyosmani.com/blog/agentic-engineering/)
- [IBM -- What Is Agentic Engineering](https://www.ibm.com/think/topics/agentic-engineering)
- [Entrepreneur -- 7 AI Tools Solopreneurs Need for 2026](https://www.entrepreneur.com/science-technology/7-ai-tools-solopreneurs-need-for-2026-to-hit-7-figures/499925)
- [TLDL -- Best AI Agents for Solo Founders](https://www.tldl.io/resources/best-ai-agents-for-solo-founders)
- [Inc -- Amodei Predicts Billion-Dollar Solopreneur by 2026](https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609)
- [Every.to -- The One-Person Billion-Dollar Company](https://every.to/napkin-math/the-one-person-billion-dollar-company)
- [o-mega.ai -- Top 10 Claude Cowork Alternatives](https://o-mega.ai/articles/top-10-claude-cowork-ai-agent-alternatives-2026-guide)
- [Polsia](https://polsia.com/)
- [Arahi AI -- Best AI Agents for Business 2026](https://www.arahi.ai/blog/best-ai-agents-for-business-2026)
- [Taskade -- 12 Best Agentic Engineering Platforms](https://www.taskade.com/blog/agentic-engineering-platforms)
- [NxCode -- Agentic Engineering Complete Guide](https://www.nxcode.io/resources/news/agentic-engineering-complete-guide-vibe-coding-ai-agents-2026)
- [Marketer Milk -- 13 Best AI Agent Platforms](https://www.marketermilk.com/blog/best-ai-agent-platforms)
