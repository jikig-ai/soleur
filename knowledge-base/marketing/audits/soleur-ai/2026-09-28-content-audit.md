---
date: 2026-09-28
target: https://soleur.ai
type: content-audit
scope: soleur.ai (sampled: 9 nav pages + blog index + 5 most recent posts = 15 surfaces)
brand_guide: knowledge-base/marketing/brand-guide.md (last_updated 2026-09-25; Identity, Voice, Audience Voice Profiles, Channel Notes > Website, Channel Notes > Blog applied)
prior_audit: knowledge-base/marketing/audits/soleur-ai/2026-05-25-content-audit.md
auditor: growth agent
---

# Soleur.ai Content Audit, 2026-09-28

## Scope and Method

| Item | Detail |
|---|---|
| Pages sampled | `/`, `/getting-started/`, `/pricing/`, `/agents/`, `/skills/`, `/blog/`, `/community/`, `/about/`, `/vision/` (the full `site.json` nav set), plus 5 most recent posts: `beta-testers-went-quiet` (09-26), `parked-vs-forgotten-ideas` (09-25), `best-ai-tools-for-solo-founders-2026` (06-15), `loop-engineering-for-your-whole-company` (06-12), `claude-code-plugin-vs-skill-vs-mcp` (06-01) |
| Source of truth | **Local Eleventy source at `plugins/soleur/docs/` on `main` (HEAD `fff36b61`).** WebFetch and curl were both refused by this environment's cron-containment policy, so `https://soleur.ai` and `/sitemap.xml` could not be fetched. Findings describe what the source renders. They do not confirm that production is in sync with `main`. |
| Not audited | Pillar pages (`/company-as-a-service/`, `/agentic-engineering/`, `/ai-agents-for-solo-founders/`, `/ai-cmo/`, `/ai-cto/`, `/solo-founder-ai-stack/`, `/claude-code-plugins/`), compare pages, `/glossary/` (skimmed only), `/changelog/`, legal pages, and 26 older blog posts |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, llms.txt. These belong to `soleur:marketing:seo-aeo-analyst`. Wherever this report mentions schema, it is about content parity only. |

**Brand-guide change since the prior audit.** On 2026-09-25 (#8774) the brand guide changed the blog's reader: posts are now written for non-technical founders, and search terms should be the words a founder types, not developer queries. Several fixes from the prior audit were built for the old technical-reader blog. This audit re-scores them against the new rule.

**Priority scale.** P0 = critical (blocks discoverability or publishes a false claim at scale), P1 = high, P2 = medium, P3 = low. **No P0 issues were found in this pass.**

---

## Prior-Audit Trend (2026-05-25 → 2026-09-28)

| Prior ID | Prior issue | Status | Evidence |
|---|---|---|---|
| C1 | `/getting-started/` title brand-only | **Resolved** | `seoTitle` is now "Get Started with Soleur — Install Your AI Organization in Two Commands" (the prior R1 text, word for word) |
| C2 | `/skills/` title brand-only + technical H1 | **Open** | `title: Soleur Skills` with no `seoTitle`, so the rendered `<title>` is "Soleur Skills". H1 is still "Agentic Engineering Skills" |
| C3 | `/blog/` title brand-only | **Resolved, then superseded** | The prior R5 title and meta were applied. The 2026-09-25 blog-reader change now makes them off-brand, so this is reopened as **CA-01** |
| C4 | No meta descriptions | **Resolved / false positive** | Every sampled page has `description:` frontmatter, and `base.njk` renders it as `<meta name="description">`. The prior finding came from the page fetcher, which dropped the `<head>` |
| C5 | "Agentic engineering" undefined | **Resolved** | `/skills/` opens with a definition sentence and a Karpathy citation |
| I1 | Homepage hero leads with CaaS jargon | **Partially resolved** | The memory-first line was merged into the tagline, but the hero still opens with "The Company-as-a-Service platform…". The pain-point pitch ("8 jobs… 7 of them") is not used. See **CA-06** |
| I2 | `/community/` title generic | **Open** | `seoTitle: "Community — Soleur"`. See **CA-20**. The prior R6 rewrite said "open-source", which is inaccurate: the license is BSL 1.1 |
| I3 | `/agents/` hard-coded "67" | **Resolved** | Title and H1 now use `{{ stats.agents }}` via `eleventyComputed` |
| I4 | `/about/` E-E-A-T not in title | **Partially resolved** | H1 improved to "About Soleur and its founder, Jean Deruelle", and `site.author.bio` carries "15+ years". The `<title>` is still "About Jean Deruelle - Soleur". See **CA-21** |
| I5 | `/vision/` jargon, no glossary | **Partially resolved** | `/glossary/` now exists and defines CaaS, agentic engineering, MCP, skill and more. `/vision/`, `/skills/` and `/agents/` do not link to it. See **CA-22** |
| I6 | Pricing $95K unsourced | **Resolved** | A footnote and two FAQ entries cite Robert Half 2026, Payscale and Levels.fyi, with the per-role breakdown |
| I7 | Blog categories lack landing pages | **Partially resolved; new defect found** | Pillar series exist in `_data/pillars.js`, but the blog-index category filter is broken. See **CA-02** |

**Trend:** 5 of 12 prior issues fully resolved, 4 partial, 2 open. C3 was resolved and then reopened by the brand change. Title and meta work landed well. The remaining debt is **register drift**: technical language on general-register pages. The new debt is **content accuracy and taxonomy**.

---

## Per-Page Analysis

### 1. Homepage (`/`)

| Field | Assessment |
|---|---|
| `<title>` | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" |
| Meta description | "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, …" |
| H1 | "Stop hiring. Start delegating." |
| Target keywords | AI agents for solo founders, Company-as-a-Service, AI organization, Soleur vs Cursor/Copilot |
| Keyword alignment | **Strong title and H1.** The meta description opens with the category term "Company-as-a-Service" rather than the founder's problem. `site.json` already has a better, pain-point default description that the page overrides |
| Search intent | Commercial + navigational. **Matches.** The "Soleur vs. Cursor and GitHub Copilot" section captures comparison intent well |
| Readability | Punchy and on-voice. Problems: the tagline and hero-sub both lead with "Company-as-a-Service platform" (the brand guide says CaaS "requires market education… not suitable for headlines"). The label "This Is the Way" is a pop-culture meme. "not just engineering" uses a banned word. The FAQ exposes the `/soleur:go` command. Emoji icons appear in visible cards. "9 hats… hand off 8" conflicts with the brand's "8 jobs… 7 of them" |
| Trust | **"As seen in: Inc.com" press strip.** The linked Inc.com article is about Dario Amodei's prediction. Nothing in the source shows that it mentions Soleur, yet "As seen in" implies Soleur was covered (**CA-05**) |

### 2. Getting Started (`/getting-started/`)

| Field | Assessment |
|---|---|
| `<title>` / meta | Fixed per prior R1/R2. **Strong** |
| H1 | "The AI that already knows your business." (memory-first variant) |
| Target keywords | get started with Soleur, install AI organization, self-hosted AI agents |
| Search intent | Transactional (waitlist) + informational (self-host). **Partial.** The primary CTA is correctly the waitlist, but most of the page body is CLI reference: a Claude Code vs Grok Build command table, a 120-word "Updating later?" callout covering `marketplace update`, `uninstall && install` and `Plugin not found`, and seven `/soleur:go …` example rows |
| Readability | Split audience. The hero speaks to non-technical founders, then the body turns into terminal docs. "The Workflow… for software development" frames the whole product as engineering-only on the page every new visitor reaches |
| Accuracy | The FAQ answer "What do I need to run Soleur? **Nothing to install.**" is true only for the hosted version, which is waitlist-only today. Answer engines will quote that first sentence on its own (**CA-09**). "Founding cohort of 10 teams" conflicts with the solo-founder audience |

### 3. Pricing (`/pricing/`)

| Field | Assessment |
|---|---|
| `<title>` / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." **Strong** |
| Target keywords | AI agent pricing, cost of hiring vs AI, solo founder software cost |
| Search intent | Transactional. **Matches.** Tiers, prices and a waitlist are above the fold |
| Readability | Strong. The $95K table is now sourced (prior I6 resolved) |
| Issues | Several lines claim more autonomy than the trust scaffolding on the same site: "Your public presence **on autopilot**", and "[a DPA] lands in their inbox — formatted, footnoted, and **ready to sign**" (the legal output goes out with no founder review step). "Soleur handles **the other 70%** of running a company" is unsourced. The hero lists "strategy" where the meta says "engineering". The closing proof point "420+ PRs across all 8 domains" is an engineering metric on a general-register page, and far below the repo's current PR count |

### 4. Agents (`/agents/`)

| Field | Assessment |
|---|---|
| `<title>` / H1 | Templated from `stats.agents`. **Strong** (prior I3 resolved) |
| Target keywords | AI agents for solo founders, marketing/legal/finance AI agents |
| Search intent | Informational. **Matches.** The hero opens with a plain-language definition of an AI agent, which is good for extraction |
| Accuracy / voice | "Each Soleur agent is **trained** for a specific business function." The agents are instruction-defined, not trained models, so this is inaccurate. The FAQ says "execute business tasks **within Claude Code**", which ties the product to one surface and conflicts with the delivery-agnostic positioning note. The FAQ also says "the **most comprehensive set of solo founder AI tools**", an unverifiable superlative that uses the discouraged word "tools" |

### 5. Skills (`/skills/`)

| Field | Assessment |
|---|---|
| `<title>` | "Soleur Skills". **Weak** (carried over from C2) |
| Meta | "Multi-step workflow skills … from feature development and code review to content writing, deployment, and agentic engineering." Engineering-first |
| H1 | "Agentic Engineering Skills" |
| Keyword alignment | **Weak.** A founder searching "AI workflows for my business" or "AI automation templates" has nothing to match |
| Search intent | Informational. **Partial.** The catalog is complete, but there is no outcome layer |
| Readability | The definition paragraph is now present (C5 resolved). The FAQ answer "What is a Soleur skill?" ignores the brand glossary definition ("workflows your AI team follows to get things done"). The lifecycle here is **5 stages**, while `/getting-started/` and `/` both show **6** (**CA-10**) |

### 6. Blog Index (`/blog/`)

| Field | Assessment |
|---|---|
| `<title>` | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" |
| Meta | "Field notes on building a billion-dollar company alone — Company-as-a-Service strategy, agentic engineering case studies, and engineering deep dives from Soleur." |
| H1 | "Blog" |
| Keyword alignment | **Misaligned with the current brand guide.** The Blog channel note tells writers to target the words a founder types, not "agentic engineering". It also says to use the general thesis, not the "billion-dollar… engineering problem" thesis. Title, meta, visible intro and the "Engineering Deep Dives" category all target the old technical reader (**CA-01**) |
| Taxonomy | **Broken filter.** The "What is Company-as-a-Service?" section filters on the tag `"CaaS"`, but no post carries it; posts use `company-as-a-service`. As a result the section shows only posts tagged `ai-agents`. The actual CaaS explainer (`company-as-a-service-platform`), `how-to-run-every-department-with-ai-agents`, `one-person-billion-dollar-company` and the new founder post `beta-testers-went-quiet` all fall into **"Engineering Deep Dives"** (**CA-02**) |

### 7. Community (`/community/`)

| Field | Assessment |
|---|---|
| `<title>` / H1 | "Community — Soleur" / "Community". **Weak** (carried over from I2) |
| Search intent | Navigational. Matches branded queries only |
| Readability | Strong. The honest summary ("small by design while the project is young, and we would rather say so than overstate it") is a good trust signal. "compound-engineering workflow" is used without definition |

### 8. About (`/about/`)

| Field | Assessment |
|---|---|
| `<title>` / H1 | "About Jean Deruelle - Soleur" / "About Soleur and its founder, Jean Deruelle" |
| Keyword alignment | Adequate for branded and founder-name queries. The "15+ years distributed systems" credential is in the body and author schema, but not in the title or meta (**CA-21**) |
| Readability | Strong, factual, first-person-adjacent. "Jean writes about **agentic engineering**… on the Soleur blog" no longer describes what the blog is for |

### 9. Vision (`/vision/`)

| Field | Assessment |
|---|---|
| `<title>` / H1 | "Soleur Vision: Company-as-a-Service" / "The Soleur Vision: Company-as-a-Service for the Solo Founder". **Strong** for the brand's own category term |
| Search intent | Informational (what is CaaS). **Matches** |
| Accuracy | **The roadmap is stated as shipped capability.** "Plug in your own API keys (Anthropic, OpenAI, Gemini, Llama, and more)" and "Soleur selects the best model for each task. Claude for coding. **GPT-4o** for strategy." are in the present tense. The same page's FAQ says "The current implementation runs on Claude Code", and `/pricing/` says "All plans require a Claude subscription or API key" (**CA-04**). "Revenue Philosophy: Founders only pay their model providers" contradicts the $49–$499 tiers (**CA-15**) |
| Readability | The page has the most jargon on the site ("infinite leverage", "high-level curator", "recursive dogfooding"), which the brand guide accepts for deep content. The subhead "Where Soleur is headed." is thin. There is no link to `/glossary/` |

### 10–14. Recent Blog Posts

| Post | Register rule | Title / meta keyword fit | Intent | Findings |
|---|---|---|---|---|
| `beta-testers-went-quiet` (09-26) | **New rule applies** | seoTitle "How to Run a Beta Program That Actually Tells You Something" is founder-worded. The high-intent query "how to get feedback from beta testers" appears only in the FAQ schema | Informational. Matches | **No call to action**, although the Blog note requires "one next step". The FAQPage JSON-LD has 3 Q&As that are **not visible** on the page. `pillar: billion-dollar-solo-founder` renders a series box, but the post is not a member of that pillar. Filed under "Engineering Deep Dives". "just a waiting list" uses a banned word. Opening and outcome-first structure are exemplary |
| `parked-vs-forgotten-ideas` (09-25) | **New rule applies** | seoTitle "Parked vs. Forgotten Ideas: How Solo Founders Track Decisions". Strong; "idea parking lot" appears in the intro | Informational. Matches | **Model post for the new rule**: founder problem in the first two sentences, outcome before mechanism, cited external source (Matt Pocock), visible FAQ, CTA, technical link at the end. Only gaps: no `pillar:` (no cluster links), and it is filed under "What is Company-as-a-Service?" because of the `ai-agents` tag |
| `best-ai-tools-for-solo-founders-2026` (06-15) | Pre-rule; keeps register | Strong commercial keyword ("best AI tools for solo founders 2026"). seoTitle is about 110 characters (flag to seo-aeo-analyst) | Commercial. Matches | "genuinely **move the needle**" is banned startup jargon. The Carta claim ("roughly a third of new company formations") links to the generic `carta.com/data/` hub, not a specific report (**CA-17**) |
| `loop-engineering-for-your-whole-company` (06-12) | Pre-rule; keeps register | "loop engineering" is a timely, low-competition term | Informational. Matches | Well cited (Osmani essay, attributed secondary quotes). No action; technical register is allowed under the scope rule |
| `claude-code-plugin-vs-skill-vs-mcp` (06-01) | Pre-rule; keeps register | Pure developer query | Informational. Matches for developers | Strong definitional content with official-doc citations. Under the new rule a post like this would be written in the docs, not the blog; per the scope rule, do not move or rename it. Cross-link it from `/glossary/` |

---

## Issues Found

| ID | Priority | Title | Page(s) | Why it matters | Prior |
|---|---|---|---|---|---|
| CA-01 | **P1** | Blog index positioned for technical readers | `/blog/` | The title, meta, visible intro and category labels target "agentic engineering" and "engineering deep dives". The brand guide (2026-09-25) now says the blog is for non-technical founders, searching in founder words. The hub page contradicts the posts it lists | Reopens C3 |
| CA-02 | **P1** | Blog category filter misfiles posts | `/blog/` | The CaaS section filters on the `CaaS` tag, which no post uses. The CaaS explainer and the "run every department" playbook sit under "Engineering Deep Dives", and the section named "What is Company-as-a-Service?" contains none of the CaaS explainers. This breaks the hub-to-pillar path for the brand's core term | New (extends I7) |
| CA-03 | **P1** | Skills page title is brand-only | `/skills/` | "Soleur Skills" cannot rank for any non-branded query. It is a nav page and the second product page | C2 |
| CA-04 | **P1** | Vision states roadmap as shipped capability | `/vision/` | Present-tense claims of multi-provider keys and automatic model routing (naming GPT-4o) contradict the page's own FAQ and `/pricing/`. Answer engines quote card text with no page context, so readers get a false capability statement | New |
| CA-05 | **P1** | Homepage "As seen in" implies press coverage | `/` | Labelling a third-party article about Anthropic's CEO as "As seen in" implies Soleur was covered. That is a trust claim that can be checked and found wrong | New |
| CA-06 | P2 | Homepage hero and meta lead with category jargon | `/` | The tagline, hero-sub and meta all open with "Company-as-a-Service". The brand's winning framing (pain point, 7 of 10 in testing) is absent above the fold | I1 |
| CA-07 | P2 | Homepage FAQ exposes a CLI command | `/` | `/soleur:go` in "How do I get started?" (visible and in schema) breaks the general register and the rule against CLI-first CTAs | New |
| CA-08 | P2 | Getting-started body is CLI reference | `/getting-started/` | The Grok Build table, update/uninstall callout and seven command rows bury the waitlist path. "Workflow… for software development" frames Soleur as engineering-only | New |
| CA-09 | P2 | Getting-started FAQ says "Nothing to install" | `/getting-started/` | The first sentence is only true for the waitlist-gated hosted version. It is the part most likely to be quoted on its own | New |
| CA-10 | P2 | Workflow lifecycle inconsistent across pages | `/`, `/getting-started/`, `/skills/` | `/` has Think→Plan→Build→Review→Ship→Compound, `/getting-started/` has brainstorm→plan→work→review→compound→ship, and `/skills/` has 5 stages ending at compound. The same entity is described three ways | New |
| CA-11 | P2 | Skills H1 and FAQ in technical register | `/skills/` | H1 "Agentic Engineering Skills". The FAQ definition ignores the brand glossary. Non-technical founders get no outcome framing | C2 (H1 half) |
| CA-12 | P2 | Agents page overclaims | `/agents/` | "trained", "most comprehensive set of solo founder AI tools", and "within Claude Code" are inaccurate, unverifiable, or tied to one surface | New |
| CA-13 | P2 | Pricing autonomy claims undercut human-in-the-loop | `/pricing/` | "on autopilot" and "lands in their inbox… ready to sign" contradict "starting point, not final answer". "Other 70%" is unsourced | New |
| CA-14 | P2 | Newest post lacks CTA and visible FAQ | `beta-testers-went-quiet` | The Blog note requires one next step. The FAQ exists only in JSON-LD, so the visible content and the schema differ | New |
| CA-15 | P2 | Vision revenue copy contradicts pricing | `/vision/` | "Founders only pay their model providers" vs $49–$499/mo tiers | New |
| CA-16 | P2 | Founder-operations posts have no pillar | `beta-testers-went-quiet`, `parked-vs-forgotten-ideas` | The beta post points to a pillar it is not a member of; the parked post has no pillar. The new founder-first posts have no cluster home, and no cluster links to a pillar or sibling | New |
| CA-17 | P2 | Carta statistic cites a generic data hub | `best-ai-tools-for-solo-founders-2026` | The link does not support the specific "about a third" claim. Updating it is a fact update, which the scope rule allows | New |
| CA-18 | P3 | Banned words and meme copy | `/`, `beta-testers-went-quiet`, `best-ai-tools…` | "not just engineering", "just a waiting list", "move the needle", "This Is the Way" | New |
| CA-19 | P3 | Inconsistent jobs/hats count | `/`, `/about/` | "9 hats… hand off 8" (home FAQ) vs "8 jobs… 7 of them" (brand) vs "eight departments" (about) | New |
| CA-20 | P3 | Community title generic | `/community/` | Only branded discovery | I2 |
| CA-21 | P3 | About title lacks credential; stale blog topic | `/about/` | The E-E-A-T proof is not in title/meta; "writes about agentic engineering" is stale | I4 |
| CA-22 | P3 | Glossary not linked from jargon-heavy pages | `/vision/`, `/skills/`, `/agents/` | Definitions exist but are unreachable from the pages that need them | I5 |
| CA-23 | P3 | Engineering proof point on pricing | `/pricing/` | "420+ PRs across all 8 domains" is an engineering metric, stale, on a general-register page | New |
| CA-24 | P3 | Emoji icons in marketing cards | `/`, `/pricing/` | The brand guide says no emojis in formal marketing copy (they are aria-hidden but visible) | New |
| CA-25 | P3 | Minor copy inconsistencies | `/pricing/`, `/getting-started/`, `site.json` | The pricing hero says "strategy" where the meta says "engineering". "Founding cohort of 10 teams" (solo audience). `statsLastVerified: 2026-04-22` is 5 months old | New |
| CA-26 | P3 | Blog H1 generic | `/blog/` | H1 "Blog" gives no topic signal. Fix together with CA-01 | New |

---

## Rewrite Suggestions

All rewrites use the **general register** (Website and Blog channel notes). They are declarative, and avoid "just/simply", "AI-powered", "assistant/copilot" and "plugin" in positioning copy. Trust scaffolding is included where the copy claims autonomy.

### R1. `/blog/` — founder-first title, meta, H1 (CA-01, CA-26)

| Element | Current | Suggested |
|---|---|---|
| seoTitle | Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams | Solo Founder Blog: How to Run Every Part of Your Company Alone \| Soleur |
| description | Field notes on building a billion-dollar company alone — Company-as-a-Service strategy, agentic engineering case studies, and engineering deep dives from Soleur. | Guides for solo founders on marketing, legal, finance and customers: how to run every part of your company without hiring, and where an AI team takes work off your plate. |
| H1 | Blog | Running a company alone shouldn't mean doing everything alone. |
| Category labels | What is Company-as-a-Service? / Soleur vs. Competitors / Case Studies / Engineering Deep Dives | Run Your Company / What Is Company-as-a-Service? / Soleur vs. Alternatives / Case Studies / Technical Notes |

**Rationale:** The Blog note says to target "the words a founder types when they have the problem" and to use the general thesis, which is used here as the H1, word for word. The index is not a post, so the "refresh keeps title/meta" scope rule does not apply. "Technical Notes" keeps pre-rule posts findable without presenting engineering as the blog's purpose.

### R2. `/blog/` — fix the category filter (CA-02)

- **Current:** `{% if "CaaS" in post.data.tags or ("ai-agents" in post.data.tags and …) %}`. No post is tagged `CaaS`.
- **Suggested:** Add an explicit `category:` frontmatter key to each post (`run-your-company` \| `caas` \| `comparison` \| `case-study` \| `technical`) and filter on it. Stop inferring categories from overlapping tags. Minimum fix: replace `"CaaS"` with `"company-as-a-service"` and re-check that comparison and case-study posts are still excluded.
- **Rationale:** Tags describe topics; they are a poor way to assign categories. Almost every post carries `company-as-a-service`, so a tag-based filter will keep mis-sorting posts. Put `company-as-a-service-platform` and `how-to-run-every-department-with-ai-agents` in the CaaS section, and `beta-testers-went-quiet` and `parked-vs-forgotten-ideas` in "Run Your Company".

### R3. `/skills/` — title, H1, FAQ definition (CA-03, CA-11)

| Element | Current | Suggested |
|---|---|---|
| seoTitle (new) | (none; renders "Soleur Skills") | AI Workflows for Solo Founders — 60+ Ready-to-Run Skills \| Soleur |
| H1 | Agentic Engineering Skills | Skills: the workflows your AI team follows |
| FAQ "What is a Soleur skill?" | A skill is a multi-step automated workflow that orchestrates agents, tools, and knowledge to complete complex tasks. … | A skill is a workflow your AI team follows to get a job done, such as a competitive analysis, a privacy policy or a product launch. Each skill runs the same steps every time, and brings in the right specialists for each step. You review the result before anything ships. |

**Rationale:** "60+" is the brand's minimum count for static copy. "AI workflows" is the founder's search term. The FAQ uses the brand glossary definition for Skills, plus trust scaffolding. Keep the existing "agentic engineering" definition paragraph in the body for technical visitors (`summaryRegister: technical` still fits the body).

### R4. `/vision/` — label the roadmap (CA-04, CA-15)

| Card | Current | Suggested |
|---|---|---|
| Bring Your Own Intelligence | Plug in your own API keys (Anthropic, OpenAI, Gemini, Llama, and more). Zero compute overhead from Soleur -- total control over your intelligence spend. | **On the roadmap.** Today Soleur runs on Anthropic's Claude models, and you bring your own Claude subscription or API key. Next: plug in keys from any model provider and keep full control of your model spend. |
| Multi-Model AI Agent Orchestration | Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy. Local models for privacy-sensitive data. One orchestrator across every provider. | **On the roadmap.** One orchestrator that routes each task to the model best suited for it, including local models for privacy-sensitive data. |
| Low Barrier | Free or low-cost access for the Idea Phase. Founders only pay their model providers, making Soleur the obvious choice for experimentation. | Start free with the self-hosted version and pay only your model provider. Hosted plans start at $49/month when you want managed infrastructure. |

**Rationale:** The brand guide's rule for machine-read copy ("answer engines quote verbatim with no page context") applies equally to Soleur's own capability claims. The "On the roadmap" label keeps the bold vision and removes the false present tense. Dropping "GPT-4o" also removes a dated model name.

### R5. `/` — relabel the press strip (CA-05)

- **Current:** label "As seen in"; item "Inc.com — The thesis behind Soleur, as reported on the billion-dollar solo founder."
- **Suggested:** label "Why now"; item "Inc.com: Anthropic's CEO predicts the first billion-dollar one-person company →"
- **Rationale:** This keeps the external citation, which helps AEO, without implying coverage Soleur has not earned. If Inc.com has in fact covered Soleur by name, link that article instead and keep "As seen in".

### R6. `/` — pain-point hero and meta (CA-06)

| Element | Current | Suggested |
|---|---|---|
| hero-tagline | The Company-as-a-Service platform that already knows your business. Build a billion-dollar company — alone. | You're doing 8 jobs. Soleur helps you tackle 7 of them, with an AI team that already knows your business. |
| hero-sub (opening) | Soleur is the source-available Company-as-a-Service platform: 60+ AI agents across 8 business departments … | Marketing, legal, finance, sales, support, operations, product and engineering: your AI specialists share one memory of your company, so every department builds on what the others decided. You make the calls. |
| meta description | Company-as-a-Service for solo founders. AI agents across 8 departments — … | Stop hiring, start delegating. Soleur gives solo founders an AI team for marketing, legal, finance, sales and support that remembers everything about your business. |

**Rationale:** This is the brand guide's primary pitch, lightly adapted. It keeps the softened "helps you tackle". CaaS stays as the section label, where it teaches the term without carrying the headline. The billion-dollar thesis can move to the quote section, where the Amodei citation already carries it.

### R7. `/` — homepage "How do I get started?" answer (CA-07)

- **Current:** Join the waitlist for the cloud platform, or install the self-hosted version and run `/soleur:go` to start. …
- **Suggested:** Join the waitlist for the hosted version, which runs in your browser with nothing to install. Want to start today? The free self-hosted version sets up in two steps, and the Getting Started page walks you through it. Then describe what you need, such as a feature, a contract or a competitive analysis, and Soleur sends it to the right specialists.
- **Rationale:** General register, no command syntax, and the waitlist remains the primary CTA.

### R8. `/getting-started/` — separate onboarding from CLI reference (CA-08, CA-09)

- **Structure:** Keep the hero, definition, install block and one "Existing project? / Starting fresh?" callout. Move the Claude Code vs Grok Build table and the "Updating later?" callout to the README or a docs page, and link it once: "Updating, uninstalling, or running on Grok Build? See the setup reference."
- **Workflow intro — current:** "Soleur follows a structured 6-step workflow for software development:"
- **Workflow intro — suggested:** "For engineering work, Soleur follows six steps, from idea to shipped. Marketing, legal, finance and the other departments get their own workflows: describe the job and Soleur picks the right one."
- **FAQ "What do I need to run Soleur?" — suggested:** "For the hosted version, a browser and a waitlist spot; access opens in waves to a small founding cohort. For the self-hosted version, available today, you need Claude Code on macOS, Linux or Windows (WSL) and a Claude subscription or API key. Setup takes two commands."
- **Rationale:** The page keeps its transactional job, and the answer engines get a first sentence that is true today.

### R9. Canonical lifecycle (CA-10)

- **Suggested canonical sequence (use on all three pages):** Brainstorm → Plan → Build → Review → Ship → Compound (six stages). On `/skills/` change "five stages: brainstorm, plan, implement, review, and compound" to match. On `/getting-started/` reorder so `ship` comes before `compound`, and rename `work` to "build" in the visible labels.
- **Rationale:** Describing the same thing identically everywhere strengthens entity clarity for AI models. Verify the canonical order against the actual skill chain before publishing.

### R10. `/agents/` — accuracy fixes (CA-12)

| Current | Suggested |
|---|---|
| Each Soleur agent is trained for a specific business function … | Each Soleur agent is built for one business function (code review, brand strategy, legal compliance, financial reporting, competitive intelligence), with its role and instructions written down and open to inspection. |
| Soleur agents are specialized AI personas with domain expertise that execute business tasks within Claude Code. … | Soleur agents are AI specialists that each handle one business function. They share one knowledge base, so each agent works from what the others already decided, not from a blank page. |
| Soleur provides the most comprehensive set of solo founder AI tools across 8 departments: … | Soleur agents cover 8 departments: engineering, marketing, legal, finance, operations, product, sales and support. Each department has a lead agent that coordinates its specialists. |

### R11. `/pricing/` — trust-consistent autonomy language (CA-13, CA-23, CA-25)

| Current | Suggested |
|---|---|
| Brand identity, SEO, content strategy, competitive positioning. Your public presence on autopilot. | Brand identity, SEO, content strategy, competitive positioning. Your public presence, drafted and kept consistent; you approve what ships. |
| Your CLO drafts it, your compliance auditor reviews it, and it lands in their inbox — formatted, footnoted, and ready to sign. | Your legal agent drafts it, your compliance agent checks it, and it lands on your desk formatted and footnoted, ready for your review and signature. |
| Coding tools handle code. Soleur handles the other 70% of running a company — … | Coding tools handle code. Soleur handles the rest of running a company: marketing, legal, finance, operations, product, sales and support. |
| Designed, built, and shipped by Soleur — using Soleur. 420+ PRs across all 8 domains. | Designed, built, and shipped by Soleur, using Soleur. |
| (hero) … strategy, marketing, legal, finance, … | … engineering, marketing, legal, finance, … |

**Rationale:** Legal output reaching a prospect without founder review is the objection the brand guide ranks first ("What if the output is wrong?"), 8/10 personas. Keep "70%" only if a source is cited next to it. The footer line matches the brand's fixed tagline wording.

### R12. `beta-testers-went-quiet` — add CTA and visible FAQ (CA-14, CA-16, CA-18)

- **Add before the technical link:** "Want an AI team that tracks your testers while you build the product? [Join the waitlist](/pricing/#waitlist)". This mirrors the CTA pattern in `parked-vs-forgotten-ideas`.
- **Add a visible `## Frequently asked questions` block** with the same 3 Q&As already in the JSON-LD ("How many beta testers do I need…", "How do I get feedback from beta testers without pestering them?", "Is it okay to log what beta testers do…").
- **Change** "A beta that can't tell you anything is just a waiting list with extra steps." to "A beta that can't tell you anything is a waiting list with extra steps."
- **Pillar:** remove `pillar: billion-dollar-solo-founder`, or add the post to that pillar's `members`. Preferred: create a founder-operations pillar (see R13).
- **Scope note:** This post was published after the 2026-09-25 Blog note, so bringing it into line with that note (CTA) is a compliance fix, not a re-angle. Title, slug, H1, meta and keywords stay unchanged.

### R13. New founder-operations cluster (CA-16)

| Role | Piece | Status |
|---|---|---|
| Pillar (to plan) | "How to Run a Company Alone: The Solo Founder's Operating System" (target: "how to run a business alone", "solo founder operations") | Gap |
| Cluster | `parked-vs-forgotten-ideas` | Exists; add `pillar:` |
| Cluster | `beta-testers-went-quiet` | Exists; move `pillar:` |
| Cluster | `how-to-run-every-department-with-ai-agents` | Exists (pre-rule); link from the pillar only |

Each cluster must link to the pillar and to at least one sibling. The two new posts can link to each other ("decisions stay decided" ↔ "a beta that answers back"). Writing the new pillar is content-plan work, not a fix under this audit.

### R14. `/community/` — title (CA-20)

- **Current:** Community — Soleur
- **Suggested:** Soleur Community: Solo Founders Building With an AI Team, on Discord and GitHub
- **Rationale:** This replaces the prior R6, which said "open-source". The license is BSL 1.1 (source-available), so "open-source" would be inaccurate.

### R15. `/about/` — title and blog line (CA-21)

- **seoTitle (new):** About Jean Deruelle, Founder of Soleur: 15+ Years Building Distributed Systems
- **Current body:** "Jean writes about agentic engineering, solo founding, and the mechanics of the billion-dollar one-person company on the Soleur blog."
- **Suggested body:** "Jean writes about running a company alone (marketing, legal, operations, and the decisions only a founder can make) on the Soleur blog."

### R16. Glossary links and small copy fixes (CA-18, CA-19, CA-22, CA-24, CA-25)

| Location | Current | Suggested |
|---|---|---|
| `/vision/` hero sub | Where Soleur is headed. | Where Soleur is headed, and the terms behind it. New to Company-as-a-Service? Start with the [glossary](/glossary/#company-as-a-service). |
| `/skills/`, `/agents/` intro | "Agentic engineering" link → Karpathy tweet only | Keep the citation; add "([definition](/glossary/#agentic-engineering))" |
| `/` comparison section | … and more — not just engineering. | … and more, well beyond engineering. |
| `/` section label | This Is the Way | You Decide. Agents Execute. |
| `/` FAQ "Who is Soleur for?" | Solopreneurs and solo founders wearing 9 hats who want to hand off 8 of them. | Solo founders doing 8 jobs who want help with 7 of them. |
| `best-ai-tools…` | …tools and platforms that genuinely move the needle for solo founders… | …tools and platforms that earn their place for solo founders… (voice fix; get operator sign-off first, since the scope rule limits refreshes to facts) |
| `best-ai-tools…` | `[Carta, State of Private Markets](https://carta.com/data/)` | Link the specific Carta report/post that states the solo-founder share, or soften to "a growing share" if no specific source is found (route to `soleur:marketing:fact-checker`) |
| `/`, `/pricing/` cards | Emoji icons (for example &#x1F9E0;, &#x26A1;, &#x1F4BB;) | Replace with the monoline SVG icons already used in `agents.domains` cards |
| `/getting-started/` FAQ | …founding cohort of 10 teams… | …founding cohort of 10 founders… |
| `_data/site.json` | `statsLastVerified: 2026-04-22` | Re-verify and bump |

---

## Summary Scorecard

| Page | Title / meta fit | Intent match | Readability / register | Top issue | Priority |
|---|---|---|---|---|---|
| `/` | Strong title; meta jargon-led | Strong | Good; register leaks | CA-05, CA-06 | **P1** |
| `/getting-started/` | Strong (fixed) | Partial | Split audience | CA-08, CA-09 | P2 |
| `/pricing/` | Strong | Strong | Strong; autonomy overclaims | CA-13 | P2 |
| `/agents/` | Strong (fixed) | Strong | Accuracy slips | CA-12 | P2 |
| `/skills/` | **Weak** | Partial | Technical register | CA-03, CA-11 | **P1** |
| `/blog/` | **Off-brand** after 09-25 | Partial | Good structure; broken taxonomy | CA-01, CA-02 | **P1** |
| `/community/` | Weak | Navigational only | Strong, candid | CA-20 | P3 |
| `/about/` | Adequate | Strong | Strong | CA-21 | P3 |
| `/vision/` | Strong | Strong | Dense; **accuracy** | CA-04, CA-15 | **P1** |
| `beta-testers-went-quiet` | Good | Strong | Exemplary opening; no CTA | CA-14 | P2 |
| `parked-vs-forgotten-ideas` | Strong | Strong | **Model post** | CA-16 (pillar) | P2 |
| `best-ai-tools…2026` | Strong | Strong | Jargon slip; weak citation | CA-17 | P2 |
| `loop-engineering…` | Good | Strong | Technical (allowed) | none | n/a |
| `claude-code-plugin-vs-skill-vs-mcp` | Developer query | Strong (dev) | Technical (allowed) | none | n/a |

**P1 (next sprint):** CA-01 and CA-02 (blog index repositioning and taxonomy fix, together), CA-03 (skills title), CA-04 (vision roadmap labels), CA-05 (press-strip relabel).

**P2:** CA-06 to CA-17. Homepage hero and meta, getting-started split, lifecycle consistency, skills/agents/pricing accuracy and register, the beta post CTA and FAQ, the founder-ops pillar, the Carta citation.

**P3:** CA-18 to CA-26. Banned words, counts, community and about titles, glossary links, emoji icons, stale verification date, blog H1.

---

## Notes and Caveats

- **Live-site parity not verified.** Every finding comes from source on `main`. If production lags `main`, some resolved items (C1, I3, I6) may not be live yet. Re-run with WebFetch allowed, or have `soleur:marketing:seo-aeo-analyst` check the rendered HTML.
- **Schema content parity (CA-14):** only the missing visible FAQ is flagged. Whether hidden-FAQ JSON-LD is still eligible for rich results is for the seo-aeo-analyst.
- **Blog scope rule respected:** no title, slug, H1, meta or keyword changes are proposed for posts published before 2026-09-25. CA-17 is a fact update (allowed). The "move the needle" fix is marked as needing operator sign-off.
- **Prior R6 corrected:** "open-source" does not describe a BSL 1.1 project. Use "source-available" in all titles.
- No competitor URLs were analyzed. This is a single-site content audit, not a gap analysis. R13's pillar is a gap to hand to a content-plan run.
