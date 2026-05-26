---
audit_date: 2026-05-18
audit_type: content
scope: soleur.ai (homepage, /pricing/, /about/, /vision/, /getting-started/)
brand_guide: knowledge-base/marketing/brand-guide.md (read and applied)
owner: CMO
data_source_note: |
  Live site at https://soleur.ai/ returned Cloudflare error 526 ("Invalid SSL
  Certificate" between Cloudflare and the origin) on every WebFetch attempt
  during this audit window. The audit was performed against the deploy
  source-of-truth in plugins/soleur/docs/pages/*.njk (and index.njk) which is
  what the production build publishes. Any per-page assessment that depends
  on render-time data (e.g., the resolved values of {{ stats.agents }},
  {{ stats.skills }}, {{ stats.departments }}, OG image rendering) was
  evaluated symbolically against brand-guide rules; rerun against the live
  domain once the 526 is resolved to confirm visual rendering matches.
---

# Soleur.ai Content Audit — 2026-05-18

**Scope:** Homepage (`/`), `/pricing/`, `/about/`, `/vision/`, `/getting-started/`. Sample audit; remaining pages (Agents, Skills, Blog, Changelog, Company-as-a-Service pillar, Community, Articles, Legal index) are not covered here.

**Brand guide status:** Present at `knowledge-base/marketing/brand-guide.md`. The Identity, Voice, Tone Spectrum, Do's/Don'ts, Audience Voice Profiles (general register applies to website), and Value Proposition Framings (primary pain-point + memory-first A/B variant) were applied to evaluate alignment.

**Live site availability:** `https://soleur.ai/` was unreachable (Cloudflare 526) during this audit. See `data_source_note` in frontmatter. Findings reflect the deploy source which renders to the production site; they will be valid for the next deploy. Flag the 526 to the seo-aeo-analyst / infra owner separately.

---

## Executive Summary

The soleur.ai surface is **on brand and well-voiced** — declarative copy, no hedging, brand glossary terms used correctly, FAQ blocks structured for AEO citation on every audited page. Voice quality is the strongest dimension across the site.

The two structural problems are **the same as the 2026-05-04 audit found, partially remediated, partially recurrent**:

1. **The "stats in prose" drift hazard remains.** The homepage opener still hard-codes `{{ stats.agents }}` and `{{ stats.departments }}` into prose copy and the JSON-LD FAQ block, despite brand guide §Numbers explicitly stating "never duplicate the exact count in prose, where it will drift as new agents and skills ship." This is the correct mechanism (Nunjucks variable) but the wrong placement (prose); it bypasses the soft-floor rule that was added to prevent stale "60+ agents" → "66 agents" drift across releases. The contract should be: exact counts in **stat strips and tables only**; **soft floors** ("60+ agents," "60+ skills") in prose.

2. **Search-intent coverage is thin in the middle of the funnel.** The site captures (a) brand/navigational intent and (b) high-intent transactional CTAs ("Join the Waitlist," "Reserve access"). It does not capture commercial-investigation traffic — visitors searching "AI agents for solo founders comparison," "Soleur vs Cursor," "best AI tools for solopreneurs" — even though the homepage FAQ contains exactly that comparison content. The Cursor/Copilot answer is gated behind a `<details>` collapsed-by-default element and not surfaced as crawlable H2/H3 anchors.

Two **on-brand wins** worth keeping:
- The Dario Amodei pull-quote on the homepage with a sourced link to Inc.com (brand guide AEO citation pattern, executed correctly).
- The `/pricing/` hiring-comparison table with explicit methodology footnotes citing Robert Half, Payscale, and Levels.fyi (textbook E-E-A-T signal, also brand-on-voice — concrete numbers, no hedging).

Two **brand-voice violations** to fix:
- The `/about/` H1 is the single word "About." Brand guide §Website calls for "Badge > Headline > Subheadline" structure; "About" violates the declarative-ambition rule and surrenders a keyword opportunity ("About Jean Deruelle, founder of Soleur" or "The founder behind Company-as-a-Service").
- `/vision/` uses the word "vessel" ("Soleur is the vessel that allows..."), "swarm," and "Global Brain" — these are abstract marketing-speak that violate the §Don't "trust the reader's intelligence / no over-explanation" rule and the prohibition on startup jargon. The page reads like an internal strategy memo, not a public vision page.

---

## Per-Page Analysis

### 1. Homepage (`/` → `index.njk`)

**SEO title:** `Soleur — AI Agents for Solo Founders | Every Department, One Platform`
**Meta description:** `Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support.`

**Detected target keywords**

| Keyword | Where it appears | Search-volume estimate (qual.) |
|---|---|---|
| "AI agents for solo founders" | SEO title, meta description | High brand-adjacent, head term |
| "Company-as-a-Service" | Section label, H1 deck-line, H2, FAQ | Owned brand term (~zero competing volume) |
| "stop hiring start delegating" | H1 hero, final CTA H2 | Positioning line, near-zero search volume |
| "AI organization" | H2 ("Your AI Organization"), body | Owned brand language |
| "compounding knowledge base" | Hero sub, problem cards, FAQ | Brand-owned term |
| "human-in-the-loop" | Hero trust line, FAQ #4 | Industry term, growing volume |

**Keyword alignment assessment**
- The SEO title nails the head keyword. Strong.
- The dual-headline pattern (positioning H1 + keyword-bearing deck-line) is the right structure for a brand-led hero. Voice-on, intent-recovered.
- Long-tail gap unchanged from 2026-05-04: "AI tools for solopreneurs," "delegate to AI agents," "AI for one-person company," "AI back office for founders" do not appear in any H2/H3.

**Search-intent match**
- Informational + commercial-investigation: partial. Hero serves informational; the seven-question FAQ block answers many investigation queries; but the most decision-relevant question — "How does Soleur differ from Cursor or GitHub Copilot?" — is the FAQ that should be surfaced as an H2 comparison section, not buried inside a collapsed `<details>` element.
- Transactional: strong. Waitlist form is above the fold; redundant CTA mid-page and at the end.
- Navigational: served correctly by the stat strip linking to `/agents/` and `/skills/`.

**Readability**
- Strong. Short declarative sentences. Department blocks follow a clean micro-pattern (icon → name → outcome). The Workflow grid (Think → Plan → Build → Review → Ship → Compound) is a textbook scannable layout. Aligns with §Voice (precise, no hedging) and §Density (generous whitespace).

**Issues**

| Severity | Issue |
|---|---|
| Critical | **Stats-in-prose drift hazard.** Hero sub-paragraph reads `Soleur is an open-source company-as-a-service platform that deploys {{ stats.agents }} AI agents across {{ stats.departments }} business departments...` This compiles to "66 AI agents across 8 business departments" today. Per brand guide §Numbers: "Use 60+ agents and 60+ skills in static documentation and marketing prose. The live site renders exact counts from the filesystem via {{ stats.agents }} / {{ stats.skills }} — **never duplicate the exact count in prose**." The intent of the rule is to keep exact counts in stat strips/tables (where drift is obvious and intended) and soft floors in narrative prose. The hero, the "Final CTA" paragraph, and 3 of 7 FAQ answers all violate this. The JSON-LD FAQ block has the same problem and will be scraped by AI engines verbatim. |
| Critical | **`Company-as-a-Service` capitalization is inconsistent.** Hero deck-line uses "Company-as-a-Service platform" (correct). Hero sub uses "company-as-a-service platform" (lowercase). FAQ #2 question is "What is company-as-a-service?" (lowercase). Brand guide §Tagline establishes the term as a proper noun. Pick one and apply consistently. |
| Improvement | **The strongest comparison FAQ is hidden in `<details>`.** "How does Soleur differ from Cursor or GitHub Copilot?" contains the most search-relevant content on the page for "Soleur vs Cursor" and "Cursor alternatives" queries. Either (a) keep the `<details>` element but add a non-collapsed H3 stub above it, or (b) promote the answer into a sibling section with an H2 like "Soleur vs. coding copilots." |
| Improvement | **Final-CTA H2 is identical to hero H1** ("Stop hiring. Start delegating."). Reusing the exact line at the close is voice-consistent, but the H2 is wasted as a duplicate. Use the close to surface the memory-first variant or a third-rail proof point. |
| Improvement | **"Or try the open-source version →" CTA wording.** Brand guide §Don't permits "open-source version" but bans "plugin" or "tool" in public copy. The CTA reads cleanly today; flag for re-review only if it gets rewritten to introduce "plugin." |
| Improvement | **The press strip has one entry.** "As seen in" with a single Inc.com row reads slightly thin. Either expand it (HN front-page snapshot, Dario quote provenance, podcast appearances if any) or rename the section to "In the conversation" to fit a single anchor proof. |

**Rewrite suggestions**

1. **Hero sub-paragraph — soft-floor restoration**
   - Current: `Soleur is an open-source company-as-a-service platform that deploys {{ stats.agents }} AI agents across {{ stats.departments }} business departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving a single founder the operational capacity of a full organization. Every agent shares a compounding knowledge base that grows with your business.`
   - Suggested: `Soleur is the open-source Company-as-a-Service platform: 60+ AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving one founder the operational capacity of a full organization. Every agent shares a compounding knowledge base that gets smarter the more you use it.`
   - Rationale: Restores soft-floor counts per §Numbers; capitalizes "Company-as-a-Service" consistently; tightens "single founder" → "one founder" (matches §Example Phrases "One founder. Full-stack AI."); replaces the abstract "grows with your business" with the brand-glossary phrasing "gets smarter the more you use it" (§Audience Voice Profiles general-register glossary). The exact count stays available in the stat strip directly below the hero, where drift is intentional.

2. **FAQ #1 — "What is Soleur?"**
   - Current: `Soleur deploys {{ stats.agents }} AI agents across {{ stats.departments }} business departments — engineering, marketing, legal, finance, operations, product, sales, and support — giving a single founder the capacity of a full organization. Every agent shares a compounding knowledge base, so your marketing agent knows what your legal agent decided, and your finance agent references your actual revenue data. Your expertise stays in the loop: agents provide starting points, you make the final call.`
   - Suggested: `Soleur is the Company-as-a-Service platform for solo founders. It deploys 60+ AI agents and 60+ skills across 8 departments — engineering, marketing, legal, finance, operations, product, sales, and support — so one founder runs the operational capacity of a full company. Every agent shares a compounding knowledge base, so your marketing agent knows what your legal agent decided, and your finance agent references your actual revenue data. Your expertise stays in the loop: agents provide starting points, you make the final call.`
   - Rationale: First sentence becomes a self-contained, quotable definition (§Structure — definition extractability; AEO-friendly). Adds the head keyword phrase "Company-as-a-Service platform for solo founders." Restores soft floors per §Numbers. The JSON-LD `<Answer>` text must be updated to match — that block is what AI engines cite.

3. **"How does Soleur differ from Cursor or GitHub Copilot?" — promote to surfaced H3**
   - Add above the `<details>` wrapper: `<h3 class="faq-heading">Soleur vs. Cursor and GitHub Copilot</h3>` (or similar, matching site CSS) with the first sentence ("Cursor and Copilot help you write code. Soleur helps you run a company.") rendered as a non-collapsed lead paragraph. Keep the rest inside the `<details>`.
   - Rationale: Captures commercial-investigation traffic for "soleur vs cursor" and "github copilot alternatives" queries without changing the FAQ pattern. Voice-on: declarative two-sentence comparison.

4. **Final CTA H2 — replace duplicate**
   - Current: `Stop hiring. Start delegating.` (identical to hero H1)
   - Suggested: `The AI that already knows your business.` with sub-line `60+ agents. One compounding memory. Your expertise, amplified.`
   - Rationale: Brand guide flags the memory-first variant as "the feature that separates Soleur from 'just use ChatGPT'" — generated the strongest unprompted positive reaction across personas. The hero leads with pain-point framing; the close should land the memory differentiator. Voice-on: declarative, concrete, no hedging.

---

### 2. `/pricing/` (`pricing.njk`)

**SEO title:** `Pricing — AI Agents for Solo Founders | Soleur`
**Meta description:** `All 8 departments -- engineering, marketing, legal, finance, sales, operations, product, and support -- from $49/month. Less than a single contractor.`

**Detected target keywords:** "Soleur pricing," "AI agents pricing," "AI agents for solo founders pricing," "company-as-a-service pricing"
**Keyword alignment:** SEO title and meta capture the head keyword well. On-page H1 "Every department. One price." is brand-led and high-voice. The subhead recovers the value frame ("for less than a single contractor"). Adequate; could be stronger if the H2 "Choose your scale. Keep every department." were paired with a keyword phrase like "Soleur pricing plans."
**Search-intent match:** Transactional — strong. Comparison table directly addresses the "vs. hiring" decision frame. FAQ resolves all common pre-purchase objections.
**Readability:** Strong. Tables are scannable. Numbers carry the page (per §Voice "Use concrete numbers when available").

**Issues**

| Severity | Issue |
|---|---|
| Critical | **`{{ stats.agents }}` drift hazard inside body copy.** The Plans subhead reads `Every plan includes all {{ stats.departments }} departments and {{ stats.agents }} agents.` Same drift-hazard as homepage. Departments (8) is structurally stable; agents (currently 66) is not. Use "all 8 departments and 60+ agents." |
| Critical | **"Concurrent conversations" definition is split across the page.** The plan card lists "2 concurrent conversations" without a tooltip or inline definition. The definition is in the FAQ below the plan grid. Brand guide §General register requires inline definition on first use of jargon. Add a footnote or one-line caption under the plan card features list. |
| Improvement | **Plan-card badge "Coming Soon" on every paid tier** with no shipping date. Brand guide §Don't bans hedging ("might, could, potentially"); a vague "Coming Soon" reads as a soft hedge. Replace with a concrete date band (e.g., "Q3 2026") or surface the founding-cohort intro link from `/getting-started/`. |
| Improvement | **Hiring-comparison table is the strongest E-E-A-T asset on the site.** It cites Robert Half, Payscale, and Levels.fyi inline. Lean into it: add an H2 above the methodology footnote like "Methodology: how we sourced the $95K/mo figure" — currently the footnote is small-text and the citations get visually buried. |
| Improvement | **Scenario callouts ("Enterprise prospect needs a DPA?")** use the role abbreviations "CLO," "CRO," "CMO," "CFO" without expansion. General-register readers (non-technical founders, per §Target Audience) may not parse these. Either spell out on first use or add an aside listing the abbreviations. |

**Rewrite suggestions**

1. **Plans subhead — soft floor**
   - Current: `Every plan includes all {{ stats.departments }} departments and {{ stats.agents }} agents. No feature gating by domain. Pick the concurrency that matches your stage.`
   - Suggested: `Every plan includes all 8 departments and 60+ agents. No feature gating by domain. Pick the concurrency that matches your stage.`
   - Rationale: §Numbers compliance. Eight departments is intentionally hard-coded in brand-guide tone ("60+ Agents · 8 Departments · 1 Founder" appears literally in the X banner spec); the agent count is not.

2. **Solo plan card — add concurrency definition**
   - Current feature list opens with: `2 concurrent conversations`
   - Suggested: `2 concurrent conversations <span class="pricing-feature-note">(two chats running work in parallel — your CTO reviews code while your CMO drafts copy)</span>`
   - Rationale: First-use inline definition per §General register. Mirrors the FAQ answer's example without making the visitor scroll to find it.

3. **Scenario callout — spell out role**
   - Current: `Your CLO drafts it, your compliance auditor reviews it, and it lands in their inbox`
   - Suggested: `Your legal lead (CLO) drafts it, your compliance auditor reviews it, and it lands in their inbox`
   - Rationale: General-register inline expansion. Voice stays declarative and concrete; the parenthetical adds zero word fluff.

---

### 3. `/about/` (`about.njk`)

**Page title (frontmatter):** `About Jean Deruelle`
**Meta description:** `Jean Deruelle is the founder of Soleur, a Company-as-a-Service platform giving solo founders the operational capacity of a full organization through AI agents.`

**Detected target keywords:** "Jean Deruelle," "Soleur founder," "who founded Soleur," "Jikigai Soleur"
**Keyword alignment:** Meta description is strong. The on-page H1 "About" wastes the keyword. Body copy and FAQ block answer every navigational-intent query correctly.
**Search-intent match:** Navigational — adequate. Anyone arriving here knows what they want and gets it. The page is also a strong ProfilePage schema target (already implemented in JSON-LD).
**Readability:** Adequate. Four-paragraph bio reads well. The "About Soleur" sub-section at the bottom is thin — three short paragraphs with three inline links — and ends the page abruptly.

**Issues**

| Severity | Issue |
|---|---|
| Critical | **H1 is a single word: "About."** Brand guide §Website calls for "Badge (ALL CAPS, gold) > Headline (Cormorant Garamond, white) > Subheadline (Inter, secondary text)." A one-word H1 surrenders the highest-impact element on the page. Voice-on alternatives: "About Jean Deruelle" or "The founder behind Soleur." |
| Improvement | **Bio omits the Dario Amodei thesis hook.** Paragraph 4 mentions Jean's thesis and links to the Inc.com article; this is the right move. But the bio opens with biographical detail (15+ years engineering) before the why. Voice-on (§Voice: "Lead with what becomes possible, not what the tool does") would reverse the order: thesis first, then credentials. |
| Improvement | **"About Soleur" closing section says "open-source Claude Code plugin."** Brand guide §Don't permits "plugin" only "in literal CLI commands, in legal documents where 'Plugin' is a defined term, and in technical documentation describing the installation mechanism." The About page is public-facing brand copy; "plugin" is not the right word here. Use "platform" or "open-source Company-as-a-Service platform that runs on Claude Code." |
| Improvement | **No H2 for the FAQ section.** The FAQ section uses the standard "Common Questions / Frequently Asked Questions" pattern, which is fine, but the four bio paragraphs are followed by a single `<ul>` of social links, then immediately the FAQ. A linking H2 like "More about Soleur" or a stronger transition would improve flow. |

**Rewrite suggestions**

1. **H1 — replace the one-word headline**
   - Current: `<h1>About</h1>` with sub `The founder behind Soleur.`
   - Suggested: `<h1>About Jean Deruelle</h1>` with sub `Founder of Soleur. Building the Company-as-a-Service platform for solo founders.`
   - Rationale: Brand guide §Website hero pattern (Badge > Headline > Subheadline). Captures the navigational keyword in the H1. Voice-on: declarative, ambitious, concrete, no hedging.

2. **Reorder bio paragraphs — thesis first**
   - Suggested opening sentence (new paragraph 1): `Jean Deruelle is building the first proof that a single founder can run a full company. He founded Soleur in early 2026 to solve a problem he was living: running eight departments with the time and budget for none of them.`
   - Then existing paragraph 2 (the engineering credentials) becomes paragraph 2; existing paragraph 3 (the launch + growth) becomes paragraph 3; existing paragraph 4 (thesis + Inc.com link) folds into paragraph 1.
   - Rationale: §Voice "Lead with what becomes possible, not what the tool does." Voice-on: declarative present-tense, no hedging.

3. **"About Soleur" — remove "plugin" framing**
   - Current: `Soleur is an open-source Claude Code plugin that turns a solo founder into a full AI organization.`
   - Suggested: `Soleur is the open-source Company-as-a-Service platform that turns a solo founder into a full AI organization. It runs on Claude Code today; the hosted platform is in development.`
   - Rationale: §Don't ("Call it a 'plugin' or 'tool' in public-facing content — it is a platform"). Adds the hosted-platform forward signal that visitors arriving from search expect.

---

### 4. `/vision/` (`vision.njk`)

**SEO title (effective):** `Soleur Vision: Company-as-a-Service`
**Meta description:** `The Soleur vision: company-as-a-service for solo founders. AI agents across every department giving one person the operational capacity of a full organization.`

**Detected target keywords:** "company-as-a-service," "billion-dollar solo founder," "AI agent orchestration," "AI organization platform"
**Keyword alignment:** Owned-brand terms covered. Misses entry-level informational queries like "what is a company-as-a-service platform" — the page assumes the reader is already bought in.
**Search-intent match:** Informational — partial. The page reads like an internal strategy doc, not a public vision page. Concepts ("Global Brain," "Decision Ledger," "Swarm of Agents") are introduced as proper nouns ("Internally called...") without earning the capitalization.
**Readability:** Weak. Sentences are dense and abstract. Multiple §Don't violations.

**Issues**

| Severity | Issue |
|---|---|
| Critical | **"Soleur is the vessel that allows those with unique insights to capture the non-linear rewards..."** "Vessel" is metaphor-as-jargon and reads as startup-speak. §Don't bans "synergy," "disrupt," "move the needle" — "vessel" sits in the same register. Replace with a concrete subject. |
| Critical | **"Swarm of Agents," "Global Brain," "Decision Ledger" introduced as proper nouns.** Brand guide §Don't: "Trust the reader's intelligence -- over-explain." These internal codenames are introduced with quote marks and "internally called" framing that calls attention to themselves without earning it. The reader doesn't yet care what the team calls things internally. |
| Improvement | **No H2 captures the head keyword "What is Company-as-a-Service?"** Visitors arriving from the search "what is company-as-a-service" land here and have to infer the definition from paragraph 2. Promote the definition into a labeled H2. |
| Improvement | **"Curator (CEO)" framing diverges from the rest of the site.** Homepage and pricing use "founder makes decisions, agents execute." Vision page introduces "curator" as a new term. Pick one and apply across all pages. |
| Improvement | **Three card grids in a row** (Core Value Proposition, Model-Agnostic Architecture, Strategic Architecture) without intervening prose. The page reads as a deck slide list. Add 1-2 sentence prose transitions between card grids to give the reader narrative scaffolding. |

**Rewrite suggestions**

1. **Replace "vessel" sentence**
   - Current: `Soleur is the vessel that allows those with unique insights to capture the non-linear rewards of the AI revolution.`
   - Suggested: `Soleur turns judgment and taste into leverage. When code and AI replicate labor at near-zero marginal cost, the founder's unique insight becomes the entire moat. Soleur is the platform that makes one founder's insight scale like a hundred-person team.`
   - Rationale: Removes the "vessel" metaphor. Voice-on: three short declarative sentences, concrete subject, ends on the leverage claim. §Voice "Use declarative statements" and "Write like the future is already here."

2. **Demote internal codenames**
   - Current (Multi-Model AI Agent Orchestration card): `Internally called "The Global Brain". Soleur selects the best model for each task -- Claude for coding, GPT-4o for strategy, local models for privacy-sensitive data.`
   - Suggested: `Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy. Local models for privacy-sensitive data. One orchestrator across every provider.`
   - Rationale: Removes the internal-jargon callout. Brand voice gets crisper, the parallelism lands harder. Same fix to "Decision Ledger" and "Swarm of Agents" cards.

3. **Add a definitional H2**
   - Suggested insertion (just after the page hero, before "The Company-as-a-Service Platform" H2): a section labeled `WHAT IS COMPANY-AS-A-SERVICE?` with a single-paragraph definition that quotes cleanly: `Company-as-a-Service means delegating business functions to AI agents instead of hiring for each department. You provide the decisions and judgment. Agents execute across engineering, marketing, legal, finance, sales, operations, product, and support. A shared knowledge base compounds across all departments over time.`
   - Rationale: Captures the entry-level informational query. AEO-friendly definition extractability (§Structure). Voice-on: declarative, concrete, the same definition pattern as the homepage FAQ.

---

### 5. `/getting-started/` (`getting-started.njk`)

**SEO title (effective):** `Getting Started with Soleur`
**Meta description:** `The AI that already knows your business. Soleur remembers every decision and customer so your team stops re-explaining context. Reserve access.`

**Detected target keywords:** "Soleur install," "Soleur quickstart," "Claude Code plugin install," "AI agents getting started"
**Keyword alignment:** Strong on transactional/onboarding intent. Hero H1 is the memory-first variant ("The AI that already knows your business") — this is the only page on the site that leads with the brand-guide-recommended A/B variant. Worth promoting that pattern to the homepage close (see homepage rewrite #4).
**Search-intent match:** Transactional + how-to. Dual-CTA (Reserve access / Run open source today) covers both audiences. Concrete two-command install block is exactly what a technical-register reader wants.
**Readability:** Strong. Workflow steps listed numerically, command grid uses `<code>` blocks correctly.

**Issues**

| Severity | Issue |
|---|---|
| Improvement | **"Founding cohort — limited to 10" framing.** Voice-on, but the scarcity claim needs a freshness signal — when was the 10-slot cap set, and how many remain? Without that, the line reads as evergreen marketing copy. Either rotate it weekly or replace with a static "Email ops@jikigai.com to discuss founding-cohort access." |
| Improvement | **"6-step workflow" vs. brand guide §Voice "60+ agents, 60+ skills."** The page describes the workflow in steps (Think/Plan/Build/Review/Ship/Compound on the homepage; brainstorm/plan/work/review/compound/ship here using internal skill names). The two pages name the same six steps differently. Pick one labeling system (the homepage's noun forms are more public-facing) and use it consistently. |
| Improvement | **The "Run it yourself" H2 mid-page is a §Don't borderline.** "Run it yourself" is fine; "Prefer to run it yourself?" in the lead paragraph hedges ("Prefer to" implies an opt-out rather than a clear branch). Restructure as a clean two-path framing. |

**Rewrite suggestions**

1. **Memory-first H1 — apply consistently elsewhere**
   - This page's H1 (`The AI that already knows your business.`) is the brand-guide-recommended memory-first variant for A/B testing. No rewrite needed on this page; **action is to propagate** this line to the homepage final CTA (homepage rewrite #4). Cite this audit as the source.

2. **"Run it yourself" intro paragraph**
   - Current: `Prefer to run it yourself? Soleur is open source and works in Claude Code today. Install it in two commands, keep every byte of memory on your own machine, and upgrade to the hosted version whenever you're ready.`
   - Suggested: `Soleur is open source. Install it in Claude Code in two commands, keep every byte of memory on your own machine, and upgrade to the hosted version whenever you're ready.`
   - Rationale: Removes the hedged opener. Voice-on: declarative, no "Prefer to" softener. §Voice "Don't hedge."

---

## Issues — Prioritized Roll-Up

| ID | Page | Severity | Issue | Brand-guide anchor |
|----|------|----------|-------|---------------------|
| C-1 | Homepage | Critical | `{{ stats.agents }}` interpolated into hero prose + FAQ + JSON-LD (drift hazard) | §Numbers (soft floors in prose) |
| C-2 | Homepage | Critical | "Company-as-a-Service" capitalization inconsistent (hero deck vs. hero sub vs. FAQ #2) | §Tagline / proper-noun rule |
| C-3 | Pricing | Critical | `{{ stats.agents }}` in Plans subhead body copy | §Numbers |
| C-4 | Pricing | Critical | "Concurrent conversations" undefined on the plan card (only defined in FAQ below) | §General register inline definition |
| C-5 | About | Critical | H1 is the single word "About" — surrenders headline real-estate and keyword | §Website hero pattern |
| C-6 | Vision | Critical | "Soleur is the vessel that allows..." — metaphor-as-jargon | §Don't startup jargon |
| C-7 | Vision | Critical | Internal codenames "Global Brain / Decision Ledger / Swarm of Agents" introduced as proper nouns | §Don't over-explain |
| I-1 | Homepage | Improvement | Cursor/Copilot comparison answer buried in collapsed `<details>` — strongest comparison content not surfaced | §Search intent (commercial investigation) |
| I-2 | Homepage | Improvement | Final-CTA H2 duplicates hero H1 verbatim | Voice efficiency |
| I-3 | Homepage | Improvement | Press strip has one entry; reads thin | E-E-A-T |
| I-4 | Pricing | Improvement | "Coming Soon" badges on all paid tiers with no date | §Don't hedge |
| I-5 | Pricing | Improvement | Methodology footnote (Robert Half / Payscale / Levels.fyi) buried as small text | E-E-A-T citation visibility |
| I-6 | Pricing | Improvement | Scenario callouts use CLO/CRO/CMO/CFO abbreviations un-expanded | §General register |
| I-7 | About | Improvement | Bio opens with credentials, not thesis | §Voice "Lead with what becomes possible" |
| I-8 | About | Improvement | "Open-source Claude Code plugin" in About Soleur section | §Don't "plugin in public-facing content" |
| I-9 | Vision | Improvement | No H2 anchor for "What is Company-as-a-Service?" definitional query | §Search intent (informational) |
| I-10 | Vision | Improvement | "Curator (CEO)" framing diverges from rest of site ("founder makes decisions") | Cross-page consistency |
| I-11 | Vision | Improvement | Three card grids in a row with no narrative transitions | §Density / readability |
| I-12 | Getting Started | Improvement | "Founding cohort — limited to 10" lacks freshness signal | Trust scaffolding |
| I-13 | Getting Started | Improvement | Workflow-step naming differs from homepage Workflow grid | Cross-page consistency |
| I-14 | Getting Started | Improvement | "Prefer to run it yourself?" hedged opener | §Don't hedge |

---

## Prioritized Recommendations

### P1 — ship this week (1-2 hours of edits)

1. **Apply soft floors in prose (C-1, C-3)** across `index.njk` hero sub + Final CTA paragraph, JSON-LD FAQ block, and `pricing.njk` Plans subhead. Replace `{{ stats.agents }}` with `60+` and `{{ stats.skills }}` with `60+` in narrative copy only. Keep `{{ stats.* }}` in stat strips, tables, and structured-data fields. This is a Find-and-Replace within five files.
2. **Capitalize "Company-as-a-Service" consistently (C-2)** as a proper noun on every public page. One pass across `index.njk`, `pricing.njk`, `about.njk`, `vision.njk`, `getting-started.njk`, `company-as-a-service.njk`. Update FAQ JSON-LD `name` fields to match.
3. **Replace the `/about/` H1 (C-5)** with "About Jean Deruelle" + memory-first deck-line. One line change.
4. **Define "concurrent conversations" on the Solo plan card (C-4)** with the one-line example from the FAQ answer.
5. **Replace the "vessel" sentence on `/vision/` (C-6)** with the three-sentence rewrite above.

### P2 — next sprint (4-6 hours)

6. **Promote the Cursor/Copilot comparison out of `<details>` (I-1)** as a standalone H3 with a 1-paragraph lead, keep the deep answer collapsed. Captures commercial-investigation traffic.
7. **Demote internal codenames on `/vision/` (C-7)** — strip "Global Brain," "Decision Ledger," "Swarm of Agents" proper-noun framing. Same content, less inside-baseball voice.
8. **Reorder `/about/` bio to thesis-first (I-7)** and replace "Claude Code plugin" framing (I-8).
9. **Add a "What is Company-as-a-Service?" H2 anchor on `/vision/` (I-9)** with the homepage FAQ definition.
10. **Replace pricing "Coming Soon" badges (I-4)** with a date band or founding-cohort link.

### P3 — later (depends on calendar / shipping)

11. **Expand the press strip on the homepage (I-3)** when a second outlet ships. Until then, rename to "In the conversation" or "Featured in."
12. **Surface the pricing methodology footnote (I-5)** as an H3 with a "How we sourced $95K/mo" anchor. Improves E-E-A-T and gives the page a citation-friendly section.
13. **Unify workflow-step naming across homepage and getting-started (I-13).** Adopt the public noun forms (Think/Plan/Build/Review/Ship/Compound) on both pages.
14. **Rotate the founding-cohort scarcity claim weekly (I-12)** or replace with a static contact prompt.

### Cross-page consistency sweep (do alongside P1)

- "Single founder" vs. "one founder": brand guide §Example Phrases uses "One founder. Full-stack AI. No compromises." — standardize on "one founder" in marketing prose.
- "Curator" (vision) vs. "founder makes decisions" (homepage, pricing) — drop "curator" except in `/vision/` where it can stay as a vocabulary aside.
- The Dario Amodei quote appears on `/`, `/vision/`, and `/about/`. All three link to Inc.com correctly. Keep the consistency; flag if any page adds a new pull-quote without source link.

---

## Voice-Alignment Spot-Check

| Brand-guide rule | Pages compliant | Pages with at least one violation |
|---|---|---|
| §Don't "plugin in public copy" | `/`, `/pricing/`, `/vision/`, `/getting-started/` (hero) | `/about/` ("open-source Claude Code plugin") |
| §Don't "AI-powered / leverage AI" | All 5 | None |
| §Don't "just / simply" hedges | `/`, `/pricing/`, `/about/`, `/vision/` | `/getting-started/` ("Prefer to run it yourself?") |
| §Don't startup jargon ("vessel," "synergy," "disrupt") | `/`, `/pricing/`, `/about/`, `/getting-started/` | `/vision/` ("vessel") |
| §Numbers soft floors in prose | None fully compliant (all use `{{ stats.* }}` interpolation in prose) | `/`, `/pricing/`, `/about/` |
| §Website hero pattern (Badge > Headline > Subheadline) | `/`, `/pricing/`, `/getting-started/` | `/about/` ("About" H1) |
| Capitalize "Company-as-a-Service" | `/pricing/` (consistent lowercase in body intentionally), `/vision/` (consistent) | `/`, `/about/` mix lowercase + capitalized |

---

## Notes for the SEO-AEO Analyst

Out of scope for this content audit but worth flagging:

- The live site returned Cloudflare 526 throughout the audit window — investigate origin SSL.
- JSON-LD FAQ blocks on `/`, `/pricing/`, and `/about/` will need to be regenerated after the soft-floor rewrites land (the JSON-LD strings hard-code the exact counts via Nunjucks concatenation).
- The `/about/` ProfilePage schema is in place — verify `name`, `worksFor.name`, and `sameAs` array render correctly under the new H1.
- The `meta description` on `/pricing/` uses `--` (en-dash) where the rest of the site uses `—` (em-dash). Cosmetic, but worth normalizing.
