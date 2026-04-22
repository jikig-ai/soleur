---
last_updated: 2026-04-22
last_reviewed: 2026-04-22
owner: CMO
audit_type: content
scope: soleur.ai (homepage + 7 top-level pages sampled)
brand_guide: knowledge-base/marketing/brand-guide.md (read and applied)
---

# Soleur.ai Content Audit — 2026-04-22

Scope: 8 pages sampled via WebFetch — `/`, `/pricing/`, `/getting-started/`, `/vision/`, `/agents/`, `/skills/`, `/about/`, `/blog/`. Sub-pages (per-agent, per-skill, individual posts) not audited this pass; they should be sampled next audit. Findings focus on keyword alignment, search-intent match, and readability. AEO/JSON-LD checks are out of scope (owned by `seo-aeo-analyst`).

Brand guide loaded. Rewrite suggestions follow the **Ambitious-inspiring** voice, general register (website is a non-technical channel per brand guide), with pain-point primary framing ("Stop hiring. Start delegating.") and memory-first variant retained as present on site.

## Summary

| Page | Detected target keywords | Intent match | Readability | Critical issues | Improvement issues |
|------|--------------------------|--------------|-------------|-----------------|--------------------|
| `/` Homepage | "AI agents for solo founders", "company-as-a-service", "delegate to AI" | Informational + Commercial — good | High — short declarative sentences, correct register | 0 | 2 |
| `/pricing/` | "AI agents pricing", "solo founder AI tools cost" | Transactional — good | High | 0 | 2 |
| `/getting-started/` | "how to use Soleur", "AI agent workflow" | Informational — partial (meta desc missing) | Medium — headline drift from page purpose | 1 | 2 |
| `/vision/` | "company-as-a-service", "billion-dollar solo founder" | Informational — good | Medium — register too technical for a public vision page | 0 | 3 |
| `/agents/` | "AI agents list", "AI agents for business departments" | Informational/Navigational — good | Medium — thin intro, heavy reliance on a list | 1 | 2 |
| `/skills/` | "agentic engineering skills", "AI workflow skills" | Informational — partial | Medium — "Uncategorized" bucket leaks into UX | 1 | 2 |
| `/about/` | "Jean Deruelle founder", "Soleur founder" | Navigational — good | High | 0 | 1 |
| `/blog/` | "agentic engineering blog", "company-as-a-service blog" | Informational/Navigational — good | Medium — meta description long but usable | 0 | 1 |

Totals: 3 critical, 15 improvement.

## Per-Page Analysis

### 1. Homepage — `/`

- **Title:** "Soleur — AI Agents for Solo Founders | Every Department, One Platform"
- **H1:** "Stop hiring. Start delegating."
- **Detected target keywords:** "AI agents for solo founders", "company-as-a-service platform", "delegate"
- **Keyword alignment:** Strong. The title carries the primary commercial-intent keyword ("AI Agents for Solo Founders"); the H1 delivers the brand-approved pain-point framing. Body copy reinforces the keyword set with "65 AI agents across 8 business departments" and repeats "company-as-a-service" naturally.
- **Search-intent match:** Mixed informational + commercial. Visitors arriving from "AI agents for solo founders" get an immediate value statement and department list — good. Waitlist CTA is prominent, matching commercial intent.
- **Readability:** High. Declarative sentences, 10-18 words each, no jargon. Voice matches brand guide general register.
- **Issues:**
  - Improvement: The H1 ("Stop hiring. Start delegating.") is the pain-point framing but does not contain any search keyword. Search crawlers and LLM summarizers weight H1 heavily. The sub-hero H2 does the keyword work ("Company-as-a-Service platform for solo founders"), so this is not critical, but a secondary keyword line near the H1 would strengthen alignment.
  - Improvement: Meta description was not detected in the fetched payload. If absent at the markup level, generative engines and SERP previews fall back to the first visible paragraph — which is "Stop hiring. Start delegating." alone, not ideal.

### 2. Pricing — `/pricing/`

- **Title:** "Pricing — AI Agents for Solo Founders | Soleur"
- **H1:** "Every department. One price."
- **Detected target keywords:** "AI agents pricing", "solo founder AI tool cost", "AI organization price"
- **Keyword alignment:** Good. Title picks up the commercial-intent keyword. Hero sub ("A full AI organization... for less than a single contractor") carries the pricing value proposition.
- **Search-intent match:** Transactional. Four tiers, clear price points, CTA is waitlist — aligned to current pre-launch stage. The "$95,000/mo typical team cost" comparison anchors value.
- **Readability:** High. Short tier names, crisp descriptors.
- **Issues:**
  - Improvement: No tier targets the "free / open source" query variant in the heading hierarchy. Users searching "free AI agents for solo founders" hit the paid-tier cards first; the OSS mention is only a footnote CTA. A "Free (Open Source)" row or sidebar card would catch that intent.
  - Improvement: The tier descriptors ("For founders building alone", "For founding teams moving fast") are brand-voice-aligned but under-keyworded. "Solo" could read "For solo founders ($ tier)" — see rewrites.

### 3. Getting Started — `/getting-started/`

- **Title:** "Getting Started with Soleur - Soleur"
- **H1:** "The AI that already knows your business."
- **Detected target keywords:** "how to get started with Soleur", "Soleur quickstart", "AI agent workflow"
- **Keyword alignment:** Weak. The H1 is the memory-first brand variant — it is beautiful copy, but the page is literally the quickstart, and users arriving from navigational intent ("Soleur getting started", "Soleur setup") land on a headline that does not match their query or the page URL. The body does contain the 5-step workflow and commands.
- **Search-intent match:** Mismatch. The URL and user intent is procedural (informational/navigational: "how do I use this"), but the H1 is positioning. This is the site's clearest intent-match bug.
- **Readability:** Medium. Once past the hero, the 5-step list is excellent.
- **Issues:**
  - **Critical:** H1 does not match page intent. A user from Google or ChatGPT searching "Soleur getting started" scans the page for "Get Started" or "Quickstart" and finds a memory-first positioning statement. This is the first intent-match failure of the site. Move the positioning line to a sub-hero or eyebrow and promote a procedural H1.
  - Improvement: Title tag is duplicative ("Getting Started with Soleur - Soleur"). Rewrite for keyword placement.
  - Improvement: Meta description not detected.

### 4. Vision — `/vision/`

- **Title:** "Soleur Vision: Company-as-a-Service - Soleur"
- **H1:** "The Soleur Vision: Company-as-a-Service for the Solo Founder"
- **Detected target keywords:** "company-as-a-service", "billion-dollar solo founder", "model-agnostic orchestration"
- **Keyword alignment:** Strong for the primary keyword "company-as-a-service". "Model-agnostic orchestration engine" is a distinctive phrase with SEO/AEO upside if supported by in-page definition.
- **Search-intent match:** Informational, long-form strategy — fits. But this page is reachable from the main nav, which means non-technical founders and journalists will hit it; the register trends technical ("model-agnostic orchestration engine", "three-milestone roadmap: software → hardware → multiplanetary").
- **Readability:** Medium. Big concepts, but the phrase "multiplanetary operations" without framing risks losing the pragmatist segment ($10K-50K MRR) the brand guide identifies as the target.
- **Issues:**
  - Improvement: Add a plain-language TL;DR block at the top (2-3 sentences, general register per brand guide). "Explain, don't dumb down."
  - Improvement: Define "Company-as-a-Service" in one quotable sentence near first use — this is a brand-coined term and currently lacks a crisp dictionary-style definition.
  - Improvement: The Anthropic CEO citation is strong third-party credibility — promote it closer to the top, not buried in primary claims.

### 5. Agents — `/agents/`

- **Title:** "Soleur AI Agents - Soleur"
- **H1:** "Soleur AI Agents"
- **Detected target keywords:** "AI agents list", "AI agents by department", "business AI agents"
- **Keyword alignment:** Adequate but thin. Title and H1 are near-duplicates and under-keyworded; no mention of "solo founder" or "company-as-a-service" in the hero.
- **Search-intent match:** Informational/navigational (browsing the catalog). Users want to scan the 65 agents. The department grouping works.
- **Readability:** Medium. Intro paragraph is short; the bulk is a list.
- **Issues:**
  - **Critical:** Title and H1 are functionally identical and miss a high-intent modifier. A user searching "AI agents for solo founders list" or "AI marketing agents" will not find this page ranked well. Title should carry 1-2 extra modifiers.
  - Improvement: Intro paragraph lacks a "what is an AI agent" quotable definition. LLMs cite these in response to "what is an AI agent" queries — free AEO surface area.
  - Improvement: Example agent descriptions are strong ("Thinks like an attacker, constantly asking: Where are the vulnerabilities?") but only a handful are surfaced. Surfacing 1 "flagship" example per department in the intro would increase keyword diversity.

### 6. Skills — `/skills/`

- **Title:** "Soleur Skills - Soleur"
- **H1:** "Agentic Engineering Skills"
- **Detected target keywords:** "agentic engineering", "AI workflow skills", "Claude Code skills"
- **Keyword alignment:** Mixed. "Agentic engineering" is a rising keyword and the H1 captures it — good. But the title is thin and duplicative.
- **Search-intent match:** Informational. The page explains skills orchestrate agents and lists categories. Reasonable.
- **Readability:** Medium. "Uncategorized" (5 skills) is a content-debt tell — exposes internal taxonomy to users.
- **Issues:**
  - **Critical:** The "Uncategorized" section must be eliminated. It signals unfinished work and erodes trust; it also dilutes keyword density for the real categories. Either categorize the 5 skills or fold them into an "Other" section with descriptive copy.
  - Improvement: Title tag under-keyworded — "Soleur Skills - Soleur" — should read as a keyword-rich descriptor.
  - Improvement: Intro references "Claude Code and Model Context Protocol (MCP)" without inline definition. For the general-register audience, this is jargon. Add a one-line definition or link.

### 7. About — `/about/`

- **Title:** "About Jean Deruelle - Soleur"
- **H1:** "About"
- **Detected target keywords:** "Jean Deruelle", "Soleur founder", "Soleur company"
- **Keyword alignment:** Good for the founder name. H1 ("About") is generic — acceptable because the title carries the keyword.
- **Search-intent match:** Navigational (people searching the founder or company). The bio is crisp, the "built using Soleur itself" line is a strong E-E-A-T signal.
- **Readability:** High. Two short sections, one FAQ block.
- **Issues:**
  - Improvement: The H1 "About" is generic. Promoting "Jean Deruelle, Founder of Soleur" as H1 would carry the search keyword into the most-weighted heading slot.

### 8. Blog — `/blog/`

- **Title/Meta:** "Blog — Soleur | Insights on agentic engineering, company-as-a-service, and building at scale with AI teams."
- **H1:** "Blog"
- **Detected target keywords:** "agentic engineering blog", "company-as-a-service blog", "AI for solo founders"
- **Keyword alignment:** Meta description is the strongest on the site — carries three primary keywords. Title tag is thinner.
- **Search-intent match:** Informational/navigational. Good category split (CaaS intro, competitor comparisons, case studies, engineering deep dives).
- **Readability:** Medium. Competitor comparison posts (Soleur vs. Devin, Cursor, etc.) signal commercial/comparative intent well.
- **Issues:**
  - Improvement: H1 "Blog" is generic. A descriptor like "Soleur Blog — Agentic engineering and company-as-a-service" mirrors the meta description and picks up keyword weight.

## Rewrite Suggestions

Each suggestion is brand-voice compliant (general register, declarative, no hedging, no "AI-powered" / "just" / "simply"). Priority: **C** = critical, **I** = improvement.

### R1. Homepage meta description (I)

- **Current:** (not detected in payload — likely missing or empty)
- **Suggested:**
  > Soleur is the Company-as-a-Service platform for solo founders. 65 AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support — share one compounding knowledge base. Stop hiring. Start delegating.
- **Rationale:** Carries three primary keywords ("Company-as-a-Service", "AI agents", "solo founders"), 8-department enumeration for LLM extractability, and closes with the brand-approved pain-point tagline. 280 chars — fits SERP preview.

### R2. Homepage secondary keyword line (I)

- **Current:** H1 "Stop hiring. Start delegating." (no keyword support near top)
- **Suggested addition (eyebrow above H1 or sub-hero line):**
  > AI agents for solo founders. Every department. One compounding knowledge base.
- **Rationale:** Keeps the H1 brand-perfect, adds a keyword-dense line that LLMs and SERP snippet extractors can quote. No hedging.

### R3. Getting Started H1 (C)

- **Current:** "The AI that already knows your business."
- **Suggested:**
  > Get Started with Soleur
  >
  > (sub-hero retained:) The AI that already knows your business. Install the open-source version in one command. Reserve access to the hosted platform.
- **Rationale:** Matches the page URL and user intent. Procedural pages should carry procedural headlines. The memory-first brand variant moves to the sub-hero, where it still lands first in the fold but no longer blocks intent match. Voice remains declarative, no "just" or "simply".

### R4. Getting Started title tag (I)

- **Current:** "Getting Started with Soleur - Soleur"
- **Suggested:**
  > Get Started with Soleur — Install AI Agents for Your Solo Company
- **Rationale:** Removes redundancy, adds commercial-intent modifier, keeps Soleur brand prefix via the `—` separator only once.

### R5. Agents page title + H1 (C)

- **Current title:** "Soleur AI Agents - Soleur"
- **Current H1:** "Soleur AI Agents"
- **Suggested title:**
  > 65 AI Agents for Solo Founders — Every Department | Soleur
- **Suggested H1:**
  > Your AI Organization: 65 Specialists Across 8 Departments
- **Rationale:** Title carries concrete number (per brand guide: "Use concrete numbers when available") and the primary keyword modifier. H1 uses the brand-approved phrase "Your AI Organization" (from brand guide Example Phrases) and surfaces the 65/8 proof points. Soft-floor language ("60+") is reserved for prose; headlines with live counts are acceptable because the site renders them via `{{ stats.agents }}`.

### R6. Agents intro — add quotable definition (I)

- **Suggested addition after H1:**
  > An AI agent is a specialist that handles a specific business function — code review, brand strategy, legal compliance, financial planning. Soleur agents share one knowledge base, so decisions in marketing flow through to legal and operations without re-briefing. Your expertise sets direction. The agents execute.
- **Rationale:** Definition-first sentence is quotable by LLMs. Closes with brand-guide-approved "Your expertise, amplified" variant. No "copilot" or "assistant" per brand voice.

### R7. Skills — eliminate "Uncategorized" (C)

- **Current:** "Uncategorized" section with 5 skills
- **Suggested:** Either rename to a meaningful category ("Knowledge & Meta") or merge the 5 skills into the most-fitting existing categories. Update the listing page to reflect.
- **Rationale:** "Uncategorized" signals unfinished work and violates brand voice ("trust the reader's intelligence" implies the team has done the work). Direct content fix — not just a copy rewrite.

### R8. Skills title tag (I)

- **Current:** "Soleur Skills - Soleur"
- **Suggested:**
  > Agentic Engineering Skills — 67 AI Workflows for Solo Founders | Soleur
- **Rationale:** Three keyword clusters ("agentic engineering", "AI workflows", "solo founders"), concrete number, brand suffix.

### R9. Vision — plain-language TL;DR (I)

- **Suggested addition directly below H1:**
  > **In one paragraph:** Soleur is building a platform where one founder, using AI agents, can run a company the size of a 100-person team. Engineering, marketing, legal, finance, operations, product, sales, and support — every department, one platform, one knowledge base that gets smarter every week. The goal: the first billion-dollar company run by one person.
- **Rationale:** Opens the page in general register for the non-technical audience the brand guide identifies. Declarative, concrete, no hedging.

### R10. Vision — definition of Company-as-a-Service (I)

- **Suggested addition near first use of the term:**
  > **Company-as-a-Service (CaaS):** A software platform that delivers the operational capacity of a full company — every department, every workflow — to a single founder. Agents execute. The founder decides.
- **Rationale:** Quotable definition. LLMs cite these when users ask "what is Company-as-a-Service". Matches brand guide's "Explain, don't dumb down" approach.

### R11. Pricing — free-tier surfacing (I)

- **Current:** Open-source mention is a secondary footer CTA.
- **Suggested:** Add a fifth card or sidebar: "Free (Open Source) — Self-hosted. All 65 agents. Apache 2.0. Install in one command."
- **Rationale:** Captures "free AI agents for solo founders" intent without undermining paid tiers. Apache 2.0 is a credibility signal, not a discount.

### R12. Pricing — tier descriptors with keywords (I)

- **Current (Solo tier):** "For founders building alone."
- **Suggested:** "For solo founders building alone. 65 AI agents. 8 departments. One price."
- **Rationale:** Adds the keyword "solo founders" to the tier descriptor and carries the department proof point.

### R13. About H1 (I)

- **Current:** "About"
- **Suggested:** "Jean Deruelle, Founder of Soleur"
- **Rationale:** Picks up founder-name and company-name keywords in the highest-weight heading. Retains the concise tone.

### R14. Blog H1 + page title (I)

- **Current H1:** "Blog"
- **Current title:** "Blog — Soleur | Insights on agentic engineering, company-as-a-service, and building at scale with AI teams."
- **Suggested H1:** "Soleur Blog — Agentic engineering and Company-as-a-Service"
- **Rationale:** Mirrors meta description. H1 is the strongest on-page signal; the current "Blog" wastes it.

### R15. Global — audit all title tags for "Page - Soleur" duplication (I)

Four of eight pages follow the `<Name> - Soleur` pattern; the homepage and pricing follow the richer `<Name> — <value prop> | Soleur` pattern. Standardize on the richer pattern site-wide. Replace `-` with `—` (em dash) for consistency with the homepage.

## Brand Voice Compliance Check

All 15 rewrites reviewed against brand guide Voice section:

- No "AI-powered", "leverage", "just", "simply", "assistant", "copilot", "disrupt", or "synergy" used.
- Declarative statements only — no "might", "could", "potentially".
- Concrete numbers (65, 8, 67) used per brand guide Do's.
- General register selected for public pages; technical jargon defined inline where retained.
- Pain-point framing ("Stop hiring. Start delegating.") preserved in hero; memory-first variant retained as secondary.
- "Company-as-a-Service" and "Your AI organization" used as canonical phrases.

## Recommended Priority Order

1. **R7** (Skills: remove "Uncategorized") — visible quality tell, ~30 min fix.
2. **R3** (Getting Started H1) — only intent-match failure on the site.
3. **R5** (Agents title + H1) — highest-traffic potential per search volume.
4. **R1** (Homepage meta description) — if missing, this is free SERP/LLM surface area.
5. **R15** (title-tag standardization) — batch rewrite, consistent keyword capture.
6. R2, R4, R6, R8, R9, R10, R11, R12, R13, R14 — batch as a second wave.

## Out of Scope / Next Audit

- Per-agent and per-skill detail pages (65 + 67 = 132 pages) — sample in next pass.
- Individual blog posts — refresh status tracked in `knowledge-base/marketing/seo-refresh-queue.md`.
- AEO/JSON-LD/llms.txt — covered by `seo-aeo-analyst` agent; see `2026-04-21-aeo-audit.md`.
- Competitor content gap — covered by `2026-04-21-content-plan.md`.
