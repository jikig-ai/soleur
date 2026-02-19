---
title: "Soleur.ai Content Audit: Keyword Alignment & Search Intent Analysis"
date: 2026-02-19
tool: growth-strategist (audit sub-command)
target: https://soleur.ai
issue: "#153"
---

# Soleur.ai Content Audit: Keyword Alignment & Search Intent Analysis

## Executive Summary

The soleur.ai website has strong brand voice and internal consistency, but it operates in a near-total keyword vacuum for the terms that would drive organic discovery. The site's core positioning keywords -- "agentic company", "agentic engineering", "company as a service", "AI company", "solo founder" -- appear **zero times** in the visible body copy across all five pages. The content speaks powerfully to people who already know what Soleur is, but is nearly invisible to anyone searching for the problems it solves.

---

## 1. Per-Page Keyword Analysis

### 1.1 Homepage (`index.html`)

**Apparent target keywords:** None explicitly targeted. The page reads as a brand manifesto, not a search-optimized landing page.

| Keyword/Phrase | Occurrences in Body Copy | Assessment |
|---|---|---|
| "company as a service" / "company-as-a-service" | 1 (badge only, not in prose) | Present but not in any H1, H2, or paragraph text that search engines weight heavily |
| "agentic company" | 0 | Completely absent |
| "agentic engineering" | 0 | Completely absent |
| "AI company" | 0 | Completely absent |
| "solo founder" | 0 | Completely absent |
| "AI agents" | 1 (stats strip label) | Minimal; not in any heading or descriptive paragraph |
| "AI organization" | 2 (section desc, feature label) | Reasonable coverage but never in an H1 or H2 |
| "billion-dollar company" | 1 (H1) | Strong placement |
| "Claude Code" | 0 | The product category is never named |
| "Claude Code plugin" | 0 | Absent from all body copy |
| "build ship scale" | 1 (hero sub) | Present but generic |
| "knowledge compounding" | 1 (stats label) | Present as a label, not in descriptive text |

**Copy alignment score: 2/10.** The H1 is memorable but targets no searchable query. Nobody searches "build a billion-dollar company alone" -- they search "AI tools for solo founders", "agentic engineering platform", or "company as a service". The hero subheadline is generic and could describe any SaaS product.

### 1.2 Agents Page (`pages/agents.html`)

**Apparent target keywords:** "agents", "code review", "architecture", "infrastructure"

| Keyword/Phrase | Occurrences | Assessment |
|---|---|---|
| "AI agents" | 0 in headings; individual agents are listed but the term "AI agent" itself is absent from the page hero | The H1 is just "Agents" -- no modifier |
| "code review agents" | 0 as a phrase | Individual agents describe review tasks but the page never says "code review agents" |
| "Claude Code agents" | 0 | Product category completely absent |
| "agentic engineering" | 0 | Absent |
| "AI engineering team" | 0 | Absent |

**Copy alignment score: 3/10.** The page is a catalog with no introductory prose that could rank for informational queries. The hero paragraph is one sentence of product description with no search-intent language.

### 1.3 Skills Page (`pages/skills.html`)

**Apparent target keywords:** "skills", "development", "deployment"

| Keyword/Phrase | Occurrences | Assessment |
|---|---|---|
| "AI skills" | 0 | The H1 is bare "Skills" |
| "Claude Code skills" | 0 | Absent |
| "automated workflows" | 0 | Absent |
| "AI-powered development" | 0 | Absent |

**Copy alignment score: 2/10.** Same structural problem as the Agents page -- a bare catalog with no contextualizing prose. The hero text ("41 specialized skills for development, content, deployment, and more") is the only descriptive sentence.

### 1.4 Getting Started Page (`pages/getting-started.html`)

**Apparent target keywords:** "getting started", "install"

| Keyword/Phrase | Occurrences | Assessment |
|---|---|---|
| "Claude Code plugin" | 0 in body text | The install command says `claude plugin install soleur` but the page never explains what Claude Code is |
| "how to install" | 0 | No instructional framing |
| "AI development workflow" | 0 | Absent |
| "solo founder" | 0 | Absent |

**Copy alignment score: 2/10.** The page assumes the reader already knows what Claude Code is and what Soleur does. No contextual setup, no "What is Soleur?" paragraph. A visitor arriving from search would not understand the product category.

### 1.5 Changelog Page (`pages/changelog.html`)

**Apparent target keywords:** "changelog" (unintentionally)

**Copy alignment score: 1/10.** Pure release notes. This is appropriate for a changelog, but the page has no introductory copy that could provide search context. Not a discoverability concern -- changelogs should not be keyword-optimized.

---

## 2. Search Intent Match Analysis

| Page | Detected Intent Match | Ideal Intent Match | Gap |
|---|---|---|---|
| Homepage | **Navigational** (branded search for "Soleur") | **Commercial investigation** + **Navigational** ("AI agent platform for solo founders", "company as a service platform") | Homepage only serves people who already know the brand name. It does nothing for discovery queries. |
| Agents | **Navigational** (people looking for the agents page specifically) | **Informational** + **Commercial** ("what are AI coding agents", "best AI agents for code review") | No informational content. No explanatory text. No comparison or evaluation language. |
| Skills | **Navigational** | **Informational** + **Commercial** ("AI workflow automation skills", "automated code review and deployment") | Same as Agents. Catalog without context. |
| Getting Started | **Transactional** (install instructions) | **Transactional** + **Informational** ("how to set up AI coding agents", "Claude Code plugin setup") | Correctly transactional but assumes too much prior knowledge. |
| Changelog | **Navigational** | **Navigational** | Appropriate. No changes needed. |

**Overall intent coverage:**
- Informational intent: **0%** -- The site has zero content that answers "what is agentic engineering?", "what is company as a service?", or "how do AI agents help solo founders?"
- Commercial investigation intent: **~10%** -- The homepage makes a case but uses no comparison language and targets no searchable commercial queries.
- Transactional intent: **~40%** -- Getting Started serves this, though weakly.
- Navigational intent: **~90%** -- The site serves people who already know Soleur well.

---

## 3. Specific Issues Blocking Discoverability

### Priority 1 -- Critical (blocks all organic discovery)

| # | Issue | Affected Pages | Impact |
|---|---|---|---|
| C1 | **Zero instances of target keywords in body copy.** "Agentic company", "agentic engineering", "company as a service" (as prose, not just a badge), "AI company", "solo founder" -- none appear in any heading or paragraph across the entire site. | All | Search engines cannot rank the site for these terms. |
| C2 | **Product category is never named.** The site never says "Claude Code plugin" or even "Claude Code" in visible body text. A searcher looking for "best Claude Code plugins" will never find Soleur. | All | Invisible to product-category searches. |
| C3 | **No informational content.** There are no blog posts, no "what is" pages, no concept explainers. The entire content footprint is 5 pages of marketing + catalog + install instructions. | Site-wide | No top-of-funnel entry points exist. |

### Priority 2 -- High (significantly limits reach)

| # | Issue | Affected Pages | Impact |
|---|---|---|---|
| H1 | **H1 on homepage is poetic, not searchable.** "Build a Billion-Dollar Company. Alone." is a powerful brand statement but matches no search query. The H1 is the highest-weighted on-page SEO signal. | Homepage | Wasted H1 signal. |
| H2 | **H2 headings are generic.** "Every department. From idea to shipped." and "Ready to build at scale?" contain no keywords. | Homepage | Missed heading-level keyword opportunities. |
| H3 | **Agents and Skills pages have bare H1s.** Just "Agents" and "Skills" with no modifiers. Should be "AI Agents" or "AI Engineering Agents" at minimum. | Agents, Skills | Fails to differentiate from thousands of pages titled "Agents". |
| H4 | **Hero badge text is the only instance of "Company-as-a-Service".** Badge elements are often small, styled as labels, and carry less SEO weight than H1-H2 headings or paragraph-level prose. | Homepage | Core positioning term is underrepresented. |
| H5 | **llms.txt describes Soleur as "a Claude Code plugin."** This is accurate but contradicts the brand guide, which says "Do not call it a plugin or tool in public-facing content." More importantly, the llms.txt description is generic and uses no target keywords. | llms.txt | AI engines indexing this file will categorize Soleur as a generic plugin, not as a category-defining platform. |

### Priority 3 -- Medium (limits effectiveness)

| # | Issue | Affected Pages | Impact |
|---|---|---|---|
| M1 | **No anchor text uses target keywords.** Internal links use "Start Building", "Read the Docs", "Get Started" -- none use keyword-rich anchor text. | All | Missed internal linking signals. |
| M2 | **Feature cards lack keyword density.** Cards like "Strategy", "Product", "Engineering" use single-word H3s. Adding context like "AI-Powered Strategy" or "Agentic Engineering" would help. | Homepage | Feature section contributes no keyword signal. |
| M3 | **Getting Started page has no "What is Soleur?" section.** Jumps directly to `claude plugin install soleur` with no preamble. | Getting Started | Visitors from search have no context. Bounces likely. |

---

## 4. Rewrite Suggestions

Below are specific copy rewrites that incorporate target keywords while preserving brand voice. All rewrites follow the brand guide's principles: declarative, bold, no hedging, no "AI-powered" redundancy.

### 4.1 Homepage Hero Section

**Current:**
```
Badge: The Company-as-a-Service Platform
H1: Build a Billion-Dollar Company. Alone.
Sub: Everything you need to build, ship, and scale -- powered by AI teams. For founders who think in billions.
```

**Suggested:**
```
Badge: THE AGENTIC COMPANY PLATFORM
H1: The First Company-as-a-Service Platform for Solo Founders
Sub: 32 AI agents. Every department from strategy to shipping. One founder, zero employees, infinite scale. Soleur is the agentic engineering platform that turns a solo founder into a full AI company.
CTA: Start Building | See the Agents
```

**Rationale:** Moves "company-as-a-service", "solo founder", "agentic engineering", and "AI company" into the highest-weight elements on the page. The H1 is now both searchable and declarative. The sub packs concrete numbers (brand guide: "use concrete numbers") with three of the five target keywords.

### 4.2 Homepage Problem Section

**Current:**
```
Label: This Is the Way
H2: One founder powered by a full-stack AI organization.
Desc: Not a copilot. Not an assistant. A full AI organization that reviews, plans, builds, and remembers.
```

**Suggested:**
```
Label: AGENTIC ENGINEERING
H2: One solo founder. A full AI company.
Desc: Not a copilot. Not an assistant. A full agentic company that reviews, plans, builds, and remembers. Every decision you make teaches the system. Every project starts faster than the last. This is what company as a service looks like.
```

**Rationale:** Introduces "agentic engineering" as a section label (high visibility), "solo founder" and "AI company" in the H2, and "agentic company" and "company as a service" in the description -- all without losing the brand voice.

### 4.3 Homepage Features Section

**Current:**
```
Label: Your AI Organization
H2: Every department. From idea to shipped.
```

**Suggested:**
```
Label: YOUR AI COMPANY
H2: Every department an agentic company needs. From idea to shipped.
```

### 4.4 Homepage Quote Section

**Current:**
```
"The first billion-dollar company run by one person isn't science fiction. It's an engineering problem. We're solving it."
-- The Soleur Thesis
```

**Suggested -- keep as-is.** This is the thesis and should not be modified for keywords. It already contains "billion-dollar company" and "one person" which are semantically adjacent to "solo founder."

### 4.5 Homepage Final CTA

**Current:**
```
H2: Ready to build at scale?
Sub: Your AI organization is ready. Are you?
```

**Suggested:**
```
H2: Ready to run an agentic company?
Sub: Your AI organization is ready. 32 agents. 41 skills. Zero employees. Are you?
```

### 4.6 Agents Page Hero

**Current:**
```
H1: Agents
Sub: 32 specialized agents for code review, architecture, infrastructure, operations, product, design, and engineering workflows.
```

**Suggested:**
```
H1: AI Agents for Agentic Engineering
Sub: 32 specialized agents organized as a full AI company -- from code review and architecture to marketing, operations, and product. Every department a solo founder needs, staffed by agents.
```

### 4.7 Skills Page Hero

**Current:**
```
H1: Skills
Sub: 41 specialized skills for development, content, deployment, and more.
```

**Suggested:**
```
H1: Agentic Engineering Skills
Sub: 41 skills that power the company-as-a-service platform -- from brainstorming and planning to building, reviewing, and shipping. The full lifecycle of an AI company, automated.
```

### 4.8 Getting Started Page -- Add Context Section

**Current:** Jumps directly to install command.

**Suggested -- add before Installation:**
```
H2: What is Soleur?
Soleur is a company-as-a-service platform for solo founders. It provides 32 AI agents and 41 skills
that operate as every department of a company -- engineering, marketing, operations, product, and design.
Install it as a Claude Code plugin. Run it from your terminal. Build at the scale of a full team, alone.
```

**Rationale:** This single paragraph would be the most impactful addition on the entire site. It answers the "what is this?" question for search visitors, contains all five target keywords naturally, and establishes the product category for both human and AI search engines.

### 4.9 llms.txt Rewrite

**Current:**
```
> Build, ship, and scale powered by AI teams.

Soleur is a Claude Code plugin providing 32 AI agents, 41 skills, and 8 commands for software development workflows.
```

**Suggested:**
```
> The company-as-a-service platform for solo founders.

Soleur is an agentic engineering platform that enables a single founder to build, ship, and scale an AI company.
It provides 32 AI agents and 41 skills organized as a full company -- engineering, marketing, operations,
product, and design departments -- all orchestrated through Claude Code. Every decision teaches the system.
Every project starts faster than the last.
```

---

## 5. Prioritized Action Plan

| Priority | Action | Effort | Expected Impact |
|---|---|---|---|
| 1 | Add "What is Soleur?" paragraph to Getting Started page with all 5 target keywords | Low | High -- creates the single most keyword-rich paragraph on the site |
| 2 | Rewrite homepage H1 and hero subheadline to include "company-as-a-service" and "solo founder" | Low | High -- fixes the highest-weight on-page signal |
| 3 | Rewrite Agents and Skills page H1s to include "AI" and "agentic engineering" | Low | Medium -- differentiates from generic "Agents" pages |
| 4 | Rewrite homepage section labels and H2s to include target keywords | Low | Medium -- distributes keywords across heading hierarchy |
| 5 | Rewrite llms.txt to use target keywords and platform positioning | Low | Medium -- improves AI engine discoverability |
| 6 | Add a "What is Company-as-a-Service?" or "What is Agentic Engineering?" long-form page | Medium | High -- creates informational content for top-of-funnel queries that currently have zero coverage |
| 7 | Add keyword-rich anchor text to internal links (e.g., "See the AI agents" instead of "Read the Docs") | Low | Low-Medium -- improves internal linking signals |

---

## 6. Keyword Gap Matrix

This table shows which target keywords appear on which pages. Ideally, each keyword should appear on at least 2-3 pages.

| Keyword | Homepage | Agents | Skills | Getting Started | Changelog | Total |
|---|---|---|---|---|---|---|
| "agentic company" | 0 | 0 | 0 | 0 | 0 | **0** |
| "agentic engineering" | 0 | 0 | 0 | 0 | 0 | **0** |
| "company as a service" | 0 (badge only) | 0 | 0 | 0 | 0 | **0** |
| "AI company" | 0 | 0 | 0 | 0 | 0 | **0** |
| "solo founder" | 0 | 0 | 0 | 0 | 0 | **0** |
| "AI agents" | 1 (label) | 0 | 0 | 0 | 0 | **1** |
| "Claude Code" | 0 | 0 | 0 | 0 | 0 | **0** |
| "AI organization" | 2 | 0 | 0 | 0 | 0 | **2** |

Every single target keyword has either zero or near-zero presence across the entire site. This is the fundamental discoverability problem.

---

## Conclusion

The site's content is brand-consistent and well-written in the Soleur voice. The problem is not quality -- it is absence. The copy was written for people who already believe in the vision, not for people discovering it through search. The six rewrites in Section 4 and the single "What is Soleur?" paragraph in Section 4.8 would, combined, represent the highest-impact content changes possible with the lowest effort. They do not require new pages, new design, or new features -- only rewriting existing headlines and adding one paragraph.
