# Content Audit — soleur.ai — 2026-10-05

## Executive Summary

This audit covers 15 surfaces on soleur.ai: 9 core pages, 4 pillar and comparison pages, and the 2 newest blog posts. Most of what the 2026-05-25 audit flagged has been fixed. Meta descriptions and SEO titles now exist on the getting-started page and the blog index. The `$95,000/mo` replacement figure on the pricing page now cites its sources. The agents page title is now generated from the live count. A full set of pillar pages is live: Company-as-a-Service, AI Agents for Solo Founders, Solo Founder AI Stack, AI CMO, AI CTO, Agentic Engineering, the glossary, and the comparison pages.

The main risk now is drift. The brand guide changed on 2026-09-25 (#8774) so that the blog is written for non-technical founders, but the site around the blog has not caught up. The blog index still targets developer search terms ("agentic engineering", "engineering deep dives"). The two newest founder posts land in the wrong blog categories. The getting-started title promises "install in two commands", while the page itself pushes the waitlist and its FAQ says "Nothing to install." Three pages state competitor revenue as fact, which the brand guide has banned since #6768. Department and job counts also disagree from page to page, including in FAQ structured data that answer engines quote word for word.

**Headline counts:** 0 P0, 7 P1, 7 P2, 5 P3. Of the 12 findings in the previous audit, 6 are fixed, 2 are partly fixed, and 4 persist. One earlier fix (the getting-started title) now causes a new problem, F3.

**Top 3 actions:**

1. Rewrite the blog index title, meta description and categories for the non-technical founder reader. Add a "Founder Playbooks" category (F1, F2).
2. Change competitor revenue claims from statements of fact to attributed claims, or replace them with funding signals. Make department and job counts consistent across all pages (F4, F5).
3. Rewrite the getting-started title and meta description so they match a page whose main action is the waitlist (F3).

## Scope and Method

| Item | Detail |
|---|---|
| Live fetch | **Failed.** WebFetch was blocked by the environment hook (`cron-containment: tool class not permitted: WebFetch`). All analysis uses the local Eleventy source under `plugins/soleur/docs/` at commit `5db4848b`. Rendered output may differ where templates inject content (for example `{{ stats.* }}` and `page-freshness.njk`). |
| Pages sampled (15) | `/`, `/pricing/`, `/getting-started/`, `/agents/`, `/skills/`, `/vision/`, `/about/`, `/community/`, `/blog/`, `/ai-agents-for-solo-founders/`, `/company-as-a-service/`, `/ai-cmo/`, `/compare-soleur-vs-cursor/`, the blog posts `2026-09-25-parked-vs-forgotten-ideas` and `2026-09-26-beta-testers-went-quiet` |
| Spot-checked by grep | All `pages/*.njk` frontmatter, and the blog posts dated 2026-05 through 2026-09 (titles, metas, competitor figures, department counts) |
| Not covered | Legal pages, changelog, the full archive of older blog posts, and individual agent and skill cards. This is a sample. |
| Brand guide | Loaded `knowledge-base/marketing/brand-guide.md`: Identity, Voice, Audience Voice Profiles, Value Proposition Framings, Channel Notes > Website, Channel Notes > Blog |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, llms.txt format (owned by seo-aeo-analyst). Where JSON-LD text appears below, only its *content* is assessed. |

## Trend vs. 2026-05-25 Audit

| Prior ID | Prior finding | Status 2026-10-05 | Evidence |
|---|---|---|---|
| C1 | Getting-started title is brand-only | **Fixed, but now causes F3** | `seoTitle` "Get Started with Soleur — Install Your AI Organization in Two Commands" is live. The hero now leads with the waitlist, so the title and the page disagree. |
| C2 | Skills title brand-only; technical H1 | **Persists** (F6) | `title: Soleur Skills`, no `seoTitle`, H1 "Agentic Engineering Skills" |
| C3 | Blog title brand-only | **Fixed, but now causes F1** | `seoTitle` and description added. Both target "agentic engineering", which the 2026-09-25 Blog note says not to target. |
| C4 | No meta descriptions | **Fixed** | Every sampled page has a `description:`. The previous result was probably a fetcher artifact. |
| C5 | "Agentic engineering" undefined on skills page | **Partly fixed** | A definition paragraph now exists, but it is written in the technical register (Karpathy link, MCP) instead of the plain-language glossary definition. |
| I1 | Homepage hero leans on CaaS before the pain | **Persists** (F7) | "Company-as-a-Service" appears 3 times in the hero (label, tagline, sub-hero) and is the first phrase of the meta description |
| I2 | Community title generic | **Persists** (F13) | `seoTitle: "Community — Soleur"`, H1 "Community" |
| I3 | Agents count hard-coded | **Fixed** | Title and H1 now render from `{{ stats.agents }}` |
| I4 | About: E-E-A-T proof not in title | **Partly fixed** (F15) | H1 improved to "About Soleur and its founder, Jean Deruelle". The FAQ carries the "15+ years" proof. The title is unchanged. |
| I5 | Vision page dense with jargon | **Persists** (F16) | Unchanged since 2026-06-01. Unverifiable superlatives added. |
| I6 | `$95,000/mo` unsourced | **Fixed** | Footnote and 2 FAQ entries cite Robert Half, Payscale and Levels.fyi |
| I7 | No category pillar pages | **Fixed** | 8 or more pillar and cluster pages are live |

## Per-Page Analysis

### 1. Homepage (`/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" / "Stop hiring. Start delegating." |
| Meta description | "Company-as-a-Service for solo founders. AI agents across 8 departments…". Leads with the CaaS framing, which the brand guide says is not suitable for first-contact copy. |
| Detected keywords | AI agents for solo founders, Company-as-a-Service, AI organization, knowledge base, Soleur vs Cursor/Copilot |
| Keyword alignment | **Strong title. Weak meta and hero.** The title carries the primary commercial keyword. The meta and hero spend their first words on "Company-as-a-Service", a term with almost no searches that needs explaining. |
| Search intent | Commercial with some informational. The FAQ ("What is Soleur?", "What if the AI output is wrong?") and the Cursor/Copilot comparison section are good matches for both intents. |
| Readability | Good overall. The H1 is on-brand, and the "What if the AI output is wrong?" FAQ is strong trust scaffolding. Problems: the "This Is the Way" section label (a pop-culture reference with no keyword or clarity value); the Workflow cards ("Ship: One command. Tests, version bump, commit, deploy") use engineering register on a general-register surface; the FAQ "Who is Soleur for?" says "wearing 9 hats who want to hand off 8", which contradicts the brand guide's "doing 8 jobs… 7 of them" (F5). |

### 2. Pricing (`/pricing/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." |
| Detected keywords | AI agent pricing, AI agents for solo founders cost, replace hiring cost |
| Keyword alignment | **Strong.** |
| Search intent | Transactional. **Matches.** Plans, prices, waitlist and a "Do I pay for Claude separately?" FAQ answer the buyer's questions. |
| Readability | Strong, and the `$95K` breakdown is now well sourced. Problems: (a) the "What this looks like on a Tuesday" scenarios overclaim autonomy. The DPA "lands in their inbox… ready to sign" skips the human review that the homepage promises (F10). (b) "Soleur handles the other 70% of running a company" is an unsourced statistic. (c) "420+ PRs" is an engineering proof point on a general-register page (F17). (d) `last_updated: 2026-06-01` (F19). |

### 3. Getting Started (`/getting-started/`)

| Field | Assessment |
|---|---|
| Title / H1 | SEO title "Get Started with Soleur — Install Your AI Organization in Two Commands" / "The AI that already knows your business." |
| Detected keywords | install Soleur, Claude Code plugin, self-hosted AI agents, get started |
| Keyword alignment | **Misaligned.** The title and meta promise installation. The hero's main button is "Join the waitlist", and the first FAQ answer is "Nothing to install." |
| Search intent | The title signals a transactional install. The page delivers a waitlist signup first and self-hosting second. The intent mismatch will raise bounce rates from the install queries the title attracts, and it contradicts the brand guide's Website note: "Do not reference CLI installation as the primary CTA." |
| Readability | **Weak for the general register.** Below the hero, the page is a terminal manual: 2 install commands, a 4-row Claude Code vs Grok Build table, a ~120-word "Updating later?" callout with 5 inline commands, and FAQ answers (also in FAQPage JSON-LD) containing `/soleur:go`, "Skill tool `soleur:<skill>`" and "Read `SKILL.md` in this process". The definition paragraph and the citations to BSL, Claude Code and MCP are good. |

### 4. Agents (`/agents/`)

| Field | Assessment |
|---|---|
| Title / H1 | "{{ stats.agents }} AI Agents for Solo Founders — Every Department \| Soleur" / "Your AI Organization: {{n}} Specialists Across {{n}} Departments" |
| Keyword alignment | **Strong.** The count is generated from live data, as the brand guide requires. |
| Search intent | Informational. **Matches.** |
| Readability | Good. The opening definition ("An AI agent is a specialist that handles a specific business function") is quotable. Problems: "Each Soleur agent is **trained** for a specific business function" is technically inaccurate. The agents are instructed and prompted, not trained, and answer engines will quote this sentence (F12). The prose body opens on "Agentic engineering" before the general-register definition. `summaryRegister: technical` conflicts with the page's general-register title. |

### 5. Skills (`/skills/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Skills" (no `seoTitle`) / "Agentic Engineering Skills" |
| Keyword alignment | **Weak.** The title is brand-only. The H1 targets a developer query. The meta description ends on "agentic engineering". |
| Search intent | Informational. Partial: it lists skills but does not say what they do for a founder. |
| Readability | Adequate for technical readers. The homepage stats strip links general visitors straight here, and the first thing they read is a Karpathy tweet link and "Model Context Protocol (MCP)". The glossary definition ("workflows the AI team follows to get things done") is missing. |

### 6. Vision (`/vision/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Vision: Company-as-a-Service" (no `seoTitle`) / "The Soleur Vision: Company-as-a-Service for the Solo Founder" |
| Keyword alignment | Adequate for owning the CaaS term. Overlaps with `/company-as-a-service/`, which is the stronger pillar, so these 2 pages risk cannibalizing each other's rankings. |
| Search intent | Informational / thought leadership. Matches. |
| Readability | Dense. Unverifiable claims ("one of the first model-agnostic orchestration engines", "infinite leverage") reduce the chance of being cited. "Model-agnostic" contradicts the homepage FAQ ("Both paths run on Anthropic's Claude models") (F9, F16). |

### 7. About (`/about/`)

| Field | Assessment |
|---|---|
| Title / H1 | "About Jean Deruelle" / "About Soleur and its founder, Jean Deruelle" |
| Keyword alignment | Good for branded queries. The E-E-A-T proof ("15+ years building distributed systems") is in the body and FAQ but not in the title. |
| Search intent | Navigational. Matches. |
| Readability | Good. Hero subtext "The founder behind Soleur." is filler. |

### 8. Community (`/community/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Community — Soleur" / "Community" |
| Keyword alignment | **Weak.** Unchanged since the last audit. No page-freshness include. |
| Search intent | Navigational, for branded queries only. |
| Readability | Concise. Live GitHub and Discord stats are good proof. |

### 9. Blog Index (`/blog/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "Blog" |
| Meta | "Field notes on building a billion-dollar company alone — Company-as-a-Service strategy, agentic engineering case studies, and engineering deep dives from Soleur." |
| Keyword alignment | **Misaligned with the current brand guide.** The Blog note (2026-09-25, #8774) names "agentic engineering" as a developer query *not* to target, and calls for the general thesis ("Running a company alone shouldn't mean doing everything alone") instead of the billion-dollar engineering thesis. The title and meta use both banned angles. |
| Search intent | Informational. Partial. The H1 "Blog" is generic. |
| Readability / IA | **Broken categorization.** The tag filters in `blog.njk` send `2026-09-26-beta-testers-went-quiet` (tags: beta-testing, solo-founder…) to **"Engineering Deep Dives"**, its catch-all bucket. `2026-09-25-parked-vs-forgotten-ideas` (tag `ai-agents`) lands under **"What is Company-as-a-Service?"**. The 2 newest posts, written for non-technical founders, are filed under labels that tell that reader the posts are not for them (F2). |

### 10. AI Agents for Solo Founders (`/ai-agents-for-solo-founders/`), pillar page

| Field | Assessment |
|---|---|
| Title / H1 | "AI Agents for Solo Founders: The 2026 Guide to Delegating Every Department \| Soleur" / "AI Agents for Solo Founders" |
| Keyword alignment | **Strong.** The exact-match keyword appears in the title, H1, first sentence and a bolded definition. |
| Search intent | Commercial investigation. Matches. |
| Readability | Strong, with Carta data, a bolded definition and a pain-point H2 ("You Are Doing Eight Jobs"). **Violation:** "Cursor reached $1 billion in annual recurring revenue" states a competitor's revenue as fact (F4). |

### 11. Company-as-a-Service (`/company-as-a-service/`), pillar page

| Field | Assessment |
|---|---|
| Keyword alignment | Strong for "Company-as-a-Service (CaaS)". |
| Search intent | Informational definition. Matches. |
| Readability | Good. **Violation:** it states Cursor's revenue ("$1 billion in annual recurring revenue at a $29.3 billion valuation") and Lovable's ("reached $200 million in ARR") as fact (F4). |

### 12. AI CMO (`/ai-cmo/`), role cluster page

| Field | Assessment |
|---|---|
| Keyword alignment | Strong ("AI CMO"). |
| Readability / accuracy | **Inconsistent cost figure.** The SEO title says "$240K Salary", the meta description says "$290K human CMO", and the comparison table says "~$294,000/yr" in 3 places. Search snippets and AI answers will quote different numbers (F8). |

### 13. Soleur vs Cursor (`/compare-soleur-vs-cursor/`)

| Field | Assessment |
|---|---|
| Keyword alignment | Strong ("Soleur vs Cursor" in title, H1 and meta). |
| Search intent | Commercial comparison. Matches. |
| Readability | Good. **Violation:** "roughly 1 billion dollars in annual recurring revenue at a 29.3 billion dollar valuation" (F4). |

### 14. Blog post: "Parked or Forgotten? How to Tell Before It Costs You" (2026-09-25)

| Field | Assessment |
|---|---|
| Keyword alignment | Good. SEO title "Parked vs. Forgotten Ideas: How Solo Founders Track Decisions". The higher-volume phrase "idea parking lot" appears in paragraph 2. |
| Blog note compliance | **Compliant.** It opens in the founder's own words and puts the outcome before the mechanism. It has no inline code, and the GitHub link sits once at the end behind plain words. |
| Issue | Miscategorized on the blog index (F2). Per the Blog note's scope rule, its title and meta description must stay as they are. |

### 15. Blog post: "Your First Beta Testers Went Quiet. Now What?" (2026-09-26)

| Field | Assessment |
|---|---|
| Keyword alignment | Adequate. The SEO title "How to Run a Beta Program That Actually Tells You Something" leaves out "beta testers", the query a founder would type. Its title and meta must stay as they are (scope rule). Note this for future posts. |
| Blog note compliance | **Compliant.** Problem-first opening, plain register, one technical link at the end. |
| Issue | Filed under "Engineering Deep Dives" (F2). |

## Findings

| ID | Priority | Title | Page(s) | Status | Why it matters |
|---|---|---|---|---|---|
| F1 | **P1** | Blog index targets developer queries | `/blog/` | New (register drift after #8774) | The SEO title and meta target "agentic engineering" and "engineering deep dives", which the Blog note bans. This mismatch is on the funnel page for the blog's non-technical reader. |
| F2 | **P1** | Founder posts misfiled in blog categories | `/blog/` (`blog.njk` tag filters) | New | The 2 newest founder posts appear under "Engineering Deep Dives" and "What is Company-as-a-Service?". There is no founder-playbook category, so new posts default into the technical bucket. |
| F3 | **P1** | Getting-started title promises install, page sells waitlist | `/getting-started/` | New (side effect of fixing C1) | The title says "Install… in Two Commands". The hero button is the waitlist, and the FAQ says "Nothing to install". This is an intent mismatch, and it breaks the brand guide's "Do not reference CLI installation as the primary CTA" rule. |
| F4 | **P1** | Competitor revenue asserted as fact | `/ai-agents-for-solo-founders/`, `/company-as-a-service/`, `/compare-soleur-vs-cursor/`. Also blog posts `2026-03-19-soleur-vs-cursor`, `2026-03-24-ai-agents-for-solo-founders`, `2026-04-22-billion-dollar-solo-founder-stack` | New | This breaks the brand guide Don't added 2026-07-20 (#6768): Cursor $1B ARR and Lovable $200M ARR are stated without in-sentence attribution. Answer engines quote these sentences without the surrounding context. |
| F5 | **P1** | Department and job counts drift | `/` FAQ and JSON-LD ("9 hats… 8"), blog `2026-05-05-soleur-vs-tanka` meta ("9 departments"), blog `2026-04-21-soleur-vs-devin` ("nine departments") | New | `stats.departments` = 8, and llms.txt and the brand guide say "8 jobs… 7 of them". The numbers conflict inside machine-ingested FAQ data and meta descriptions. |
| F6 | **P1** | Skills page title brand-only, H1 technical | `/skills/` | Persists (C2) | No search hook. The page is reached from the homepage stats strip by general visitors. |
| F7 | **P1** | Homepage hero and meta lead with CaaS | `/` | Persists (I1, now including the meta) | CaaS appears 3 times in the hero and opens the meta description. The brand guide says CaaS is "not suitable for headlines or first-contact messaging". Pain-point framing won 7/10 in testing. |
| F8 | **P2** | AI CMO cost figure inconsistent | `/ai-cmo/` | New | $240K title, $290K meta and $294K table. Snippets and AI answers will cite different numbers. |
| F9 | **P2** | Claude-only claims vs Grok Build support | `/` FAQ, `/pricing/` note, `/vision/`, `/getting-started/` | New | The homepage says "Both paths run on Anthropic's Claude models", the getting-started page documents Grok Build, and the vision page says "model-agnostic". Verify the support scope with product, then make one consistent claim. |
| F10 | **P2** | Pricing scenarios overclaim autonomy | `/pricing/` "On a Tuesday" | New | "Lands in their inbox… ready to sign" contradicts the human-in-the-loop promise. This is the #1 objection, raised by 8 of 10 personas. |
| F11 | **P2** | Getting-started is a terminal manual | `/getting-started/` body and FAQPage text | New | It has a 5-command update callout, a Grok table, and `SKILL.md`/`/soleur:go` in FAQ answers that answer engines quote. This fails the general-register test. |
| F12 | **P2** | Agents described as "trained" | `/agents/` | New | The claim is technically inaccurate and quotable. It invites "fine-tuned model?" misreadings. |
| F13 | **P2** | Community title and H1 generic | `/community/` | Persists (I2) | Non-branded discovery is lost. |
| F14 | **P2** | Founder-blog publishing gap | `/blog/` | New | No posts between 2026-06-15 and 2026-09-25 (3+ months). Only 2 posts follow the new founder-problem search rule, so coverage of founder queries is thin. |
| F15 | **P3** | About title lacks E-E-A-T proof | `/about/` | Partly fixed (I4) | Experience is in the body but not in the title. The hero filler line is wasted space. |
| F16 | **P3** | Vision page jargon and unverifiable superlatives | `/vision/` | Persists (I5) | "One of the first model-agnostic orchestration engines" and "infinite leverage" are unverifiable. It also overlaps with the `/company-as-a-service/` pillar. |
| F17 | **P3** | Pricing has an unsourced "70%" and an engineering proof point | `/pricing/` | New | "The other 70% of running a company" is unsourced, and "420+ PRs" is an engineering metric on a general-register page. |
| F18 | **P3** | Homepage pop-culture label and engineering workflow copy | `/` | New | "This Is the Way" adds no clarity. The Workflow cards ("version bump, commit") are written in the technical register. |
| F19 | **P3** | Stale `last_updated` on core pages | `/`, `/pricing/`, `/agents/`, `/vision/`, `/about/` (all 2026-06-01) | New | Freshness signals are 4 months old, and the pricing page promises to "refresh each salary-guide cycle". |

## Rewrite Suggestions

All rewrites use the **general register** (the brand guide default for the website and blog). They lead with the pain or the outcome and add trust scaffolding where relevant. They avoid "AI-powered", "just/simply", "copilot/assistant", "plugin" (outside literal commands), stated competitor revenue, and exact agent or skill counts in prose.

### R1. `/blog/`: title, meta, H1 (fixes F1)

- **Current SEO title:** `Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams`
- **Suggested:** `Soleur Blog — Playbooks for Running a Company Alone, Without Doing Everything Alone`
- **Current meta:** `Field notes on building a billion-dollar company alone — Company-as-a-Service strategy, agentic engineering case studies, and engineering deep dives from Soleur.`
- **Suggested meta:** `Plain-language playbooks for solo founders: decisions you keep, early users who answer back, contracts, marketing and money, and what changes when an AI team handles the busywork.`
- **Current H1:** `Blog`
- **Suggested H1:** `Running a company alone shouldn't mean doing everything alone.`
- **Rationale:** Uses the general thesis that the Blog note requires. Swaps developer queries for founder-problem phrases. The blog index is not a post, so the scope rule's "keep title" clause does not apply to it.

### R2. `/blog/`: category structure (fixes F2)

- **Current:** 4 categories. "Engineering Deep Dives" is the catch-all for any post without a CaaS, ai-agents, comparison or case-study tag.
- **Suggested:** Add a first category, **"Founder Playbooks"**, that matches the `solo-founder` tag. Rename the catch-all to **"Under the Hood"**, place it last, and exclude `solo-founder` posts from both "Under the Hood" and "What is Company-as-a-Service?".
- **Rationale:** New founder posts land in a category written for their reader. Legacy technical posts keep a home without labeling the blog "engineering".

### R3. `/getting-started/`: title and meta (fixes F3)

- **Current SEO title:** `Get Started with Soleur — Install Your AI Organization in Two Commands`
- **Suggested:** `Get Started with Soleur — Join the Waitlist or Run Your AI Team Today`
- **Current meta:** `Install Soleur in two commands and run a full AI organization — marketing, legal, finance, operations, sales, and support — without hiring anyone.`
- **Suggested meta:** `Two ways to start: join the waitlist for hosted Soleur, or run the free self-hosted version today. Your AI team for marketing, legal, finance and operations remembers your business.`
- **Rationale:** Matches the page's main call to action (the waitlist) and keeps self-hosting as the second path, as the brand guide's Website note requires. "Remembers your business" reinforces the memory-first H1.

### R4. `/getting-started/`: "Updating later?" callout (fixes F11)

- **Current:** about 120 words, 5 inline commands, failure modes, and a reinstall one-liner.
- **Suggested:** `**Updating later?** Run both update commands. The first refreshes the catalog and the second updates what you run. Full steps and troubleshooting are in the [README](<GitHub README anchor>).`
- **Rationale:** Moves technical detail to GitHub, where the brand guide says it belongs. Do the same for the FAQ answer "What is the difference between /soleur:go and individual skills?": rewrite it in plain words ("One entry point reads what you ask for and picks the right workflow. You can also start a specific workflow directly.") so the FAQPage text contains no command syntax.

### R5. Competitor revenue claims (fixes F4)

- **Current (`/ai-agents-for-solo-founders/`):** `Cursor reached $1 billion in annual recurring revenue.`
- **Suggested (preferred, verifiable signal):** `Cursor raised at a $29.3 billion valuation, according to CNBC.`
- **Alternative (attributed):** `CNBC reports that Cursor passed $1 billion in annualized revenue.`
- Apply the same pattern to `/company-as-a-service/` (Cursor and Lovable sentences), `/compare-soleur-vs-cursor/`, and the 3 blog posts listed in F4. For blog posts, the refresh scope rule allows fact corrections.
- **Rationale:** Brand guide Don't (#6768): "Vendor-reported metrics get explicit attribution… or get omitted." The rule covers rendered copy and structured data alike.

### R6. Department and job counts (fixes F5)

- **Current (homepage FAQ and JSON-LD "Who is Soleur for?"):** `Solopreneurs and solo founders wearing 9 hats who want to hand off 8 of them.`
- **Suggested:** `Solo founders doing 8 jobs who want help with 7 of them, especially founders deciding whether to make their first hire. Soleur gives you the capacity of a team before you have the budget for one.`
- **Tanka post meta:** change "executes across 9 departments" to "executes across 8 departments". This is a fact correction only; the wording otherwise stays as published. The scope rule keeps meta descriptions, so confirm that a numeric fact fix is acceptable.
- **Devin post body:** change "one of nine departments… all nine" to "one of eight departments… all eight".
- **Rationale:** Matches `stats.departments`, llms.txt and the brand guide's pain-point pitch ("You're doing 8 jobs. Soleur helps you tackle 7 of them"). It also keeps the guide's softened "helps you tackle" wording.

### R7. `/skills/`: title, H1 and opening (fixes F6)

- **Current title / H1:** `Soleur Skills` / `Agentic Engineering Skills`
- **Suggested SEO title:** `AI Workflow Skills — 60+ Repeatable Workflows for Solo Founders | Soleur`
- **Suggested H1:** `Workflow Skills: How Your AI Team Gets Work Done`
- **Suggested first paragraph (before the existing agentic-engineering paragraph):** `Skills are the workflows your AI team follows to get things done. Each one chains AI specialists together to finish a multi-step job, like launching a marketing campaign, drafting a privacy policy, or reviewing a product change. You approve the result, and every run teaches the system what worked for your business.`
- **Rationale:** Uses the glossary definition and the "60+" soft floor. If the technical register is intentional (`summaryRegister: technical`), the fallback title is `Claude Code Skills for Agentic Engineering — 60+ Workflows | Soleur`, which at least adds a search hook.

### R8. Homepage: hero tagline and meta (fixes F7)

- **Current tagline:** `The Company-as-a-Service platform that already knows your business. Build a billion-dollar company — alone.`
- **Suggested:** `You're doing 8 jobs. Soleur helps you tackle 7 of them, with AI specialists that already know your business. Build a billion-dollar company, alone.`
- **Current meta:** `Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support.`
- **Suggested meta:** `You're doing 8 jobs. Soleur helps with 7: marketing, legal, finance, operations and more, run by AI specialists that remember everything about your business.`
- **Current hero label:** `Company-as-a-Service` → **Suggested:** `Your AI Organization`
- **Rationale:** Pain-point framing (won 7/10 in testing) comes first. CaaS stays in the sub-hero and FAQ, where there is room to explain it. The thesis line is kept.

### R9. `/ai-cmo/`: consistent cost figure (fixes F8)

- **Current SEO title:** `AI CMO: Marketing Leadership Without the $240K Salary (2026) | Soleur`
- **Suggested:** `AI CMO: Marketing Leadership Without the $290K Price Tag (2026) | Soleur`
- **Rationale:** Matches the meta description ($290K) and the sourced total-comp table (~$294K). One number across title, meta and body.

### R10. `/pricing/`: DPA scenario (fixes F10)

- **Current:** `Your CLO drafts it, your compliance auditor reviews it, and it lands in their inbox — formatted, footnoted, and ready to sign.`
- **Suggested:** `Your legal agent drafts it, your compliance agent checks it against your policies, and it lands in your review queue, formatted and footnoted. You approve it, then send.`
- **Rationale:** Adds the brand guide's trust scaffolding (human-in-the-loop) where buyers decide. Answers "What if the output is wrong?" in context.

### R11. `/agents/`: "trained" claim (fixes F12)

- **Current:** `Each Soleur agent is trained for a specific business function`
- **Suggested:** `Each Soleur agent is built for one business function, with its own instructions, its own checks, and access to your company's shared memory`
- **Rationale:** Accurate, quotable, and it reinforces the memory differentiator.

### R12. `/community/`: title and H1 (fixes F13)

- **Current:** `Community — Soleur` / `Community`
- **Suggested SEO title:** `Soleur Community — Solo Founders Building With AI Teams on Discord and GitHub`
- **Suggested H1:** `Build alongside other solo founders`
- **Rationale:** Adds non-branded discovery terms and an outcome-first H1.

### R13. `/about/`: title and hero (fixes F15)

- **Current title / hero subtext:** `About Jean Deruelle` / `The founder behind Soleur.`
- **Suggested SEO title:** `About Jean Deruelle — Founder of Soleur, 15+ Years Building Distributed Systems`
- **Suggested subtext:** `Software engineer for 15+ years. Now building the platform that lets one founder run every department.`

### R14. Model-support claim (fixes F9, verify first)

- **Current (homepage FAQ "Is Soleur free?"):** `Both paths run on Anthropic's Claude models, so your AI costs depend on your Claude usage.`
- **Suggested, if Grok Build support is confirmed as user-facing:** `Soleur runs on Anthropic's Claude, and the self-hosted version also works in Grok Build. Your AI costs depend on your model usage.`
- **Vision page:** replace `one of the first model-agnostic orchestration engines` with a verifiable statement of which model environments are supported today.

## Content Gap Notes (F14)

Founder-problem queries from the Blog note's search rule with no matching post:

| Planned piece | Target query | Intent | Type | Priority |
|---|---|---|---|---|
| How to handle contracts as a solo founder | "how to handle contracts as a solo founder" | Informational | Searchable | P1 |
| Can AI run my marketing? What to delegate and what to keep | "AI to run my marketing" | Commercial | Searchable | P1 |
| Hire or delegate? The first-hire decision for solo founders | "should I hire my first employee" | Informational | Searchable and shareable (opinion) | P2 |
| What 4 months of running a company with an AI team taught me | n/a (founder data and opinion) | n/a | Shareable | P2 |

Each should link back to the `/ai-agents-for-solo-founders/` pillar and to one sibling post. The current plan is all searchable posts, so add at least one shareable piece per month, built on original data or an opinion.

## Caveats

- WebFetch was blocked, so rendered HTML, injected meta and live page copy were not verified. Findings reflect source as of commit `5db4848b`.
- F9 (Claude-only vs Grok Build) depends on how much Grok Build support product intends to promise publicly. Treat R14 as conditional.
- Per the Blog note's scope rule, no title, slug, H1, meta or target-keyword rewrites are proposed for existing blog posts. Only fact corrections (F4, F5) are suggested.
- The `simply` and `leverage AI` grep hits on `/ai-cto/`, `/ai-agents-for-solo-founders/` and `/claude-code-plugins/` were reviewed and judged acceptable usage (they describe competitors, or use "leverage" as a noun). They are not findings.
