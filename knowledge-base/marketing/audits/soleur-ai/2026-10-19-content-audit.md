# Content Audit — soleur.ai — 2026-10-19

## Executive Summary

This audit re-checks every finding from the 2026-10-05 content audit against the current Eleventy source and looks for new problems. **None of the 14 P1 and P2 findings from 2026-10-05 has been fixed.** One P3 (stale `last_updated` dates) is partly fixed.

The site did change in the last two weeks, but in other places. On 2026-10-06 the homepage got a new hero button ("Get the self-hosted version"), an illustrated "How a brief reaches the departments" section, and a sourced, dated Dario Amodei paraphrase. The `date` and `last_updated` fields on 6 pages were moved to 2026-10-06. The illustration section is the best trust copy on the site. It labels itself as sample data and says the founder approves every result.

Two of those changes make old findings worse:

1. **The new hero button sends first-time visitors into the terminal manual.** It links to `/getting-started/#self-hosted`, which opens with "Install in Claude Code", 2 terminal commands, a Claude Code vs Grok Build command table, and a ~120-word update callout with 5 inline commands. F11 moves from P2 to **P1**.
2. **The freshness dates moved, but the content behind them did not.** `/vision/` now shows "Last updated October 6, 2026" above present-tense claims about GPT-4o routing and OpenAI, Gemini and Llama keys. `/pricing/` shows the same date above "ready to sign" and the unsourced "70%". This is a new P2 (N1).

No blog posts have been published since 2026-09-26, 23 days ago. There are no new posts to audit.

**Headline counts:** 0 P0, 8 P1, 7 P2, 8 P3 (23 total). Carried: 19 (1 escalated, 3 now affect more pages). New: 4.

**Top 3 actions (all copy or template edits, under an hour each):**

1. Rewrite the top of `/getting-started/#self-hosted` for a founder who does not code, and move the update callout to the README (F11, F3). The homepage hero test (review date 2026-11-03) is now sending its main traffic there.
2. Ship the blog hub repositioning: title, meta, H1 and a "Founder Playbooks" category (F1, F2). This was a one-file change on 2026-10-05 and it is still open.
3. Do the facts-and-counts sweep: competitor revenue, "9 hats", "nine departments", AI CMO salary, "trained", "model-agnostic" (F4, F5, F8, F9, F12). Re-check the facts before moving any `last_updated` date again (N1).

## Scope and Method

| Item | Detail |
|---|---|
| Live fetch | **Failed.** WebFetch on `https://soleur.ai` was blocked by the environment hook (`cron-containment: tool class not permitted: WebFetch`). `git log` was also blocked (`not allowlisted`), so this audit cannot list commits since 2026-10-05. Changes were found from frontmatter dates, code comments (`#9577`, `#9579`) and the brand guide's 2026-10-06 notes. |
| Source audited | Local Eleventy source under `plugins/soleur/docs/` at HEAD `7c92f4ab`, read with Read, Grep and Glob. Template output such as `{{ stats.* }}` and `page-freshness.njk` was worked out from the source, not from a rendered page. |
| Pages sampled (15) | `/`, `/pricing/`, `/getting-started/`, `/agents/`, `/skills/`, `/vision/`, `/about/`, `/community/`, `/blog/`, `/ai-agents-for-solo-founders/`, `/company-as-a-service/`, `/ai-cmo/`, `/compare-soleur-vs-cursor/`, `/known-external-tools/`, `_includes/page-freshness.njk` (shared summary block) |
| Grep sweeps | All `pages/*.njk` and `pages/*.md` frontmatter. All `blog/*.md` checked for competitor revenue, department counts, autonomy claims and model claims. `_data/site.json` and `_data/fanoutDemo.js`. |
| New blog posts since 2026-10-05 | **None.** Newest post: `blog/2026-09-26-beta-testers-went-quiet.md`. |
| Not covered | Legal pages, changelog, individual agent and skill cards, and full re-reads of older posts. This is a sample. |
| Brand guide | Read `knowledge-base/marketing/brand-guide.md` (`last_updated: 2026-09-25`, with notes added 2026-10-06): Identity, Voice, Audience Voice Profiles, Value Proposition Framings, Channel Notes > Website / Landing Page (including the 2026-10-06 hero CTA test notes, #9579 and #9588), and Channel Notes > Blog. |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, llms.txt format (owned by seo-aeo-analyst). JSON-LD text is assessed only for what it says. |

## Delta vs 2026-10-05 (P1 and P2 findings)

Issue numbers are from `knowledge-base/marketing/audits/soleur-ai/2026-10-05-content-plan.md`, Part 1.

| Prior ID | Prior P | Finding | Issue | Status 2026-10-19 | Evidence (current source) |
|---|---|---|---|---|---|
| F1 | P1 | Blog index targets developer queries | #9104 | **STILL OPEN** | `pages/blog.njk:3-4`: seoTitle and description still say "Agentic Engineering" and "engineering deep dives". `pages/blog.njk:11`: H1 is still "Blog". |
| F2 | P1 | Founder posts misfiled; no founder category | #9105 | **STILL OPEN** | `pages/blog.njk:41-46` still has 4 categories, with "Engineering Deep Dives" as the catch-all (`:117`). `blog/2026-09-25-parked-vs-forgotten-ideas.md` (tag `ai-agents`) still lands in "What is Company-as-a-Service?". `blog/2026-09-26-beta-testers-went-quiet.md` still lands in "Engineering Deep Dives". |
| F3 | P1 | Getting-started title says install; page leads with the waitlist | #9107 | **STILL OPEN** | `pages/getting-started.njk:3-4` unchanged ("Install Your AI Organization in Two Commands"). The hero button is still the waitlist (`:18`). The FAQ still opens "Nothing to install." (`:202`, `:242`). The date moved to 2026-10-06 without changing either. |
| F4 | P1 | Competitor revenue stated as fact | #7179 | **STILL OPEN, and the figures now disagree** | Stated as fact: `pages/ai-agents-for-solo-founders.njk:33` (Cursor "$1 billion in annual recurring revenue"); `pages/company-as-a-service.njk:35` (Cursor $1B ARR at $29.3B) and `:41` (Lovable "reached $200 million in ARR"); `pages/compare-soleur-vs-cursor.njk:30`; `blog/2026-03-24-ai-agents-for-solo-founders.md:64`. In `blog/2026-03-19-soleur-vs-cursor.md` the body hedges with "reportedly exceeded $2 billion" (`:25`), but the FAQ question states "Cursor's $2B+ ARR" (`:105`, and FAQPage JSON-LD `:140`). Readers now see $1B on 4 surfaces and $2B+ on 1. `blog/2026-04-22-billion-dollar-solo-founder-stack.md` has no Cursor or Lovable revenue sentences today, so it has no current violation. |
| F5 | P1 | Department and job counts disagree | #8462 | **STILL OPEN, on more pages** | `index.njk:221` and JSON-LD `:282`: "wearing 9 hats who want to hand off 8". `blog/2026-05-05-soleur-vs-tanka.md:5`: "executes across 9 departments". `blog/2026-04-21-soleur-vs-devin.md:44,78`: "all nine", "one of nine departments". **Newly found:** `blog/2026-04-21-one-person-billion-dollar-company.md:86` says "all nine domains" and "a nine-department organization". |
| F6 | P1 | Skills title is brand-only; H1 is technical | #5601 | **STILL OPEN** | `pages/skills.njk:2` `title: Soleur Skills`, no `seoTitle`. H1 "Agentic Engineering Skills" (`:13`). The first sentence still opens on a Karpathy tweet link and MCP (`:24`). |
| F7 | P1 | Homepage hero and meta lead with CaaS | #9112 | **STILL OPEN** | `index.njk:4`: the meta still opens "Company-as-a-Service for solo founders". Hero label (`:14`), tagline (`:16`) and sub-hero (`:17`) all say CaaS, and the first section H2 (`:71`) repeats it. That is 4 uses before the stats strip ends. |
| F8 | P2 | AI CMO cost figure inconsistent | #9499 | **STILL OPEN** | `pages/ai-cmo.njk:3` "$240K Salary"; `:4` "$290K human CMO"; the table says ~$294K. |
| F9 | P2 | Claude-only vs Grok Build vs "model-agnostic" | #9500 | **STILL OPEN, more pages affected** | The homepage now says "Runs inside your own Claude Code" (`index.njk:21`, `:41`). `pages/getting-started.njk:60-91` documents Grok Build. `pages/vision.njk:29` still says "one of the first model-agnostic orchestration engines", and `:79`, `:87` describe OpenAI, Gemini and Llama keys and "GPT-4o for strategy" in the present tense (also #6376). **Newly found:** the shared summary paragraph in `_includes/page-freshness.njk:26` ("Soleur is a model-agnostic Company-as-a-Service orchestration engine") renders as the first paragraph on every page with `summaryRegister: technical`, which is `/agents/`, `/skills/` and `/vision/`. |
| F10 | P2 | Pricing scenario overclaims autonomy | #9111 | **STILL OPEN** | `pages/pricing.njk:196`: "lands in their inbox — formatted, footnoted, and ready to sign." The homepage's own new illustration (`_data/fanoutDemo.js:22`) says legal drafts are "for review by you and a qualified lawyer", so the two pages now contradict each other. |
| F11 | P2 | Getting-started is a terminal manual | #2669 | **STILL OPEN, ESCALATED to P1** | Unchanged: `pages/getting-started.njk:47` "Install in Claude Code"; `:56-57` commands; `:61-91` Grok table; `:99` the ~120-word update callout; FAQ answers with `SKILL.md` and `/soleur:go` (`:218`, `:274`). It is now the destination of the homepage hero's main button (`index.njk:20`). See F11 below. |
| F12 | P2 | Agents described as "trained" | #6378 | **STILL OPEN** | `pages/agents.njk:27`, FAQ `:93`, and JSON-LD `:125`. `last_updated` is still 2026-06-01. |
| F13 | P2 | Community title and H1 generic | #6377 | **STILL OPEN** | `pages/community.njk:3` "Community — Soleur"; H1 "Community" (`:11`); no date. |
| F14 | P2 | Founder-blog publishing gap | #8466 | **STILL OPEN** | No posts after 2026-09-26. The plan's "2 founder-problem posts a month" has produced 0 posts in October so far. |

**Other plan items checked (from the AEO audit, but about content):**

| Plan # | Finding | Issue | Status | Evidence |
|---|---|---|---|---|
| 3 | `/vision/` presents the multi-provider roadmap as shipped | #6376 | **STILL OPEN** | `pages/vision.njk:68-97`, under the H2 "Model-Agnostic Architecture", in the present tense. It now carries a 2026-10-06 date (N1). |
| 14 | CaaS pillar superlatives; "the numbers tell the story" | #6085 | **STILL OPEN** | `pages/company-as-a-service.njk:41`; "a leading company-as-a-service platform" at `:174` and in JSON-LD `:270`. |
| 18 | Conflicting claims about who started the CaaS term | #9501 | **STILL OPEN** | `pages/glossary.njk:24` "Soleur coined"; `pages/company-as-a-service.njk:145` "not one company's marketing term"; `:174` "a leading". |

**Prior P3 findings:** F15 (About title) still open. F16 (Vision jargon) still open. F17 (pricing "70%" and "420+ PRs") still open (`pages/pricing.njk:291,331,389`). F18 ("This Is the Way") still open (`index.njk:70`). F19 (stale `last_updated`) is **partly fixed**: `index.njk`, `pricing.njk`, `vision.njk`, `about.njk` and `getting-started.njk` now say 2026-10-06. `agents.njk` (2026-06-01), `skills.njk` (2026-06-15) and both compare pages (2026-06-01) were not updated.

**Prior findings fully fixed: none.**

**Good changes since 2026-10-05 that were not tied to a finding:**

- The Amodei prediction now appears as a dated paraphrase with an Inc. source (`index.njk:127-129`, `pages/vision.njk:26`, `pages/about.njk:36`).
- The homepage illustration (`_data/fanoutDemo.js`) is labeled "Illustrative example · sample data". It shows a failed test and a question waiting on the founder, and it says plainly that the founder has the final say.
- The pricing meta (`pages/pricing.njk:4`) now says "from $49/month once hosted plans open", which is honest about what is available today.

## Per-Page Analysis

### 1. Homepage (`/`, `plugins/soleur/docs/index.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" / "Stop hiring. Start delegating." |
| Meta description | "Company-as-a-Service for solo founders. AI agents across 8 departments…". It still opens with the term the brand guide says is "not suitable for headlines or first-contact messaging" (F7). |
| Detected keywords | AI agents for solo founders, Company-as-a-Service, self-hosted, Claude Code, Soleur vs Cursor/Copilot, knowledge base |
| Keyword alignment | **Strong title, weak meta and hero.** CaaS appears 4 times before the stats strip ends. |
| Search intent | Commercial with some informational. The FAQ and the Cursor/Copilot section match both. |
| Readability | Mixed. **Better:** the new illustration section is plain, specific and honest about limits. **Worse:** the hero now asks first-time visitors to choose between "self-hosted" and "hosted" before it says what either one does, and the self-hosted note expects them to know what Claude Code is (`:21`). The "Agents Execute" card says "running autonomously on your command" (`:82`), which contradicts the illustration two sections lower (N2). "9 hats… 8" is still in the FAQ (F5). "This Is the Way" is still a section label (F18). |
| Brand guide note | The 2026-10-06 hero CTA test (#9579, #9588) lists "hero copy drifts toward developer register" as a revert trigger. The button text is fine. The install note and its landing page are where the developer register shows (F11). |

### 2. Pricing (`/pricing/`, `pages/pricing.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." |
| Keyword alignment | **Strong.** The meta is now honest about when plans open. |
| Search intent | Transactional. **Matches.** |
| Readability | Strong overall. Still open: "ready to sign" (F10, `:196`); unsourced "other 70%" in the FAQ and JSON-LD (F17, `:291`, `:331`); "420+ PRs" engineering proof point (F17, `:389`). **Newly found:** the waitlist H2 says "Your AI organization is ready." (`:27`) while the hosted version is "coming soon" (N4). The freshness date was moved with these claims unchanged (N1). |

### 3. Getting Started (`/getting-started/`, `pages/getting-started.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Get Started with Soleur — Install Your AI Organization in Two Commands" / "The AI that already knows your business." |
| Detected keywords | install Soleur, Claude Code plugin, self-hosted, waitlist, Grok Build |
| Keyword alignment | **Misaligned** (F3). The title promises an install. The hero button is the waitlist, and the first FAQ says "Nothing to install." |
| Search intent | Split three ways: the title says install, the hero says waitlist, and the homepage's main button now lands in the `#self-hosted` section. |
| Readability | **Weak for the general register, and now on the main path** (F11). A founder who clicks "Get the self-hosted version" on the homepage skips this page's hero. The first things they see are "Source-available. Install in Claude Code.", two `claude plugin` commands, a 4-row command table for two tools, and a 120-word update callout. The workflow list (`:103`) says "for software development". The definition paragraph (`:32`) and the citations (`:33-40`) are still good. |

### 4. Agents (`/agents/`, `pages/agents.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | Generated from `{{ stats.agents }}` / "Your AI Organization: {{n}} Specialists Across {{n}} Departments" |
| Keyword alignment | **Strong.** |
| Search intent | Informational. **Matches.** |
| Readability | Good, with 2 accuracy problems. "Trained" appears 3 times, once in FAQPage text (F12). The shared summary paragraph now opens with "model-agnostic… orchestration engine" (F9, via `summaryRegister: technical` at `:7`). `last_updated` is 2026-06-01 (F19). |

### 5. Skills (`/skills/`, `pages/skills.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Skills" (no `seoTitle`) / "Agentic Engineering Skills" |
| Keyword alignment | **Weak** (F6). |
| Search intent | Informational, partly met. |
| Readability | Technical. It opens with a Karpathy tweet link, Claude Code and MCP, and then the "model-agnostic" summary (F9). The plain glossary definition ("workflows the AI team follows to get things done") is missing. |

### 6. Vision (`/vision/`, `pages/vision.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Vision: Company-as-a-Service" / "The Soleur Vision: Company-as-a-Service for the Solo Founder" |
| Keyword alignment | Adequate. It still overlaps the stronger `/company-as-a-service/` pillar. |
| Search intent | Thought leadership. Matches. |
| Readability / accuracy | Dense. The Amodei line is now sourced, which is good. Still there: "infinite leverage" (`:26`), "one of the first model-agnostic orchestration engines" (`:29`), and present-tense cards for multi-provider keys and GPT-4o routing (`:79`, `:87`), all under a fresh 2026-10-06 date (F9, F16, N1, #6376). |

### 7. About (`/about/`, `pages/about.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "About Jean Deruelle" / "About Soleur and its founder, Jean Deruelle" |
| Keyword alignment | Good for branded queries. The "15+ years" proof is still missing from the title (F15). |
| Readability | Good. The hero subtext "The founder behind Soleur." (`:13`) is still filler. "Jean writes about agentic engineering…" (`:36`) describes the blog in its pre-2026-09-25 register (P3, part of F15). |

### 8. Community (`/community/`, `pages/community.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Community — Soleur" / "Community" |
| Keyword alignment | **Weak.** Unchanged (F13). |
| Readability | Short and clear. The live GitHub and Discord stats are good proof. |

### 9. Blog Index (`/blog/`, `pages/blog.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "Blog" |
| Keyword alignment | **Misaligned with the Blog note** (F1). "Agentic engineering" is named there as a developer query not to target. |
| Search intent | Informational, partly met. |
| IA | **Categories still broken** (F2). Both founder posts are filed under labels that tell a non-technical reader the posts are not for them. |

### 10. AI Agents for Solo Founders (`pages/ai-agents-for-solo-founders.njk`)

| Field | Assessment |
|---|---|
| Keyword alignment | **Strong.** |
| Search intent | Commercial investigation. Matches. |
| Readability | Strong. Still breaks the competitor-revenue rule at `:33` (F4). "Roughly 70% of company work" (`:99`, `:135`, JSON-LD `:211`) has no source. Same class as F17; noted, not a separate finding. |

### 11. Company-as-a-Service (`pages/company-as-a-service.njk`)

| Field | Assessment |
|---|---|
| Keyword alignment | Strong for "Company-as-a-Service (CaaS)". |
| Readability / accuracy | Still breaks the competitor-revenue rule (F4, `:35`, `:41`). "A leading company-as-a-service platform" is in the FAQ and JSON-LD (`:174`, `:270`; #6085, #9501). `date` moved to 2026-10-06; there is no `last_updated`. |

### 12. AI CMO (`pages/ai-cmo.njk`)

| Field | Assessment |
|---|---|
| Keyword alignment | Strong ("AI CMO"). |
| Accuracy | Three salary figures ($240K, $290K, ~$294K) remain (F8). |

### 13. Soleur vs Cursor (`pages/compare-soleur-vs-cursor.njk`)

| Field | Assessment |
|---|---|
| Keyword alignment | Strong. |
| Accuracy | "Roughly 1 billion dollars in annual recurring revenue" (`:30`, F4). The blog post on the same matchup says "$2B+". `last_updated` is 2026-06-01. |

### 14. Known external tools (`/known-external-tools/`, `pages/known-external-tools.md`) — newly in sample

| Field | Assessment |
|---|---|
| Title / H1 | "Known external tools — output filters and Soleur's evidence surface" / "Known external tools" |
| Purpose | A troubleshooting page for developers (rtk, Headroom, hook markers). Its contents are fine for technical docs. |
| Issue | It is linked from the sitewide footer "Resources" column, between Blog and Glossary (`_data/site.json:75`). So every general-register page links to a page whose meta description says "footguns" and "evidence literals". It has no `date` (N3). |

### 15. Shared page summary (`_includes/page-freshness.njk`)

| Field | Assessment |
|---|---|
| Role | Renders the first summary paragraph and the "Last updated" line on every page that includes it. Answer engines are likely to quote this paragraph. |
| Issue | The technical variant (`:26`) opens "Soleur is a model-agnostic Company-as-a-Service orchestration engine". That is the same unverified claim as `/vision/`, now on 3 pages (F9). |

## Findings

| ID | Priority | Title | File(s) | New / Carried | Why it matters |
|---|---|---|---|---|---|
| F11 | **P1** (was P2) | The homepage's main button lands in a terminal manual | `pages/getting-started.njk:44-100`, `:218`, `:222`, `:274`, `:282`; `index.njk:20-21` | Carried (#2669), **escalated** | Since 2026-10-06 the main path from the homepage goes straight to install commands, a two-tool command table and a 120-word update callout. This is the "developer register" revert trigger in the brand guide's own test note, and it works against the alpha cohort goal of at least 3 of 10 non-Claude-Code founders. |
| F3 | **P1** | Getting-started title says install; hero says waitlist; FAQ says "Nothing to install" | `pages/getting-started.njk:3-4`, `:18`, `:202` | Carried (#9107) | One page makes three different promises. The 2026-10-06 brand note says the hero test "does not license 'install', 'CLI' or 'terminal' wording". |
| F1 | **P1** | Blog index targets developer queries | `pages/blog.njk:3-4`, `:11` | Carried (#9104) | This is the entry page for the blog's non-technical reader, and it uses the exact query the Blog note says not to target. |
| F2 | **P1** | Founder posts filed under engineering and CaaS labels | `pages/blog.njk:41-130` | Carried (#9105) | Every new founder post will default into "Engineering Deep Dives" unless its tags happen to match. |
| F4 | **P1** | Competitor revenue stated as fact, and the figures disagree | `pages/ai-agents-for-solo-founders.njk:33`; `pages/company-as-a-service.njk:35,41`; `pages/compare-soleur-vs-cursor.njk:30`; `blog/2026-03-24-ai-agents-for-solo-founders.md:64`; `blog/2026-03-19-soleur-vs-cursor.md:105,140` | Carried (#7179), now on more pages | Breaks the brand guide Don't (#6768), which covers JSON-LD too. Answer engines will now quote $1B or $2B+ depending on the page. |
| F5 | **P1** | "9 hats / nine departments" vs 8 | `index.njk:221,282`; `blog/2026-05-05-soleur-vs-tanka.md:5`; `blog/2026-04-21-soleur-vs-devin.md:44,78`; `blog/2026-04-21-one-person-billion-dollar-company.md:86` (newly found) | Carried (#8462), now on more pages | `stats.departments` = 8, and the brand guide says "8 jobs… 7 of them". The wrong count is in FAQPage text that answer engines quote. |
| F7 | **P1** | Homepage hero and meta lead with CaaS | `index.njk:4,14,16,17,71` | Carried (#9112) | 4 uses of CaaS before the visitor learns the pain point. Pain-point framing won 7/10 in testing. |
| F6 | **P1** | Skills title is brand-only; H1 and opening are technical | `pages/skills.njk:2,13,24` | Carried (#5601) | Linked from the homepage stats strip and the main nav, yet it gives no search hook to the ICP. |
| F9 | **P2** | Model-support claims disagree | `_includes/page-freshness.njk:26` (newly found); `pages/vision.njk:29,79,87`; `index.njk:21,41`; `pages/getting-started.njk:60-91` | Carried (#9500, #6376), now on more pages | "Model-agnostic" now opens the summary on 3 pages, while the homepage says Claude only and getting-started documents Grok Build. |
| F10 | **P2** | Pricing scenario says "ready to sign" | `pages/pricing.njk:196` | Carried (#9111) | Contradicts the homepage's new "review by you and a qualified lawyer" line. "What if it's wrong?" is the #1 objection (8 of 10 personas). |
| F12 | **P2** | Agents described as "trained" | `pages/agents.njk:27,93,125` | Carried (#6378) | Inaccurate, and quoted in FAQPage text. |
| F8 | **P2** | AI CMO cost figure inconsistent | `pages/ai-cmo.njk:3,4` + table | Carried (#9499) | Search snippets and AI answers will cite different numbers. |
| F13 | **P2** | Community title and H1 generic | `pages/community.njk:3,11` | Carried (#6377) | No discovery for anyone not already searching for "Soleur". |
| F14 | **P2** | No founder posts for 23 days | `plugins/soleur/docs/blog/` | Carried (#8466) | Only 2 posts follow the 2026-09-25 Blog note. The 2-a-month goal has 0 posts in October. |
| N1 | **P2** | Freshness dates moved without fixing the facts | `index.njk:7-8`, `pages/pricing.njk:9-10`, `pages/vision.njk:6-7`, `pages/about.njk:6-7`, `pages/getting-started.njk:7-8`, `pages/company-as-a-service.njk:7` | **New** | "Last updated October 6, 2026" now sits above known-open claims: GPT-4o routing, "ready to sign", "9 hats", Cursor ARR. A fresh date on stale facts tells readers and answer engines that the claims were re-checked. The 2026-10-05 plan said to "re-review the facts on core pages before bumping `last_updated`". |
| F15 | P3 | About title lacks E-E-A-T proof; filler subtext; blog described as "agentic engineering" | `pages/about.njk:2,13,36` | Carried | Small E-E-A-T and register gain left on the table. |
| F16 | P3 | Vision: jargon and unverifiable superlatives; CaaS origin claims disagree | `pages/vision.njk:26,29`; `pages/glossary.njk:24`; `pages/company-as-a-service.njk:145,174` | Carried (#9501, #6085) | "Infinite leverage", "one of the first", "Soleur coined", "a leading": none of these can be checked. |
| F17 | P3 | Unsourced "70%"; "420+ PRs" on a general-register page | `pages/pricing.njk:291,331,389`; `pages/ai-agents-for-solo-founders.njk:99,135,211` | Carried (#9111) | An unsourced statistic in FAQPage text. |
| F18 | P3 | "This Is the Way" label; engineering-register Workflow cards | `index.njk:70,146-177` | Carried | Adds no clarity; "version bump, commit" is technical register on the homepage. |
| F19 | P3 | Stale `last_updated` | `pages/agents.njk:6`, `pages/skills.njk:7`, `pages/compare-soleur-vs-cursor.njk:10`, `pages/compare-soleur-vs-devin.njk:10` | Carried, **partly fixed** | 5 pages updated (see N1 for the caveat); 4 remain 4 months old. |
| N2 | P3 | "Running autonomously" contradicts the new illustration | `index.njk:82` vs `_data/fanoutDemo.js:52,60` | **New** | The same page says agents run "autonomously" and that "you keep the final say". |
| N3 | P3 | Sitewide footer links to a developer troubleshooting page | `_data/site.json:75`; `pages/known-external-tools.md:2-3` | **New** | A general-register footer sends every visitor to a page about "footguns" and "evidence literals". It belongs under docs or GitHub. |
| N4 | P3 | Pricing waitlist H2 says the hosted product is ready | `pages/pricing.njk:27` | **New** (newly found; not dated) | "Your AI organization is ready." sits directly above "Join the waitlist" for a version that is coming soon. |

## Rewrite Suggestions

All rewrites use the **general register** (the brand guide default for the website and blog). They lead with the pain or outcome and keep the trust language ("you approve", "starting point"). They avoid "AI-powered", "just/simply", "copilot/assistant", "plugin" outside literal commands, stated competitor revenue, and exact counts in static prose. None of them changes the homepage hero button, which is under a time-boxed test until 2026-11-03.

### R1. `/getting-started/#self-hosted`: opening (fixes F11)

- **Current section label:** `Source-available. Install in Claude Code.`
- **Suggested:** `Source-available. Runs on your own machine.`
- **Current first paragraph:** `Prefer to run it yourself? Soleur is source-available and works in Claude Code today. Install it in two commands, keep your knowledge base as plain files on your own machine, and join the waitlist if you want the hosted version when it opens.`
- **Suggested:** `Run your AI team today, on your own computer. Self-hosted Soleur works inside Claude Code, Anthropic's AI workspace, with your Claude plan or an Anthropic API key. Your company's memory stays as plain files you own. Setup is the two steps below. If you would rather not touch a terminal, join the waitlist for the hosted version.`
- **Rationale:** Says what the reader gets and what they need before any command. "Claude Code" is defined in the same sentence, as the general register requires. It gives a non-technical founder a clear way out, which protects the cohort-mix goal in the hero test note.

### R2. `/getting-started/`: update callout and command FAQ (fixes F11)

- **Current:** ~120 words, 5 inline commands (`pages/getting-started.njk:99`).
- **Suggested:** `**Updating later?** Run both update commands; the first one alone does not update what you run. Full steps and troubleshooting are in the [README](<GitHub README anchor>).`
- **Current FAQ answer ("difference between /soleur:go and individual skills"):** has `SKILL.md`, `Skill tool soleur:<skill>`, `/go`.
- **Suggested question:** `Do I have to pick a workflow myself?` **Answer:** `No. Describe what you need in plain words and Soleur picks the right workflow. If you already know the step you want, such as planning or review, you can start it directly.`
- **Rationale:** Takes command syntax out of FAQPage text. The command table can stay, under a small "Command reference" heading after the plain-language opening.

### R3. `/getting-started/`: title and meta (fixes F3)

- **Current SEO title:** `Get Started with Soleur — Install Your AI Organization in Two Commands`
- **Suggested:** `Get Started with Soleur — Run Your AI Team Today or Join the Hosted Waitlist`
- **Current meta:** `Install Soleur in two commands and run a full AI organization — marketing, legal, finance, operations, sales, and support — without hiring anyone.`
- **Suggested:** `Two ways to start: run the free self-hosted version today, or join the waitlist for hosted Soleur. Your AI team for marketing, legal, finance and operations remembers your business.`
- **Current first FAQ answer:** `Nothing to install. The hosted version runs in your browser…`
- **Suggested:** `For the hosted version, nothing: it runs in your browser once your access opens. The self-hosted version runs inside Claude Code on macOS, Linux or Windows (WSL), with two setup steps.`
- **Rationale:** Matches both the homepage's self-hosted button and this page's waitlist button, and drops "install" from the title, as the 2026-10-06 note requires. The FAQ no longer contradicts the section below it.

### R4. `/blog/`: title, meta, H1 (fixes F1)

- **Current SEO title:** `Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams`
- **Suggested:** `Soleur Blog — Playbooks for Running a Company Alone, Without Doing Everything Alone`
- **Current meta:** `Field notes on building a billion-dollar company alone — Company-as-a-Service strategy, agentic engineering case studies, and engineering deep dives from Soleur.`
- **Suggested:** `Plain-language playbooks for solo founders: decisions you keep, early users who answer back, contracts, marketing and money, and what changes when an AI team handles the busywork.`
- **Current H1:** `Blog` → **Suggested:** `Running a company alone shouldn't mean doing everything alone.`
- **Rationale:** Uses the general thesis the Blog note requires. The index is not a post, so the scope rule's "keep title" clause does not apply.

### R5. `/blog/`: categories (fixes F2)

- Add a first category, **"Founder Playbooks"**, matching the `solo-founder` tag. Rename "Engineering Deep Dives" to **"Under the Hood"** and move it last. Exclude `solo-founder` posts from both "Under the Hood" and "What is Company-as-a-Service?" (`pages/blog.njk:54`, `:117`).

### R6. Competitor revenue (fixes F4)

- **Current (`pages/ai-agents-for-solo-founders.njk:33`):** `Cursor reached $1 billion in annual recurring revenue.`
- **Suggested (verifiable signal):** `Cursor raised money at a $29.3 billion valuation, CNBC reported.`
- **Current (`pages/company-as-a-service.njk:41`):** `Lovable reached $200 million in ARR`
- **Suggested:** `Lovable raised $330 million at a $6.6 billion valuation, TechCrunch reported`. The source is already linked in the same sentence.
- **Current FAQ (`blog/2026-03-19-soleur-vs-cursor.md:105`, JSON-LD `:140`):** `Does Cursor's $2B+ ARR indicate it is better for enterprise use than Soleur?`
- **Suggested:** `Does Cursor's reported growth mean it is better for enterprise use than Soleur?` Keep the answer and add "TechCrunch reported" wherever the figure appears.
- **Rationale:** Brand guide Don't (#6768). Using funding rounds everywhere also removes the $1B vs $2B+ conflict. The blog changes are fact corrections, which the scope rule allows.

### R7. Counts (fixes F5)

- **Current (`index.njk:221`, `:282`):** `Solopreneurs and solo founders wearing 9 hats who want to hand off 8 of them.`
- **Suggested:** `Solo founders doing 8 jobs who want help with 7 of them, especially founders deciding whether to make their first hire.` Keep the rest of the answer as it is.
- **Devin post (`:44`, `:78`) and one-person post (`:86`):** "nine" becomes "eight" (fact correction only).
- **Tanka post meta (`:5`):** "9 departments" becomes "8 departments". This is a numeric fact fix in a meta description, so confirm it is allowed under the Blog note scope rule.

### R8. Homepage tagline and meta (fixes F7)

- **Current tagline:** `The Company-as-a-Service platform that already knows your business. Build a billion-dollar company — alone.`
- **Suggested:** `You're doing 8 jobs. Soleur helps you tackle 7 of them, with AI specialists that already know your business. Build a billion-dollar company. Alone.`
- **Current meta:** `Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support.`
- **Suggested:** `You're doing 8 jobs. Soleur helps with 7: marketing, legal, finance, operations and more, run by AI specialists that remember everything about your business.`
- **Hero label (`:14`):** `Company-as-a-Service` → `Your AI Organization`. Keep CaaS in the sub-hero and FAQ, where there is room to explain it.
- **Rationale:** Puts the pain-point framing first and leaves the button under test alone. The hero test note compares click rates, so make this change after the 2026-11-03 review, or annotate the test window if it ships earlier.

### R9. `/skills/` (fixes F6)

- **Suggested SEO title:** `AI Workflow Skills — 60+ Repeatable Workflows for Solo Founders | Soleur`
- **Suggested H1:** `Workflow Skills: How Your AI Team Gets Work Done`
- **Suggested first paragraph (before the agentic-engineering paragraph):** `Skills are the workflows your AI team follows to get things done. Each one chains AI specialists together to finish a multi-step job, such as launching a campaign, drafting a privacy policy or reviewing a product change. You approve the result, and every run teaches the system what worked for your business.`

### R10. Shared summary and model claims (fixes F9)

- **Current (`_includes/page-freshness.njk:26`):** `Soleur is a model-agnostic Company-as-a-Service orchestration engine: 60+ specialist AI agents…`
- **Suggested:** `Soleur is a Company-as-a-Service orchestration engine: 60+ specialist AI agents and 60+ workflow skills across {{n}} departments, coordinated through one shared, compounding knowledge base. Source-available (BSL 1.1), it runs on Anthropic's Claude through Claude Code, with self-hosted support for Grok Build.` (Keep the Grok clause only if product confirms it as a public promise; see #9500.)
- **`pages/vision.njk:68-97`:** retitle the H2 `Model-Agnostic Architecture` to `On the Roadmap: Bring Your Own Model` and put the cards in the future tense ("Soleur will let you plug in…", "will select the best model for each task"). Replace `:29` "one of the first model-agnostic orchestration engines" with `an orchestration engine built so the agents, not the model, carry your company's knowledge`.

### R11. `/pricing/` (fixes F10, N4)

- **Current (`:196`):** `Your CLO drafts it, your compliance auditor reviews it, and it lands in their inbox — formatted, footnoted, and ready to sign.`
- **Suggested:** `Your legal agent drafts it and your compliance agent checks it against your policies. It lands in your review queue, formatted and footnoted. You approve it, then send.`
- **Current H2 (`:27`):** `Your AI organization is ready.` → **Suggested:** `Your AI organization is being built. Get in early.`

### R12. Homepage "Agents Execute" card (fixes N2)

- **Current (`index.njk:82`):** `{{ departmentList }} — every department, running autonomously on your command.`
- **Suggested:** `{{ departmentList }} — every department drafts, checks and reports back. You approve what ships.`

### R13. `/agents/` "trained" (fixes F12)

- **Current:** `Each Soleur agent is trained for a specific business function`
- **Suggested:** `Each Soleur agent is built for one business function, with its own instructions, its own checks, and access to your company's shared memory`. Apply at `:27`, `:93` and `:125`.

### R14. `/ai-cmo/` (fixes F8)

- **SEO title:** `AI CMO: Marketing Leadership Without the $290K Price Tag (2026) | Soleur`. This matches the meta and the sourced ~$294K table.

### R15. `/community/` (fixes F13)

- **SEO title:** `Soleur Community — Solo Founders Building With AI Teams on Discord and GitHub`
- **H1:** `Build alongside other solo founders`

### R16. `/about/` (fixes F15)

- **SEO title:** `About Jean Deruelle — Founder of Soleur, 15+ Years Building Distributed Systems`
- **Subtext:** `Software engineer for 15+ years. Now building the platform that lets one founder run every department.`
- **`:36`:** `Jean writes about agentic engineering, solo founding…` → `Jean writes plain-language playbooks for solo founders, and about what it takes to build a billion-dollar company alone, on the Soleur blog.`

### R17. Footer (fixes N3)

- Remove `Known external tools` from the "Resources" column in `_data/site.json:75`, and link it from the GitHub README or a docs index instead. If it must stay, add a `date:` to `pages/known-external-tools.md` and change "footguns" in its meta to "common failure modes".

### Process note for N1 (no rewrite)

Before the next `last_updated` change, check each page against the open findings for that page (vision: F9 and #6376; pricing: F10 and F17; homepage: F5 and F7; getting-started: F3 and F11). A date should only move when the claims under it have been checked. Agents, skills and the compare pages still need a real review and a new date (F19).

## Content Gap Notes (F14)

The 2026-10-05 gap list still applies; none of it has been published.

| Planned piece | Target query | Intent | Type | Priority |
|---|---|---|---|---|
| How to handle contracts as a solo founder | "how to handle contracts as a solo founder" | Informational | Searchable | P1 |
| Can AI run my marketing? What to delegate and what to keep | "AI to run my marketing" | Commercial | Searchable | P1 |
| Self-hosted or hosted? Choosing how to start with an AI team | "self-hosted vs hosted AI tools for small business" | Commercial | Searchable | P2 (new; supports the hero test's two paths in plain language) |
| Hire or delegate? The first-hire decision | "should I hire my first employee" | Informational | Searchable + shareable | P2 |
| What the founding cohort taught us (beta-checkpoint data, #2603) | n/a (original data) | n/a | Shareable | P2 |

Each should link to the `/ai-agents-for-solo-founders/` pillar and to one sibling post. The plan is mostly searchable posts, so keep at least one shareable, data- or opinion-led piece a month.

## Caveats

- WebFetch and `git log` were both blocked. Rendered HTML, live copy and the exact commit history since 2026-10-05 were not checked. "Unchanged" means the current source still contains the text the 2026-10-05 audit quoted.
- F4 for `blog/2026-03-19-soleur-vs-cursor.md`: the body sentence says "reportedly", but without git history this audit cannot tell whether it changed after 2026-10-05.
- F9 and R10 depend on how much Grok Build support product wants to promise in public (#9500).
- Under the Blog note scope rule, no title, slug, H1, meta or keyword rewrites are proposed for existing posts. The only exceptions are fact corrections (F4, F5), and the Tanka meta fix needs confirmation.
- R8 touches the homepage during the hero CTA test window (review 2026-11-03). Schedule it after the review or annotate the test.
