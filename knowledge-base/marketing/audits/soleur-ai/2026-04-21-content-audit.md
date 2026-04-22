---
date: 2026-04-21
owner: CMO / growth
scope: Content-level keyword alignment, search intent match, readability
site: https://soleur.ai
source: plugins/soleur/docs (Eleventy) — live site WebFetch returned 403 (Cloudflare bot challenge); audit performed against the committed source, which is the production build.
brand_guide: knowledge-base/marketing/brand-guide.md (read, applied)
---

# Soleur.ai Content Audit — 2026-04-21

## Executive Summary

Soleur.ai has strong foundational content: clear positioning ("Company-as-a-Service"), on-brand voice (Vercel-adjacent, declarative), and extensive FAQ coverage. Keyword coverage is good for **brand-defining terms** ("company-as-a-service", "AI agents for solo founders", "Claude Code plugin") but weaker for **high-intent commercial queries** that prospects actually search ("AI business tools for solopreneurs", "AI virtual assistant alternatives", "run a startup alone with AI").

Five patterns recur across pages:

1. **Brand-first, problem-second framing** — hero H1s lead with action ("Stop hiring. Start delegating.") but skip the target-audience keyword in the H1 itself. Solo-founder keyword density is lower than it should be for a brand whose primary ICP keyword is "solo founder".
2. **Category keyword ("Company-as-a-Service") is invented terminology** — great for brand moat, weak for search discovery because nobody searches for it. Every pillar page uses it; no page bridges it to the queries users actually type.
3. **Hero taglines repeat across pages** — the `/vision/` and `/` pages duplicate "billion-dollar" framing; `/about/` and `/` share "Company-as-a-Service platform" wording verbatim. Search engines deduplicate; consider differentiating.
4. **Readability is good for technical register, weak for non-technical founder register.** Brand guide §Voice requires two registers. The homepage leans technical ("compounding knowledge base", "agentic engineering"); the non-technical register only surfaces in scattered FAQ answers.
5. **Meta descriptions are inconsistent in keyword priority.** Homepage `<title>` is "Soleur — One Command Center, 8 Departments" (from Next.js dashboard route) but the Eleventy `index.njk` SEO title is "Soleur — AI Agents for Solo Founders | Every Department, One Platform" — there is a title mismatch between the marketing surface and the authenticated app.

**Top three fixes (estimated impact vs. cost):**

| Priority | Fix | Pages | Est. effort |
|----------|-----|-------|-------------|
| P0 | Add "solo founder" and "AI agents for solo founders" keyword presence in H1/H2 of `/`, `/pricing/`, `/agents/` | 3 pages | 30 min |
| P0 | Rewrite `/getting-started/` hero to include transactional intent keywords ("install", "get started", "try Soleur") — currently reads like a value-prop page | 1 page | 20 min |
| P1 | Add a "What is a solo founder AI platform?" definition paragraph to `/vision/` or a new pillar — bridges invented "Company-as-a-Service" category to searched queries | 1 page | 40 min |

## Pages Audited

Full sample of the committed Eleventy source (`plugins/soleur/docs/`). Live site was behind Cloudflare challenge (WebFetch 403), so audit is against source truth.

| # | Path | Type | Role |
|---|------|------|------|
| 1 | `/` (`index.njk`) | Landing | Primary conversion page |
| 2 | `/pricing/` (`pricing.njk`) | Commercial | Primary monetization page |
| 3 | `/about/` (`about.njk`) | Informational | Founder E-E-A-T |
| 4 | `/vision/` (`vision.njk`) | Informational | Positioning / pillar |
| 5 | `/getting-started/` (`getting-started.njk`) | Transactional | Install / activation |
| 6 | `/agents/` (`agents.njk`) | Informational | Catalog / pillar |
| 7 | `/skills/` (`skills.njk`) | Informational | Catalog |
| 8 | `/community/` (`community.njk`) | Informational | Community proof |
| 9 | `/blog/` (`blog.njk`) | Index | Content hub |

---

## Per-Page Analysis

### 1. `/` (Homepage)

| Field | Value |
|-------|-------|
| `<title>` (SEO) | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" |
| Meta description | "Stop hiring, start delegating. Soleur deploys 60+ AI agents across 8 business departments — engineering, marketing, legal, finance, operations, product, sales, and support. Human-in-the-loop. Your expertise, amplified." |
| H1 | "Stop hiring. Start delegating." |
| H2s | "The AI that already knows your business.", "8 departments. One knowledge base. Your expertise, amplified.", "Frequently Asked Questions", "Stop hiring. Start delegating." (final CTA) |
| Detected target keywords | `solo founder`, `AI agents`, `company-as-a-service`, `stop hiring start delegating` (brand phrase), `compounding knowledge base` |
| Keyword alignment | **Partial.** Meta description is strong. H1 does NOT contain "solo founder" or "AI agents" — relies entirely on brand-voice slogan. Search engines cannot infer ICP from the H1 alone. |
| Search intent match | **Mixed.** Home serves informational + commercial intent. Hero copy is pure brand/emotional; first body paragraph correctly hits informational keywords. Transactional CTA ("Join the Waitlist") present. |
| Readability | Reads well in technical register. Non-technical register underserved — FAQ #1 uses "compounding knowledge base" without defining it. |
| Brand voice match | Strong. "Stop hiring. Start delegating." is in brand guide §Example Phrases. Declarative, no hedging. |

**Critical issues:**

- H1 lacks any target keyword. "Stop hiring. Start delegating." will not rank for anything a prospect searches. Add an H1 subhead that mentions "AI agents for solo founders" OR add semantic H2 immediately after hero.
- Hero subheading uses "Company-as-a-Service platform" — an invented category. Add a synonym accessible to searchers: "AI agent platform for solo founders" or "AI business team platform".
- "Compounding knowledge base" appears 3 times in hero+problem section without inline definition. Brand guide §Audience Voice Profiles requires inline definition for non-technical readers.

**Improvement issues:**

- "Agents Execute" card description renders `{{ agents.departmentList | lower }}` which will produce a flat lowercase list — likely reads clumsily inline. Verify rendered output reads naturally.
- FAQ "Is Soleur free?" buries the open-source answer behind "The cloud platform (coming soon) provides..." — move "The self-hosted version is open source and free." to sentence 1 for the people actually searching "is Soleur free".

**Rewrite suggestions:**

| Element | Current | Suggested | Rationale |
|---------|---------|-----------|-----------|
| H1 | "Stop hiring. Start delegating." | Keep H1 as-is (brand-voice load-bearing). Add immediately below: `<p class="hero-eyebrow">AI agents for solo founders — every department, one platform</p>` | Preserves brand voice; injects target keyword cluster into first visible heading context. |
| Hero subheading | "The Company-as-a-Service platform for solo founders." | "The AI agent platform for solo founders. Company-as-a-Service for the billion-dollar solo company." | Leads with searched term ("AI agent platform"), keeps brand category as follow-up. |
| Problem section H2 | "The AI that already knows your business." | Keep. Add lead sentence: "Soleur is an AI business platform that remembers every decision you make." | Adds a plain-language definition sentence for non-technical register + GEO extractability. |
| FAQ "Is Soleur free?" | "Soleur offers two paths. The cloud platform (coming soon) provides managed infrastructure..." | "Yes — the self-hosted version of Soleur is free and open source under Apache 2.0. A managed cloud platform with a web dashboard and priority support is in development; pricing starts at the Spark tier." | Answers the searched question in the first word. AEO-optimal. |

---

### 2. `/pricing/`

| Field | Value |
|-------|-------|
| `<title>` | "Pricing" |
| Meta description | "All 8 departments -- engineering, marketing, legal, finance, sales, operations, product, and support -- from $49/month. Less than a single contractor." |
| H1 | "Every department.<br>One price." |
| H2s | "The team you need. Without the headcount.", (plus tier section H2s) |
| Detected target keywords | `AI pricing`, `solo founder pricing`, (weak: `Soleur pricing`) |
| Keyword alignment | **Weak.** `<title>` is literally just "Pricing" — zero brand or category anchor. Meta description is strong but title tag will lose SERP CTR. |
| Search intent | Commercial/transactional match. Hiring comparison table is excellent for "AI vs hiring cost" queries. |
| Readability | Strong. Table comparisons are scannable. |
| Brand voice | On-brand — declarative, no hedging. |

**Critical issues:**

- `<title>` is "Pricing" (Eleventy default from frontmatter `title`) — not "Soleur Pricing — AI Organization for $49/mo" or similar. SERP will show the page as just "Pricing" which hurts CTR.
- H1 "Every department. One price." is brand-voice perfect but contains no keyword. Prospect searching "Soleur pricing" or "AI agent pricing" won't see a keyword match in the H1.
- No FAQ on pricing page. "How much does Soleur cost?", "Is there a free tier?", "What's included in Spark?" should be structured FAQs — pricing is the #2 search-intent page and deserves AEO treatment equal to the homepage.

**Improvement issues:**

- "Typical Cost" column aggregates to ~$80K/mo implied team cost; this is a great statistic for AEO but the page never states the aggregate claim in plain prose. AI models quote numbers from sentences, not table cells.

**Rewrite suggestions:**

| Element | Current | Suggested | Rationale |
|---------|---------|-----------|-----------|
| Frontmatter `title` | `Pricing` | `Soleur Pricing — A Full AI Organization From $49/mo` | Adds brand, category anchor, and price anchor to `<title>`. |
| Hero H1 subhead | "A full AI organization..." | Prepend: "Soleur pricing: every department, one price." | Injects "Soleur pricing" exact-match keyword into first visible paragraph. |
| New paragraph before comparison table | — | "A full executive team costs about $80,000 per month. Soleur delivers the same eight functions — CTO, Marketing Director, General Counsel, CFO, Sales Director, Operations Manager, Product Lead, and Head of Support — starting at $49 per month." | Standalone quotable claim with concrete numbers. Prime GEO/AEO extraction target. |
| New FAQ section | — | Add 5 FAQ items: "How much does Soleur cost?", "Is there a free tier?", "What is the Spark tier?", "Can I self-host Soleur for free?", "Does Soleur charge for Claude API usage?" with schema.org FAQPage JSON-LD. | Pricing page has zero FAQ structure; every other primary page has one. |

---

### 3. `/about/`

| Field | Value |
|-------|-------|
| `<title>` | "About Jean Deruelle" |
| Meta description | "Jean Deruelle is the founder of Soleur, a Company-as-a-Service platform giving solo founders the operational capacity of a full organization through AI agents." |
| H1 | "About" |
| H2s | "Jean Deruelle", "About Soleur", "Frequently Asked Questions" |
| Detected target keywords | `Jean Deruelle`, `Soleur founder`, `Company-as-a-Service` |
| Keyword alignment | **Strong for founder-search, weak for category-search.** Good for "who founded Soleur" queries. |
| Search intent | Informational. Well-matched. |
| Readability | Strong. First paragraph is a complete self-contained definition — excellent for AEO. |
| Brand voice | On-brand but slightly corporate in places ("distributed systems and developer tools" — technical register OK here). |

**Critical issues:**

- H1 is bare "About" — not "About Jean Deruelle, Soleur Founder". Missing primary keyword in the highest-weight element.
- Two opening paragraphs about Jean are both ~80-word blocks; first paragraph should be shorter (1-2 sentences) to improve AEO quotability.

**Improvement issues:**

- JetBrains Mono/Go/TypeScript/Ruby stack list reads as technical-register content on a page that should be accessible to non-technical founders (VCs, journalists, potential customers reading "who runs this company"). Consider two-tier: 1-sentence accessible summary, then detail paragraph.
- Missing FAQ: "Is Jean Deruelle on LinkedIn?", "How to contact Soleur?"

**Rewrite suggestions:**

| Element | Current | Suggested | Rationale |
|---------|---------|-----------|-----------|
| H1 | "About" | "About Jean Deruelle, Soleur Founder" | Adds exact-match person + brand + role keywords. |
| Hero sub | "The founder behind Soleur." | "Jean Deruelle, Founder and CEO of Soleur — the AI agent platform for solo founders." | Inject category keyword + role + brand in one sentence. |
| Opening paragraph | (2-clause, ~50 words) | Split into: (1) one-sentence identity ("Jean Deruelle is the founder and CEO of Soleur, an AI agent platform that lets one founder run an eight-department company."); (2) origin story paragraph. | Sentence 1 becomes AEO-quotable standalone answer. |

---

### 4. `/vision/`

| Field | Value |
|-------|-------|
| `<title>` | "Soleur Vision: Company-as-a-Service" |
| Meta description | "The Soleur vision: company-as-a-service for solo founders. AI agents across every department giving one person the operational capacity of a full organization." |
| H1 | "The Soleur Vision: Company-as-a-Service for the Solo Founder" |
| H2s | "The Company-as-a-Service Platform", "Core Value Proposition", "Model-Agnostic Architecture", "Strategic Architecture" |
| Detected target keywords | `company-as-a-service`, `billion-dollar solopreneur`, `AI agent swarm` |
| Keyword alignment | **Strong for invented category; weak for external search.** |
| Search intent | Informational, thought-leadership. Likely target for referral traffic (HN, press) not organic search. |
| Readability | **Mixed.** Paragraphs are long (4-6 sentences) and use jargon ("model-agnostic orchestration engine", "CEO of a swarm", "Decision Ledger") without definitions. Technical register pushed beyond the brand guide's guidance. |
| Brand voice | On-brand tone (bold, ambitious) but drifts into jargon the brand guide flags. |

**Critical issues:**

- First body paragraph is 107 words and contains three capitalized invented terms ("Judgment", "Taste", "Swarm of Agents") without definition. AEO models will not extract quotable facts from this structure.
- "world's first model-agnostic orchestration engine" — unsourced superlative. Brand guide §HN says "HN readers detect and punish marketing language instantly." This page would lose HN credibility and also fails GEO source-citation guidance.
- "Bring Your Own Intelligence" section claims "Plug in your own API keys (Anthropic, OpenAI, Gemini, Llama, and more)." Verify this is accurate — Soleur is built on Claude Code, which may not support OpenAI/Gemini API keys today. If aspirational, label as roadmap.

**Improvement issues:**

- No statistics on this page. `/vision/` is the pillar for "what is company-as-a-service" and should cite concrete numbers (63 agents, 62 skills, 8 departments, 420+ merged PRs from the brand guide) inline in prose, not only via the stats strip.
- No FAQ on this page. Competing vision/manifesto pages (e.g., Vercel's product pages) have FAQs.

**Rewrite suggestions:**

| Element | Current | Suggested | Rationale |
|---------|---------|-----------|-----------|
| First body paragraph | "Soleur is a Company-as-a-Service platform designed to collapse the friction..." | Lead with a one-sentence definition: "Company-as-a-Service is the delegation of every business function — engineering, marketing, legal, finance, operations, product, sales, and support — to a coordinated team of AI agents that share a compounding knowledge base." Then continue with the thesis. | Creates an extractable definition sentence; the existing page has none. |
| "world's first" | "the world's first model-agnostic orchestration engine" | Remove "world's first" (unsourceable) or replace with a verifiable claim: "Soleur is an open-source, model-agnostic orchestration platform" | GEO authority signal: cite or cut. |
| "Bring Your Own Intelligence" | "Plug in your own API keys (Anthropic, OpenAI, Gemini, Llama, and more)." | If not currently supported, label: "Roadmap: plug in your own API keys..." | Accuracy / trust. |

---

### 5. `/getting-started/`

| Field | Value |
|-------|-------|
| `<title>` | "Getting Started with Soleur" |
| Meta description | "The AI that already knows your business. Soleur remembers every decision and customer so your team stops re-explaining context. Reserve access." |
| H1 | "The AI that already knows your business." |
| H2s | "Run it yourself", "The Workflow", "Commands" |
| Detected target keywords | `getting started Soleur`, `install Soleur`, `Claude Code plugin` |
| Keyword alignment | **Weak for install-intent.** H1 is a re-used brand slogan from the homepage, not a transactional-intent heading. |
| Search intent | **Mismatched.** Page is titled "Getting Started" (transactional/navigational) but H1 and hero copy duplicate the homepage's informational framing. Users searching "install Soleur" or "how to use Soleur" land on a re-stated value prop instead of instructions. |
| Readability | Good in the "Run it yourself" section — code block is prominent, quickstart is well-structured. |
| Brand voice | On-brand. |

**Critical issues:**

- **H1 duplicates the homepage.** "The AI that already knows your business." is already the H2 on `/` and the description here. Two pages competing on the same phrase cannibalizes search signals. The getting-started page should own a transactional H1.
- Meta description reads like a pricing-page CTA ("Reserve access.") rather than "how to install" guidance. Search intent mismatch.
- The `<title>` "Getting Started with Soleur" is fine; keep — but H1 should mirror the title's transactional intent.

**Improvement issues:**

- Quickstart code block is well-annotated (`<!-- verified: 2026-04-19 -->` comment) — good practice.
- Workflow steps (brainstorm → plan → work → review → compound) listed but not linked to their individual skill pages. Internal linking gap; these should link into cluster content.

**Rewrite suggestions:**

| Element | Current | Suggested | Rationale |
|---------|---------|-----------|-----------|
| H1 | "The AI that already knows your business." | "Get started with Soleur in two commands" | Transactional-intent match; includes brand keyword; concrete payoff. |
| Hero sub | "Soleur remembers every decision, customer, and context..." | "Install Soleur in Claude Code and run your first AI agent in 30 seconds. Join the managed platform waitlist or run the open-source version today." | Mentions install step + both paths (waitlist + OSS) up front. |
| Meta description | "The AI that already knows your business. ... Reserve access." | "Install Soleur in two commands. Run the open-source Claude Code plugin locally, or join the waitlist for the managed platform. Get started with 60+ AI agents across 8 departments." | Transactional intent, mentions both paths, includes keyword cluster. |

---

### 6. `/agents/`

| Field | Value |
|-------|-------|
| `<title>` | "Soleur AI Agents" |
| Meta description | "AI agents for every business department — engineering, marketing, legal, finance, operations, product, sales, and support. The full Soleur agent roster." |
| H1 | "Soleur AI Agents" |
| Detected target keywords | `Soleur AI agents`, `AI agents for business`, `agentic engineering` |
| Keyword alignment | **Strong.** H1 is exact-match of the brand's primary keyword cluster. |
| Search intent | Informational. Catalog-style match. |
| Readability | Intro paragraph is dense (4 linked terms, 60+ words). Cards are scannable. |
| Brand voice | On-brand, technical register (appropriate for this page's audience). |

**Critical issues:**

- First intro paragraph opens with a Twitter/X link to Karpathy. Relying on a third-party link as the *opening* to a pillar page is a GEO risk — AI models may fail to follow the link and miss the definition of "agentic engineering". Provide an inline definition first.

**Improvement issues:**

- Intro mentions "60+ open source AI agents" but the brand guide's preferred framing ("63 agents, 62 skills") uses precise numbers. Use the template variable.
- Links to `/blog/` or individual agent docs would reinforce the cluster-to-pillar structure.

**Rewrite suggestions:**

| Element | Current | Suggested | Rationale |
|---------|---------|-----------|-----------|
| Intro paragraph lead | `<a href="https://x.com/karpathy/...">Agentic engineering</a> treats AI agents as specialist team members...` | "Agentic engineering is a development approach where AI agents act as specialist team members, not generic assistants. <a href=\"https://x.com/karpathy/...\">Andrej Karpathy</a> coined the term in..." | Inline definition before the link. GEO + AEO win. |

---

### 7. `/skills/`

| Field | Value |
|-------|-------|
| `<title>` | "Soleur Skills" |
| Meta description | "Multi-step workflow skills for the Soleur platform — from feature development and code review to content writing, deployment, and agentic engineering." |
| H1 | "Agentic Engineering Skills" |
| Detected target keywords | `agentic engineering`, `AI workflow automation`, `Claude Code skills` |
| Keyword alignment | H1 is "Agentic Engineering Skills" — niche keyword; strong for the target audience but low-volume. Consider dual-phrasing. |
| Search intent | Informational. |
| Readability | Same intro density issue as `/agents/` — opens with two external links. |
| Brand voice | On-brand, technical register. |

**Critical issues:**

- H1 says "Agentic Engineering Skills" but `<title>` says "Soleur Skills". Mismatch. Prefer `<title>`: "Soleur Skills — Agentic Engineering Workflows for Solo Founders" to unify both keywords.

**Improvement issues:**

- Opening paragraph mentions "compound engineering lifecycle" linking to Every.to — cite, but also define inline in one sentence.

---

### 8. `/community/`

| Field | Value |
|-------|-------|
| `<title>` | "Community" |
| Meta description | "Join the Soleur community. Connect on Discord, contribute on GitHub, get help, and learn about our community guidelines." |
| H1 | "Community" |
| Detected target keywords | `Soleur community`, `Soleur Discord`, `Soleur GitHub` |
| Keyword alignment | Weak. `<title>` and H1 both bare "Community". |
| Search intent | Navigational. Match OK (users searching "Soleur Discord" will find what they want via the page). |
| Readability | Strong. |
| Brand voice | On-brand. |

**Improvement issues:**

- Same pattern as `/pricing/` and `/about/`: `<title>` is a generic single word. Prefer "Soleur Community — Discord, GitHub, and Contributors" for SERP differentiation.

---

### 9. `/blog/`

| Field | Value |
|-------|-------|
| `<title>` | "Blog" |
| Meta description | "Insights on agentic engineering, company-as-a-service, and building at scale with AI teams." |
| H1 | "Blog" |
| Keyword alignment | Weak `<title>`; description is on-brand. |

**Improvement issues:**

- `<title>`: prefer "Soleur Blog — Agentic Engineering and Company-as-a-Service". Same pattern as `/community/` and `/pricing/`.
- Category nav pills ("What is Company-as-a-Service?", "Soleur vs. Competitors", "Case Studies", "Engineering Deep Dives") are excellent pillar-cluster scaffolding if the underlying posts exist.

---

## Cross-Page Patterns (Issues repeating across 2+ pages)

| Pattern | Affected pages | Severity |
|---------|---------------|----------|
| `<title>` tag is a bare single word ("Blog", "Pricing", "Community") lacking brand + category anchor | `/pricing/`, `/community/`, `/blog/` | Critical — hurts SERP CTR |
| H1 duplicates or re-uses brand-voice slogan without injecting the page's specific target keyword | `/`, `/getting-started/`, `/community/`, `/blog/` | Critical on `/getting-started/`; improvement elsewhere |
| Pillar pages open with a third-party link before defining the term being linked | `/agents/`, `/skills/` | Improvement |
| "Company-as-a-Service" used as the primary category label without a bridge definition accessible to searchers | `/`, `/vision/`, `/about/`, meta descriptions across all pages | Improvement — brand moat trade-off |
| "Compounding knowledge base" used without inline definition (non-technical register gap) | `/`, `/agents/`, `/vision/` | Improvement |
| Pricing page lacks FAQ structure despite being a primary conversion page | `/pricing/` | Critical for AEO |

---

## Prioritized Issue List

### Critical (blocks discoverability)

1. **Homepage `<title>` mismatch** — Eleventy `index.njk` uses `seoTitle: "Soleur — AI Agents for Solo Founders..."` but the Next.js `apps/web-platform/app/layout.tsx` uses `"Soleur — One Command Center, 8 Departments"`. If both render (depending on which is served at `/`), search engines see conflicting signals. **Action:** confirm which surface serves the public homepage and align the other.
2. `/getting-started/` H1 duplicates homepage H2 and does not serve transactional intent. **Action:** rewrite to "Get started with Soleur in two commands" and shift meta description to install-intent copy.
3. `/pricing/` `<title>` is bare "Pricing". **Action:** change to "Soleur Pricing — A Full AI Organization From $49/mo".
4. `/pricing/` has no FAQ section or FAQPage schema. **Action:** add 5-7 FAQ items with JSON-LD.
5. Homepage H1 contains no target keyword. **Action:** add hero-eyebrow `<p>` above or H2 subhead immediately below with "AI agents for solo founders" cluster.
6. `/vision/` uses unsourceable superlative ("world's first model-agnostic orchestration engine"). **Action:** source or remove.

### Improvement (enhances ranking)

1. `/community/`, `/blog/` `<title>` tags lack brand/category anchor.
2. `/about/` H1 is bare "About" — should be "About Jean Deruelle, Soleur Founder".
3. `/agents/` and `/skills/` open with external Twitter/X links before defining the term. Add inline definition first.
4. "Compounding knowledge base" should get an inline definition on first usage per page (homepage, agents, vision).
5. `/vision/` "Bring Your Own Intelligence" claim needs verification; label as roadmap if aspirational.
6. `/pricing/` should state the aggregate team-cost number in prose ("~$80,000/month for the equivalent eight-role executive team") as a quotable GEO target.

---

## Keyword Coverage Matrix

Keywords are assessed against the brand-guide ICP ("solo founders", "technical builders", "non-technical founders").

| Keyword cluster | Intent | Current coverage | Gap | Priority |
|----------------|--------|-----------------|-----|----------|
| "company-as-a-service" | Informational | Strong — 4+ pages | Missing bridge to searched synonyms | P2 |
| "AI agents for solo founders" | Commercial | Moderate — agents page H1, meta descriptions | H1 on homepage missing; pricing H1 missing | P0 |
| "solo founder AI platform" / "AI business tools for solopreneurs" | Commercial | Weak — only in prose | No page explicitly targets these queries | P1 |
| "AI agent pricing" / "AI team cost" | Commercial | Strong in pricing table; weak in title/H1 | Title tag, no FAQ | P0 |
| "install Soleur" / "Soleur tutorial" / "how to use Soleur" | Transactional | Weak — `/getting-started/` doesn't target them | Rewrite `/getting-started/` hero | P0 |
| "Claude Code plugin" | Commercial/navigational | Strong — multiple pages | — | — |
| "billion-dollar solo founder" / "one-person unicorn" | Informational (thought-leadership) | Strong — homepage quote, vision | — | — |
| "AI virtual assistant alternatives" | Commercial | **Missing** | No comparison content targeting this frame | P2 |
| "run a startup alone with AI" | Informational | **Missing** | Candidate for blog pillar | P2 |
| "Jean Deruelle" | Navigational | Strong | — | — |

---

## GEO/AEO Content-Level Recommendations

(Structural AEO recommendations only; SEO/JSON-LD validity audit belongs to seo-aeo-analyst agent.)

1. **Add definition sentences** to `/vision/`, `/agents/`, `/skills/` — each should have a standalone, quotable definition sentence for the key term near first usage. Currently `/vision/` opens with thesis prose; no extractable definition of "company-as-a-service".
2. **Add aggregate statistics in prose.** Pricing table has the numbers; prose doesn't surface them. Add: "Replacing the full eight-role executive team costs approximately $80,000 per month. Soleur delivers all eight roles starting at $49 per month."
3. **Verify the "world's first" claim or remove.** Unsourced superlatives reduce AI citation probability — AI models are trained to down-weight uncited strong claims.
4. **Pricing page FAQ is the #1 AEO gap.** Pricing is often the most-searched page; AI search engines heavily favor FAQ-structured answers to transactional questions.
5. **Inline-define technical terms on first use** per page — "compounding knowledge base", "agentic engineering", "Model Context Protocol (MCP)". Some pages do this; most do not.

---

## Suggested Next Actions

1. **P0 inline fixes (30-60 min total):** Rewrite `/getting-started/` hero + meta; add keyword eyebrow/sub on homepage; fix `/pricing/`, `/community/`, `/blog/` `<title>` tags; fix `/about/` H1.
2. **P0 structural (1-2 hr):** Add FAQ section with FAQPage JSON-LD to `/pricing/`.
3. **P1 content (2-3 hr):** Add an inline definition paragraph of "Company-as-a-Service" to `/vision/` and cross-link from `/`, `/agents/`, `/skills/`.
4. **P1 cluster (separate plan):** Commission blog pillar "What is a solo founder AI platform?" targeting the missing commercial keywords cluster. Hand off to the content-writer skill.
5. **Verify homepage surface:** confirm whether `soleur.ai/` serves the Eleventy `index.njk` or the Next.js `app/page.tsx` (which redirects to `/dashboard`). If both render, align `<title>` tags.

---

## Methodology Notes

- Live site WebFetch returned HTTP 403 (Cloudflare bot challenge). Playwright MCP was not permitted in this session. Audit performed against committed Eleventy source at `plugins/soleur/docs/pages/` which is the build-time source of truth for soleur.ai.
- Brand guide `knowledge-base/marketing/brand-guide.md` was read and applied. Voice assessments reference brand guide §Voice, §Audience Voice Profiles, §Do's and Don'ts, and §Channel Notes → Website.
- Keyword density analysis skipped — brand guide's audience voice section explicitly discourages keyword stuffing; the GEO framework in the growth skill flags keyword density as counterproductive for AI citation.
- Per growth skill scope: JSON-LD validity, sitemap, `llms.txt`, and meta-tag syntax audits belong to the seo-aeo-analyst agent and are not included here.
