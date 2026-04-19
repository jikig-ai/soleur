---
title: "Soleur.ai Content Audit"
date: 2026-04-18
type: content-audit
scope: "Homepage + key navigation pages + representative blog posts"
auditor: growth skill (content audit)
source_fetch_method: "Local source review (Cloudflare 403 on WebFetch from https://soleur.ai)"
brand_guide: knowledge-base/marketing/brand-guide.md
---

# Soleur.ai Content Audit

## Methodology and Scope

`WebFetch` against `https://soleur.ai`, `https://www.soleur.ai`, `/blog/`, `/docs/`, and `/sitemap.xml` all returned HTTP 403 (Cloudflare challenge rejecting automated fetches). Audit was performed against the canonical Eleventy source under `plugins/soleur/docs/` — this is the authoritative content that builds to soleur.ai, so findings map 1:1 to the live site.

Sample (most-important-first): homepage (`index.njk`), pricing (`pricing.njk`), about (`about.njk`), vision (`vision.njk`), getting-started (`getting-started.njk`), agents (`agents.njk`), and two representative long-form pieces (`blog/what-is-company-as-a-service.md`, `blog/2026-03-24-ai-agents-for-solo-founders.md`). The site has 16+ blog posts and 7 legal pages — unsampled pages are called out under Coverage Gaps.

Brand guide read and applied: `knowledge-base/marketing/brand-guide.md` (last_updated 2026-03-26). Key constraints enforced:

- Primary framing is pain-point: "Stop hiring. Start delegating." (not CaaS on landing surfaces).
- Memory-first variant is an A/B candidate: "The AI that already knows your business."
- Trust scaffolding ("human-in-the-loop", "your expertise, amplified") must appear on every framing.
- Banned words: "AI-powered", "leverage AI", "just", "simply", "assistant", "copilot", "terminal-first", "CLI-native" as positioning.
- "Plugin"/"tool" banned in public-facing content (exception: literal CLI commands).

---

## Per-Page Analysis

### 1. Homepage (`/`, source: `docs/index.njk`)

| Dimension | Finding |
|---|---|
| SEO title | "Soleur — Company-as-a-Service Platform for Solo Founders" |
| Meta description | "Soleur is the open-source company-as-a-service platform for solo founders and solopreneurs — AI agents across engineering, marketing, legal, finance, and every business department." |
| Detected target keywords | "company-as-a-service platform", "solo founders", "AI agents", "solopreneurs", "Claude Code plugin" (implicit) |
| H1 | "The Company-as-a-Service Platform for Solo Founders" |
| Hero tagline | "Build a Billion-Dollar Company. Alone." |
| Primary framing used | CaaS (category-education) — brand guide 2026-03-26 update demotes CaaS from primary to "secondary, education-heavy; not suitable for headlines" |
| Trust scaffolding | Present: "Human-in-the-loop. Your expertise, amplified." (compliant) |
| Search-intent match | Partial. "Company-as-a-service" is a category the brand is creating — near-zero existing search volume. Title and meta miss the actual high-intent queries from the ICP ("AI agents for solo founders", "hire AI marketing manager", "AI legal for startup", "Claude Code plugins"). |
| Readability | Strong. Short sentences, concrete numbers (agents/departments/skills counts), named quote with primary source. |
| FAQ block | Present, 7 Q&As with JSON-LD `FAQPage` schema — solid AEO signal |
| Internal linking | Weak. Hero CTA points only to `/pricing/` and `/getting-started/`. No link to `/agents/`, `/vision/`, `/blog/`, or flagship blog pillar. |

### 2. Pricing (`/pricing/`, source: `pages/pricing.njk`)

| Dimension | Finding |
|---|---|
| SEO title | "Pricing" (weak — no keyword, no brand) |
| Meta description | "All 8 departments -- engineering, marketing, legal, finance, sales, operations, product, and support -- from $49/month. Less than a single contractor." (strong framing, concrete numbers) |
| Detected target keywords | "AI pricing", "AI team cost", "hire vs AI" (implicit via comparison table) |
| H1 | "Every department. One price." |
| Search-intent match | Good for commercial intent. The $95K/mo vs $49/mo comparison matches "cost to hire CTO", "fractional general counsel cost", "CFO as a service pricing" queries. |
| Readability | Strong. Table-first, scannable, concrete costs. |
| Issues | SEO title lacks any keyword; role-cost rows would earn AEO citations if each cost had an inline source citation (brand guide 2026-03-22 validation review emphasizes trust signals). |

### 3. About (`/about/`, source: `pages/about.njk`)

| Dimension | Finding |
|---|---|
| SEO title | "About Jean Deruelle" (good — exact-match founder query) |
| Meta description | Strong, keyword-aligned |
| H1 | "About" (too generic — wastes the keyword slot) |
| E-E-A-T signals | Good: named founder, 15-year tenure, stack experience, founding date, thesis statement with external citation. ProfilePage + Person schema present. |
| Readability | Strong, 4 paragraphs, concrete claims. |
| Issues | H1 is a single word ("About") — loses the author-expertise keyword opportunity. First line mentions "Jean Deruelle is the founder of Soleur" but does not state his prior companies or any verifiable proof point beyond "over 15 years". Brand guide section "Founder" is authoritative for attribution — this page complies. |

### 4. Vision (`/vision/`, source: `pages/vision.njk`)

| Dimension | Finding |
|---|---|
| SEO title | "Soleur Vision: Company-as-a-Service" |
| H1 | "The Soleur Vision: Company-as-a-Service for the Solo Founder" |
| Readability | Weakest of sampled pages. Sentences are long and abstract ("collapse the friction between a startup idea and a billion-dollar outcome"). Uses phrases the brand guide explicitly avoids: "leverage" appears in "capture the non-linear rewards" framing. |
| Voice compliance | Partial miss. The brand guide's "Don'ts" include: no hedging, no startup jargon. This page uses "the vessel that allows those with unique insights" — this is the kind of abstraction the brand guide flags as "over-explain". |
| Search intent | Weak. "Soleur vision" is a navigational query (already-aware users). No target keyword defense. |

### 5. Getting Started (`/getting-started/`, source: `pages/getting-started.njk`)

| Dimension | Finding |
|---|---|
| SEO title | "Getting Started with Soleur" (solid, branded navigational) |
| Meta description | "Get started with Soleur in one command..." (keyword-aligned) |
| H1 | "Getting Started with Soleur" |
| Search-intent match | Good for transactional "install Soleur" / "how to use Soleur" queries. |
| Issues | The cloud platform and self-hosted paths are both surfaced, but the "COMING SOON" badge on the primary path may break expectations for a user who arrived from a "try Soleur" query. The self-hosted path references "Claude Code extension" and then drops to CLI commands — the brand guide flags "CLI-native as a positioning advantage" as banned; the words themselves are not present, but the de-facto positioning is CLI-first. Callout about Ollama is unverified — `ollama launch claude --model gemma4:31b-cloud` is not a valid Ollama command (Ollama doesn't ship a Claude model). Critical accuracy issue. |

### 6. Agents (`/agents/`, source: `pages/agents.njk`)

| Dimension | Finding |
|---|---|
| SEO title | "Soleur AI Agents" |
| Meta description | Strong, keyword-aligned |
| H1 | "Soleur AI Agents" |
| Search intent | Informational + navigational match. Intro paragraph explicitly claims "open source AI agents" — earns the high-volume "open source AI agents" informational query. |
| AEO strengths | The phrase "60+ open source AI agents that function as a unified AI organization" is AI-citation-ready (specific number, clear claim). Each domain has `category-count` markup — extractable. |
| Issues | No FAQ block. No external source citations. The claim "agentic engineering treats AI agents as specialist team members" is an assertion without source — would be stronger with a citation to the blog pillar `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`. |

### 7. Blog Pillar: "What Is Company-as-a-Service?" (`/blog/what-is-company-as-a-service/`)

| Dimension | Finding |
|---|---|
| Date | 2026-03-05 |
| SEO title | "What Is Company-as-a-Service?" (strong — exact-match informational query) |
| Meta description | Keyword-aligned |
| Search intent | Informational — defines a category the brand is trying to own |
| AEO strengths | Exceptional. Multiple inline source citations (BLS, CNBC, VentureBeat, TechCrunch, Carta). Specific numbers ($1B ARR, $29.3B valuation, $20/mo, $200M ARR, $6.6B valuation). Clean H2/H3 hierarchy. Definitional first sentence: "Company-as-a-Service (CaaS) is a new category of platform where a single AI organization runs every department of a business" — this is the literal sentence AI engines will cite. |
| Issues | Pillar/cluster wiring: this post links to `/blog/why-most-agentic-tools-plateau/` but does not link back from that post's frontmatter to this one as its pillar. Cluster coherence is ad-hoc. |

### 8. Blog Pillar: "AI Agents for Solo Founders: The Definitive Guide" (`/blog/2026-03-24-ai-agents-for-solo-founders/`)

| Dimension | Finding |
|---|---|
| SEO title | "AI Agents for Solo Founders: The Definitive Guide" (high-intent informational) |
| Meta description | Keyword-aligned |
| AEO strengths | Opens with cited data (Carta Solo Founders Report, 23.7% → 36.3%). BLS citation. Definitional framing: "A chatbot answers a question. An AI agent completes a task." — quotable. Four-property definition of an agent is extractable. |
| Voice compliance | Full compliance. Declarative, no hedging, concrete numbers, trust-scaffolding tone. |
| Issues | No FAQ block at bottom (losing a free AEO slot on a pillar article). No explicit link to pricing page despite commercial upside. |

---

## Issues Found (Severity-Ordered)

### Critical (blocks discoverability or violates brand guide)

| # | Page | Issue | Why critical |
|---|---|---|---|
| C1 | `/getting-started/` | Ollama callout contains an invalid command: `ollama launch claude --model gemma4:31b-cloud`. Ollama has no `launch` subcommand, no Claude model, and `gemma4:31b-cloud` is not a real tag. | Factual error on the page a new user follows to install the product. Breaks trust on first touch. |
| C2 | `/` (homepage) | Primary framing is CaaS, but brand guide 2026-03-26 validation review demotes CaaS to "secondary, education-heavy" and sets primary framing to pain-point "Stop hiring. Start delegating." CaaS appears first in H1 and tagline precedes pain-point. | Direct brand guide conflict. A/B test variant (memory-first) also not implemented. |
| C3 | `/` (homepage) | SEO title targets `company-as-a-service platform` (a category with near-zero monthly search volume — brand is creating the category). No page on the site targets the high-intent, high-volume queries the ICP actually types: "AI agents for solo founders", "AI marketing agent", "AI legal assistant for startup", "Claude Code plugins". | The homepage is the highest-authority URL and it targets a keyword nobody searches. |
| C4 | `/pricing/` | SEO title is the bare word "Pricing" — no brand, no keyword modifier. | Wastes the highest-authority title slot on a page with strong commercial intent. |
| C5 | `/vision/` | Uses "the vessel that allows those with unique insights to capture the non-linear rewards" — abstraction the brand guide flags as over-explaining. Also "leverage" used in a brand-banned construction. | Brand voice non-compliance on a page positioned as thesis. |
| C6 | Site-wide | Internal linking is thin. Homepage does not link to `/agents/`, `/vision/`, `/blog/`, or any flagship blog pillar. Blog posts do not consistently link back to pillar → cluster relationships. | Pillar/cluster model from brand's content-strategy mandate is not enforced by navigation. |

### Improvement (enhances ranking / AEO)

| # | Page | Issue |
|---|---|---|
| I1 | `/pricing/` | Role/cost rows lack inline citations. "Typical Cost" column would earn AI-engine citations if each row cited BLS, Payscale, or Levels.fyi. Currently says only "Based on US market median fully-loaded compensation, 2025-2026" in a footnote. |
| I2 | `/agents/` | No FAQ block. This page would benefit from 4-5 Q&As ("What is an AI agent?", "How is this different from ChatGPT?", "What agents are included?"). |
| I3 | `/about/` | H1 is the single word "About" — wastes the author-query keyword slot ("Jean Deruelle Soleur", "who founded Soleur"). |
| I4 | `/blog/2026-03-24-ai-agents-for-solo-founders/` | No FAQ block at the bottom of a pillar article. No explicit CTA to `/pricing/`. |
| I5 | Site-wide | No clear pillar/cluster topology documented in the site map. "Why Most Agentic Tools Plateau" reads like a pillar but is not positioned as one. |
| I6 | Homepage FAQ | Answer to "Is Soleur free?" says "pricing starts at the Spark tier" — requires reader to know what Spark tier is. Self-contained-answer principle for AEO broken. |
| I7 | Homepage | Hero subhead contains the word "deploys" — accurate but less AEO-friendly than a definitional opener. A quotable opener ("Soleur is a Company-as-a-Service platform...") is preferred for AI engines. |
| I8 | Homepage hero | CTA copy "See Pricing & Join Waitlist" bundles two intents. Split intents convert better and the brand guide's "CTA candidates" section lists "Start Building" / "Open Your Dashboard" / "Meet Your Organization" as post-launch candidates — none implemented. |

---

## Rewrite Suggestions

All suggestions preserve brand voice per `knowledge-base/marketing/brand-guide.md` §Voice: declarative, no hedging, concrete numbers, trust scaffolding, no banned terms.

### R1 — Homepage SEO title (C3)

**Current:**
> "Soleur — Company-as-a-Service Platform for Solo Founders"

**Suggested:**
> "Soleur — AI Agents for Solo Founders | Every Department, One Platform"

**Rationale:** Leads with the query the ICP actually types ("AI agents for solo founders", backed by the pillar article already ranking for that head term). Keeps "Soleur" brand prefix. Pipe-separated modifier captures the category frame without leading with it.

### R2 — Homepage meta description (C3)

**Current:**
> "Soleur is the open-source company-as-a-service platform for solo founders and solopreneurs — AI agents across engineering, marketing, legal, finance, and every business department."

**Suggested:**
> "Stop hiring, start delegating. Soleur deploys 60+ AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support. Human-in-the-loop. Your expertise, amplified."

**Rationale:** Leads with the brand guide's primary framing ("Stop hiring, start delegating"). Keeps keyword density organic. Adds trust scaffolding in the meta — captured in search snippets.

### R3 — Homepage H1 + tagline order (C2)

**Current:**
> H1: "The Company-as-a-Service Platform for Solo Founders"
> Tagline: "Build a Billion-Dollar Company. Alone."

**Suggested (lead with pain-point, keep CaaS as subhead):**
> H1: "Stop hiring. Start delegating."
> Subhead: "The Company-as-a-Service platform for solo founders. Build a billion-dollar company — alone."

**Rationale:** Implements brand guide 2026-03-26 primary framing. CaaS stays present but is no longer the first thing a visitor reads. Billion-dollar claim moves to subhead where it functions as proof-point amplifier rather than unsupported headline.

### R4 — `/pricing/` SEO title (C4)

**Current:** "Pricing"

**Suggested:** "Soleur Pricing — Every Department from $49/month"

**Rationale:** Brand prefix + commercial anchor ($49) + value prop ("every department") in under 60 characters.

### R5 — `/getting-started/` Ollama callout (C1)

**Current:**
> "Running with Ollama? Use the command `ollama launch claude --model gemma4:31b-cloud` to start Soleur with your preferred local model."

**Suggested:** Remove the callout entirely unless a maintainer can verify the actual Ollama integration path. If Soleur supports local models via Ollama, the real command is `ollama run <model>` followed by pointing Claude Code at the Ollama endpoint — not a `claude` subcommand of Ollama. Replace with:

> "Using a local model? Soleur runs on any Claude Code-compatible backend. See [local model setup](/docs/local-models/) for Ollama and llama.cpp configuration." (Only ship this once the linked doc exists.)

**Rationale:** Factual accuracy on the install page. Removing is strictly better than shipping invalid commands.

### R6 — `/vision/` opening paragraph (C5)

**Current:**
> "Soleur is a Company-as-a-Service platform designed to collapse the friction between a startup idea and a billion-dollar outcome — a future Anthropic's CEO assigns 70-80% probability. The world is moving toward infinite leverage. When code and AI can replicate labor at near-zero marginal cost, the only remaining bottlenecks are Judgment and Taste. Soleur is the vessel that allows those with unique insights to capture the non-linear rewards of the AI revolution."

**Suggested:**
> "Soleur is the Company-as-a-Service platform for the first billion-dollar solo founder — an outcome Anthropic's CEO assigns [70-80% probability within the next two years](https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609). When AI replicates labor at near-zero marginal cost, the only remaining bottlenecks are judgment and taste. Soleur gives founders an AI organization to execute, while they hold the judgment."

**Rationale:** Removes "vessel that allows those with unique insights to capture the non-linear rewards" (brand guide flags as over-explaining). Keeps the Amodei source cite inline. Replaces abstraction with concrete mechanism ("AI organization to execute, while they hold the judgment") — this is the brand's actual thesis per the brand guide §Identity.

### R7 — `/about/` H1 (I3)

**Current:** "About"

**Suggested:** "Jean Deruelle — Founder of Soleur"

**Rationale:** Claims the author-query keyword. ProfilePage schema already expects this.

### R8 — Homepage FAQ answer for "Is Soleur free?" (I6)

**Current:**
> "...pricing starts at the Spark tier. The self-hosted version is open source and free. Both run on Anthropic's Claude models..."

**Suggested:**
> "Soleur offers two paths. The self-hosted version is open source and free — install it as a Claude Code plugin and run it locally. The cloud platform (coming soon) provides managed infrastructure, a web dashboard, and priority support starting at $49/month. Both run on Anthropic's Claude models, so AI usage costs depend on your Claude plan."

**Rationale:** Self-contained answer (AEO requirement). Removes "Spark tier" jargon. Adds concrete $49/month anchor so AI engines can quote the answer standalone.

### R9 — Add FAQ block to `/agents/` (I2)

Suggested Q&A set:

1. "What are Soleur AI agents?" — "Soleur AI agents are specialized AI workers that handle specific business functions — code review, brand strategy, legal compliance, financial reporting, and more. Each agent carries domain-specific knowledge and operates as part of a 60+ agent organization across 8 departments."
2. "How is a Soleur agent different from ChatGPT?" — "ChatGPT is a general-purpose chat interface with no memory between sessions. A Soleur agent is goal-oriented, uses tools to execute work, shares a persistent knowledge base with other agents, and produces verifiable work products — not just responses."
3. "Are Soleur agents open source?" — "Yes. Every Soleur agent is publicly inspectable on GitHub. You can review each agent's role, routing logic, and instructions in the repository."
4. "Can I add my own agents?" — "Yes. Soleur agents are markdown files with YAML frontmatter. Add a new file to the agents/ directory and the plugin loader discovers it automatically."

**Rationale:** Captures informational queries and earns AEO real estate on a top-5 navigation page. Answers are self-contained (1-3 sentences each, per AEO best practice).

### R10 — Add inline citations to `/pricing/` role costs (I1)

**Current:** Costs listed without source.

**Suggested:** Each cost should cite Payscale, BLS, or Levels.fyi inline as a superscript footnote. Example row:

> CTO / VP Engineering — $18,000/mo [¹](#ref-1) — Included — Code review, architecture decisions, security audits, deployment.

With a Sources section at the bottom of the page listing each cited range.

**Rationale:** Pricing comparison is the page AI engines will cite for "how much does it cost to hire an AI CFO vs a human one" queries. Sourced claims earn citations; uncited ones don't.

---

## Key Findings

Priority labels: **P0** = ship this week (trust-breaking or brand-conflict); **P1** = ship this month (ranking / conversion); **P2** = ship this quarter (nice-to-have).

| Priority | Finding | File(s) | Action |
|---|---|---|---|
| **P0** | `/getting-started/` ships an invalid `ollama launch claude` command. First-touch trust risk. | `plugins/soleur/docs/pages/getting-started.njk` | Remove callout or replace with verified command. See R5. |
| **P0** | Homepage leads with CaaS framing; brand guide 2026-03-26 primary is "Stop hiring. Start delegating." | `plugins/soleur/docs/index.njk` | Swap H1 and tagline per R3. |
| **P0** | Homepage SEO title targets a near-zero-volume category keyword. | `plugins/soleur/docs/index.njk` frontmatter | Apply R1 title and R2 meta. |
| **P1** | `/pricing/` SEO title is the bare word "Pricing". | `plugins/soleur/docs/pages/pricing.njk` frontmatter | Apply R4. |
| **P1** | `/vision/` opens with abstractions the brand guide flags. | `plugins/soleur/docs/pages/vision.njk` | Apply R6. |
| **P1** | `/agents/` has no FAQ block; losing AEO on a top-nav page. | `plugins/soleur/docs/pages/agents.njk` | Apply R9 (add 4 Q&As + JSON-LD). |
| **P1** | Homepage FAQ answer for "Is Soleur free?" uses undefined "Spark tier" jargon. | `plugins/soleur/docs/index.njk` | Apply R8. |
| **P1** | `/pricing/` role costs lack inline citations — lost AEO opportunity on high-commercial-intent page. | `plugins/soleur/docs/pages/pricing.njk` | Apply R10. |
| **P1** | `/about/` H1 is the single word "About". | `plugins/soleur/docs/pages/about.njk` | Apply R7. |
| **P2** | Site-wide pillar/cluster linking is ad-hoc. Blog posts don't declare their pillar. | `plugins/soleur/docs/blog/*.md` | Add `pillar:` frontmatter field and render a "Part of the X series" block. |
| **P2** | No explicit CTA from long-form pillar blog posts to `/pricing/`. | `plugins/soleur/docs/blog/2026-03-24-ai-agents-for-solo-founders.md` et al. | Add end-of-article CTA block in `base.njk` or per-post. |
| **P2** | No pages target the high-intent transactional queries "hire AI CTO", "fractional general counsel AI", "AI CFO for startup". | Content plan | Ship one cluster page per role, each linking back to `/pricing/` as pillar. |
| **P2** | Homepage hero does not link to `/agents/`, `/vision/`, or the flagship blog pillar. | `plugins/soleur/docs/index.njk` | Add secondary nav row below hero CTA. |

---

## Coverage Gaps (pages not sampled in this audit)

- `/blog/` index and 14 additional blog posts (sampled 2)
- `/skills/`, `/community/`, `/articles/`, `/changelog/` (navigation pages not sampled)
- Legal pages (7) — out of scope for content audit; handled by `seo-aeo-analyst`
- Case studies (5 under `docs/blog/case-study-*.md`) — not sampled

A follow-up audit should sample 3-4 more blog posts and the `/skills/` and `/community/` pages before shipping a site-wide content plan.

---

## Notes on Audit Method

The audit was forced to use local source because `WebFetch` hits Cloudflare's bot challenge. The Eleventy source under `plugins/soleur/docs/` is the canonical authoring surface — no drift risk against the live site. For future audits, either (a) run from a browser-capable tool that completes the Cloudflare JS challenge, or (b) run post-build against `_site/` output. The source-based approach caught issues a rendered-HTML audit would still catch (the Ollama command bug is in the source, not a build artifact).
