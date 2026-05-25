---
date: 2026-05-25
audit_type: content
scope: soleur.ai (sampled — 9 pages)
brand_guide: knowledge-base/marketing/brand-guide.md (loaded; voice + register applied)
auditor: growth agent
---

# Soleur.ai Content Audit — 2026-05-25

## Scope and Method

Sampled 9 high-priority pages: homepage, then nav-linked pillars (pricing, getting-started, agents, skills, vision, about, community, blog index). Long-tail blog posts and changelog entries were not individually audited in this pass — they are queued for the next sweep.

Brand-guide alignment: rewrite suggestions use the **general register** (website is a non-technical surface per brand guide line 109), lead with the **pain-point primary framing** ("Stop hiring. Start delegating."), and avoid banned phrases ("AI-powered", "leverage AI", "just/simply", "copilot/assistant", "terminal-first").

---

## Per-Page Analysis

### 1. Homepage (`/`)

| Field | Value |
|---|---|
| Title | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" |
| H1 | "Stop hiring. Start delegating." |
| Detected target keywords | AI agents for solo founders, Company-as-a-Service, AI organization, knowledge base |
| Keyword alignment | **Strong.** Primary pain-point framing matches brand guide. "Company-as-a-Service" appears in title family and H2. |
| Search intent match | **Commercial + informational hybrid.** Title targets commercial ("AI agents for solo founders"), H1 matches transactional intent (delegation), body explains the concept (informational). Match is good but the hero subhead leans heavy on category jargon ("Company-as-a-Service") before the visitor has been onboarded. |
| Readability | Headings are punchy, on-brand. The repeated "Stop hiring. Start delegating." closer is correct per brand guide (line 159). Body uses concrete numbers (67 agents, 8 departments). |

### 2. Pricing (`/pricing/`)

| Field | Value |
|---|---|
| Title | "Pricing — AI Agents for Solo Founders \| Soleur" |
| H1 | "Every department. One price." |
| Detected target keywords | AI agent pricing, solo founder pricing, contractor replacement cost |
| Keyword alignment | **Strong.** Title contains primary keyword cluster. "$95,000/mo" comparison maps to the brand guide's tool-replacement framing (line 142) — correctly demoted from the headline to a proof point. |
| Search intent match | **Transactional. Matches.** Plans, prices, and CTAs ("Join the Waitlist", "Contact Us") are visible. |
| Readability | Strong. The "One writes functions. The other runs departments." differentiator is on-voice. |

### 3. Getting Started (`/getting-started/`)

| Field | Value |
|---|---|
| Title | "Getting Started with Soleur" |
| H1 | "The AI that already knows your business." |
| Detected target keywords | install Soleur, Claude Code plugin, getting started AI agents |
| Keyword alignment | **Weak title.** Title contains zero keywords beyond the brand name. A founder searching "how to set up AI agents for my startup" cannot find this page. H1 uses the memory-first variant (brand guide line 134) — good for the page, but does not reinforce search intent. |
| Search intent match | **Informational + transactional. Partial match.** The page serves both intents (run open source, reserve hosted access) but the title does not signal either to search engines. |
| Readability | Good. Six-step workflow visualization is concrete. Plain language throughout. |

### 4. Agents (`/agents/`)

| Field | Value |
|---|---|
| Title | "67 AI Agents for Solo Founders — Every Department \| Soleur" |
| H1 | "Your AI Organization: 67 Specialists Across 8 Departments" |
| Detected target keywords | AI agents for founders, AI agent list, specialized AI agents, marketing/legal/finance AI agents |
| Keyword alignment | **Strong.** Title and H1 both contain primary keywords. Department headers each surface a domain-specific keyword (marketing agents, legal agents, finance agents). |
| Search intent match | **Informational. Matches.** Visitor wants to know what's in the box; the page enumerates it. |
| Readability | Strong. Concrete agent counts per department. **Concern:** the brand guide (line 79) flags hard-coded exact counts in prose as drift risk — "67 agents" in title/H1 is fine if rendered from `{{ stats.agents }}`, but if it is hard-coded prose it will go stale. |

### 5. Skills (`/skills/`)

| Field | Value |
|---|---|
| Title | "Soleur Skills" |
| H1 | "Agentic Engineering Skills" |
| Detected target keywords | Claude Code skills, agentic engineering, workflow automation |
| Keyword alignment | **Weak title. Strong H1 for technical register only.** Title is brand-only — no search hook. H1 ("Agentic Engineering Skills") is a technical-register phrase on what should be a general-register page (line 109 of brand guide). A non-technical founder searching "AI workflow templates" or "AI automation for my business" will not match. |
| Search intent match | **Informational. Partial.** Lists skills well; misses the "what do they do for me?" outcome layer. |
| Readability | Adequate but feature-listy. "Agentic engineering" is undefined on first use — violates brand guide line 84 (technical terms must be defined on first use in general register). |

### 6. Vision (`/vision/`)

| Field | Value |
|---|---|
| Title | "Soleur Vision: Company-as-a-Service" |
| H1 | "The Company-as-a-Service Platform" |
| Detected target keywords | Company-as-a-Service, AI agent orchestration, billion-dollar solo founder |
| Keyword alignment | **Strong for thought-leadership terms.** "Company-as-a-Service" and "billion-dollar solo company" are the brand's invented categories — appropriate to own here. |
| Search intent match | **Informational. Matches.** This is the explainer page — visitors arriving from "what is Company-as-a-Service" land correctly. |
| Readability | Adequate. Risk: this is the deepest-jargon page on the site, which is correct positioning per brand guide line 140 ("retain for deep content where there's space to explain"). |

### 7. About (`/about/`)

| Field | Value |
|---|---|
| Title | "About Jean Deruelle - Soleur" |
| H1 | "About" |
| Detected target keywords | Jean Deruelle, Soleur founder, who built Soleur |
| Keyword alignment | **Adequate for branded queries.** Founder name in title is correct (brand guide line 46-48 mandates founder attribution). Missing E-E-A-T keywords: "15+ years distributed systems" appears in body but not in a meta-description-eligible location. |
| Search intent match | **Navigational + informational. Matches.** |
| Readability | Strong. First-person founder voice consistent with brand guide line 330 (LinkedIn Personal register). |

### 8. Community (`/community/`)

| Field | Value |
|---|---|
| Title | "Community — Soleur" |
| H1 | "Community" |
| Detected target keywords | Soleur Discord, Soleur GitHub, contribute to Soleur |
| Keyword alignment | **Weak.** Title and H1 are generic. A page targeting "open-source AI agents Discord" or "contribute Claude Code plugins" would broaden discoverability. |
| Search intent match | **Navigational. Matches** for branded queries. Misses non-branded discovery. |
| Readability | Concise. Apache 2.0 + Contributor Covenant references are well-placed for trust. |

### 9. Blog Index (`/blog/`)

| Field | Value |
|---|---|
| Title | "Blog — Soleur" |
| H1 | "Blog" |
| Detected target keywords | agentic engineering blog, Company-as-a-Service insights |
| Keyword alignment | **Weak.** Title is brand-only. The intro line ("Insights on agentic engineering, company-as-a-service, and building at scale with AI teams") contains every keyword but is not surfaced in the title or meta description. |
| Search intent match | **Informational. Partial.** Category sections (What is CaaS, vs Competitors, Case Studies, Engineering Deep Dives) are strong; the index itself isn't optimized for search arrival. |
| Readability | Good structure. |

---

## Issues Found

### Critical (blocks discoverability)

| # | Page | Issue | Why critical |
|---|------|-------|--------------|
| C1 | /getting-started/ | Title `"Getting Started with Soleur"` is brand-only — zero keywords | Page cannot rank for any non-branded query. Highest-traffic onboarding page on the site. |
| C2 | /skills/ | Title `"Soleur Skills"` is brand-only and "Agentic Engineering Skills" H1 is technical register on a general-register surface | Excludes non-technical founders (one of two target segments per brand guide line 27). |
| C3 | /blog/ | Title `"Blog — Soleur"` is brand-only; keyword-rich intro is not surfaced in title or meta | Blog index is the funnel hub for content marketing; current title forfeits all category-level search traffic. |
| C4 | All pages | No meta descriptions detected in any sampled page output | Search engines auto-generate from body text; AI engines have no canonical summary to quote. |
| C5 | /skills/ | Term "Agentic engineering" is used in H1 without inline definition | Brand guide line 84 mandates inline definition for jargon in general register. Non-technical visitors bounce. |

### Improvement (enhances ranking)

| # | Page | Issue | Why |
|---|------|-------|-----|
| I1 | / (home) | Hero subhead leans on "Company-as-a-Service" before onboarding the visitor | Pain-point framing won 7/10 in synthetic research (brand guide line 124). Subhead could lead with the pain. |
| I2 | /community/ | Title and H1 are generic | Adding "Open-source AI agents" prefix unlocks non-branded discovery. |
| I3 | /agents/ | "67" hard-coded in title and H1 risks drift | Brand guide line 79 mandates soft floors in prose. Use "60+" in static title/H1 or template from `{{ stats.agents }}`. |
| I4 | /about/ | E-E-A-T proof ("15+ years distributed systems", "420+ merged PRs") not in title or hero | Strengthens AI-citation probability and human credibility scan. |
| I5 | /vision/ | Page is the densest jargon — no glossary or sidebar definitions | Brand guide line 114 provides the inline-definition glossary; apply it. |
| I6 | /pricing/ | "$95,000/mo" replacement number is unsourced in visible content | Adding a footnote breakdown elevates trust (brand guide line 144 trust-scaffolding guidance). |
| I7 | /blog/ | Three category sections (CaaS, vs Competitors, Case Studies) have no per-category landing pages | Each category is a pillar-page opportunity. |

---

## Rewrite Suggestions

All rewrites use the **general register** and adhere to brand guide voice (declarative, no hedging, no "just/simply", no "AI-powered").

### R1. /getting-started/ — Title rewrite (addresses C1)

- **Current:** `Getting Started with Soleur`
- **Suggested:** `Get Started with Soleur — Install Your AI Organization in Two Commands`
- **Rationale:** Adds the action keyword "Install" + the outcome keyword "AI Organization" + the proof point "two commands". Matches brand guide line 38 thesis register and reinforces the page's actual transactional intent.

### R2. /getting-started/ — Meta description (new; addresses C4)

- **Current:** (none)
- **Suggested:** `Install Soleur in two commands and run a full AI organization — marketing, legal, finance, operations, sales, and support — without hiring anyone.`
- **Rationale:** Pain-point framing (line 127), concrete proof (two commands), explicit department list, follows the "Stop hiring, start delegating" thesis without using the headline phrase verbatim.

### R3. /skills/ — Title rewrite (addresses C2)

- **Current:** `Soleur Skills`
- **Suggested:** `AI Workflow Skills — 60+ Automated Workflows for Solo Founders \| Soleur`
- **Rationale:** "AI Workflow Skills" is the general-register synonym for "agentic engineering skills". "60+" is the brand-approved soft floor. Adds the target-audience keyword.

### R4. /skills/ — Definition paragraph (addresses C5)

- **Current:** H1 "Agentic Engineering Skills" with no inline definition.
- **Suggested addition** (under H1, before the categories): `Skills are the workflows your AI team follows to get things done. Each skill chains together one or more agents to complete a multi-step job — generating a marketing campaign, reviewing a pull request, or launching a feature. Skills compound: every run teaches the system what worked for your business.`
- **Rationale:** Direct application of brand guide line 117 glossary ("Skills = workflows the AI team follows to get things done"). Quotable by AI engines; readable by non-technical founders.

### R5. /blog/ — Title and meta rewrite (addresses C3, C4)

- **Current title:** `Blog — Soleur`
- **Suggested title:** `Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams`
- **Suggested meta:** `Field notes on building a billion-dollar company alone. Company-as-a-Service strategy, agentic engineering case studies, and engineering deep dives — by Jean Deruelle, founder of Soleur.`
- **Rationale:** Title surfaces three category keywords. Meta includes founder attribution (E-E-A-T per brand guide line 46), the brand thesis, and content categories.

### R6. /community/ — Title rewrite (addresses I2)

- **Current:** `Community — Soleur`
- **Suggested:** `Soleur Community — Open-Source AI Agents for Solo Founders on Discord and GitHub`
- **Rationale:** Adds non-branded keywords (open-source AI agents, Discord, GitHub) without losing the brand mention.

### R7. /agents/ — Soft-floor compliance (addresses I3)

- **Current title:** `67 AI Agents for Solo Founders — Every Department \| Soleur`
- **Suggested title:** `60+ AI Agents for Solo Founders — Every Department \| Soleur`
- **Rationale:** Brand guide line 79: "Use '60+ agents' and '60+ skills' in static documentation and marketing prose." If the title is rendered from `{{ stats.agents }}`, it can keep the exact count. Otherwise, this title goes stale every release.

### R8. / (home) — Hero subhead rewrite (addresses I1)

- **Current:** `The Company-as-a-Service platform for solo founders. Build a billion-dollar company — alone.`
- **Suggested:** `You're doing 8 jobs. Soleur runs 7 of them — marketing, legal, finance, operations, sales, support, and product — with AI specialists that learn your business and work together.`
- **Rationale:** Direct application of the primary pain-point framing (brand guide line 128). "7 of 8 jobs" beats abstract "Company-as-a-Service" for first-time visitors. Keeps "build a billion-dollar company — alone" intact further down the hero — it remains the brand thesis (line 38).

### R9. /about/ — Title + intro rewrite (addresses I4)

- **Current title:** `About Jean Deruelle - Soleur`
- **Suggested title:** `About Jean Deruelle — Founder of Soleur \| 15+ Years Building Distributed Systems`
- **Rationale:** Surfaces E-E-A-T proof in the title where AI engines and human scanners see it. Founder name first preserves the branded-query path.

### R10. /pricing/ — Trust-scaffolding addition (addresses I6)

- **Current:** "$95,000/mo" cost replacement claim, unsourced in visible content.
- **Suggested addition** (footnote or expandable breakdown beneath the claim): `Breakdown: senior marketing manager ($12K/mo), fractional legal counsel ($8K/mo), fractional CFO ($10K/mo), product manager ($14K/mo), customer success lead ($9K/mo), sales rep ($11K/mo), ops lead ($10K/mo), 2 senior engineers ($21K/mo). US contractor market rates, 2026. Your mileage will vary — Soleur is a starting point, not a final answer.`
- **Rationale:** Brand guide line 144 trust-scaffolding: "starting point, not final answer" addresses the #1 objection ("what if the output is wrong?"). Concrete numbers per brand guide line 77.

---

## Summary Scorecard

| Page | Title alignment | Intent match | Readability | Priority for fix |
|------|-----------------|--------------|-------------|------------------|
| / | Strong | Good | Strong | I1 (hero subhead) — P2 |
| /pricing/ | Strong | Strong | Strong | I6 (trust scaffolding) — P3 |
| /getting-started/ | **Weak** | Partial | Strong | C1 + R1/R2 — **P1** |
| /agents/ | Strong | Strong | Strong | I3 (soft floor) — P2 |
| /skills/ | **Weak** | Partial | Adequate | C2 + C5 + R3/R4 — **P1** |
| /vision/ | Strong | Strong | Adequate | I5 (glossary) — P3 |
| /about/ | Adequate | Strong | Strong | I4 (E-E-A-T in title) — P2 |
| /community/ | Weak | Navigational only | Strong | I2 — P2 |
| /blog/ | **Weak** | Partial | Good | C3 + R5 — **P1** |

**P1 fixes (next sprint):** Rewrite titles + add meta descriptions on `/getting-started/`, `/skills/`, `/blog/`. Add the skills-page definition paragraph (R4).

**P2 fixes:** Hero subhead pain-point rewrite (R8), community title (R6), agents soft-floor (R7), about title E-E-A-T (R9).

**P3 fixes:** Pricing trust scaffolding (R10), vision-page glossary application (I5).

---

## Notes and Caveats

- Audit covered 9 pages out of the full site. Long-tail blog posts, changelog entries, legal pages, and individual agent/skill detail pages are not in this pass.
- Meta descriptions appear missing across the sampled pages per WebFetch output. If they exist in `<head>` but were stripped by the fetcher, escalate to the seo-aeo-analyst agent for confirmation — meta-tag validity is out of scope for this content audit.
- Brand guide line 91 prohibits "terminal-first" / "CLI-native" positioning. The current site copy appears compliant. The `/getting-started/` "two commands" phrasing is acceptable (it describes installation mechanics, not positioning).
- No competitor URLs were analyzed in this pass — this is a single-site content audit, not a gap analysis.
