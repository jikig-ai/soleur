# Content Audit: soleur.ai — 2026-10-26

## Executive Summary

This audit re-checks every finding from the 2026-10-19 content audit against the current Eleventy source and reviews the 9 blog posts added since then.

**No prior finding is fully fixed.** Three are partly fixed:

- F9 (model claims): every core page now lists the same 5 self-hosted tools.
- F14 (publishing gap): 9 new posts.
- F19 (stale dates): the compare pages were re-dated.

Two prior findings got worse:

- **F11:** the getting-started self-hosted section now has install blocks for 5 tools, a 6-column command table, and a 170-word OpenCode paragraph about hooks and environment variables.
- **N1:** freshness dates moved a second time, to 2026-10-22, on 7 pages. The open claims underneath them did not change.

Two new problems are serious enough to rank P0:

1. **Seven blog posts dated in the future are already live.** The posts are dated 2026-10-27 to 2026-11-17. The Eleventy config has no future-date filter, and `deploy-docs.yml` builds on every push to `main`. So today the blog index opens with a card dated "November 17, 2026", and each post's `datePublished` JSON-LD gives a future date.
2. **The homepage hero now uses the developer register, which is a named revert trigger for the hero test under way.** The 2026-10-22 multi-tool copy put "coding harness" directly under the hero button. It also says Soleur "ships as a plugin" (a brand-guide Don't) and adds `/soleur:go` to the "How do I get started?" FAQ answer, which is FAQPage text. The brand guide's 2026-10-06 test note lists "hero copy drifts toward developer register" as a revert trigger. The test review is on 2026-11-03, 8 days from now.

The new blog posts are uneven:

- **"Before Your AI Team Takes a Recurring Job, It Answers Six Questions" (2026-11-04)** is the best example yet of the Blog note: it opens with the founder's problem and gives them a checklist they can use.
- **The 8-post "agentic verification" cluster** has strong sourcing and specificity: a cited Addy Osmani checklist, and concrete counts (102 checks, 56/46, 32 pages, 17 review passes). Its openings are re-angled to the founder well. But **7 of its 8 titles and meta descriptions name the mechanism** ("property test", "flaky test", "migration", "schema", "guardrails", "repo"). Those are developer search queries the Blog note says not to target. The bodies use undefined terms such as "oracle", "idempotence", "negative control", "harness" and "P1". All 8 posts also show the wrong series box, because they declare a pillar they are not members of.

**Headline counts:** 2 P0, 9 P1, 11 P2, 11 P3 (33 total). Carried: 23 (2 worse, 3 partly fixed). New: 10.

**Top 3 actions:**

1. **Hide future-dated posts until their date (N6).** Add a `date <= now` filter to the blog collection and to permalinks, plus a daily scheduled rebuild. Or re-date the 7 posts to the dates they actually went live. Do this today.
2. **Take "harness", "plugin" and `/soleur:go` out of the homepage and pricing copy (N5), and annotate the hero test (#9588) with the 2026-10-22 copy change.** The change happened inside the measurement window, so it confounds the 2026-11-03 comparison.
3. **Once the date gate holds back the 7 future-dated verification posts, retitle them to founder problems before they publish (N7).** Keep the slugs so the hub post's links still work.

## Scope and Method

| Item | Detail |
|---|---|
| Live fetch | **Failed.** WebFetch on `https://soleur.ai` was blocked by the environment hook (`cron-containment: tool class not permitted: WebFetch`). Rendered HTML and live copy were not checked. The same thing happened on 2026-10-19. |
| Source audited | Local Eleventy source under `plugins/soleur/docs/`, read with Read, Grep and Glob. Template output (`{{ stats.* }}`, `page-freshness.njk`, `pillar-series.njk`) was worked out from the source, not from rendered pages. |
| Publish-state check | `eleventy.config.js` has no date filter on collections or permalinks. `plugins/soleur/docs/blog/blog.json` sets `permalink: blog/{{ page.fileSlug }}/index.html` for every post. `.github/workflows/deploy-docs.yml` builds with `npx @11ty/eleventy` on push to `plugins/soleur/docs/**`, with no schedule. A post committed to `main` is therefore live at the next docs deploy, whatever its `date`. |
| Pages sampled (18 + 9 posts) | `/`, `/pricing/`, `/getting-started/`, `/agents/`, `/skills/`, `/vision/`, `/about/`, `/community/`, `/blog/`, `/ai-agents-for-solo-founders/`, `/company-as-a-service/`, `/ai-cmo/`, `/ai-cto/` (new in sample), `/solo-founder-ai-stack/` (new in sample), `/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/` (frontmatter only), `/known-external-tools/`, `_includes/page-freshness.njk`, `_includes/pillar-series.njk` with `_data/pillars.js`. |
| New posts (all read in full) | `2026-10-23-agentic-verification-checklist-shipped`, `2026-10-27-audited-102-guardrails-four-portable`, `2026-10-29-property-test-cannot-fail-teaches-nothing`, `2026-11-03-first-property-test-found-real-bug`, `2026-11-04-before-your-ai-team-takes-a-recurring-job`, `2026-11-05-map-that-cant-drift`, `2026-11-10-test-the-migration-not-just-the-schema`, `2026-11-12-map-that-only-records-what-the-agent-saw`, `2026-11-17-flaky-test-passed-on-retry-quarantine`. |
| Grep sweeps | Competitor revenue (`annual recurring revenue`, `$2B`, `reached $`), department counts (`nine`, `9 hats`, `9 departments`), "trained", "model-agnostic", "harness", "plugin", salary figures, CaaS superlatives, and the frontmatter of every sampled page. |
| Brand guide | Read `knowledge-base/marketing/brand-guide.md` in full: Identity, Voice (Do's and Don'ts, Audience Voice Profiles, Value Proposition Framings), Channel Notes > Website / Landing Page (including the 2026-10-06 hero CTA test notes, #9579 and #9588), and Channel Notes > Blog. |
| Not covered | Legal pages, changelog, `/agentic-engineering/`, `/claude-code-plugins/`, `/glossary/` (one line only), `/goal-primitive/`, individual agent and skill cards, and full re-reads of posts from before 2026-10-19. This is a sample. |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, llms.txt (owned by seo-aeo-analyst). JSON-LD text is assessed only for what it says. This is a content audit, not an AEO audit, so the SAP and 8-component AEO scorecards are not produced. GEO-relevant observations are noted inline. |

## Delta since 2026-10-19

Status key: **FIXED**, **PARTLY FIXED**, **STILL OPEN**, **WORSE** (still open and the evidence has grown).

### Prior P1 and P2 findings

| Prior ID | Prior P | Finding | Issue | Status 2026-10-26 | Evidence (current source) |
|---|---|---|---|---|---|
| F11 | P1 | The homepage's main button lands in a terminal manual | #2669 | **WORSE** | `pages/getting-started.njk:47` label is now "Source-available. Install in your own harness." `:54-110` has 5 install blocks (Claude Code, Grok Build, Codex, Devin CLI, OpenCode). `:99` and `:108` contain `bun` on `PATH`, `~/.config/opencode/soleur/`, "code-mode `execute`", "Stop hook", `<promise>DONE</promise>` and `CLAUDE_PLUGIN_ROOT`. `:111-156` is a 6-column command table. The ~120-word update callout (`:164`) is unchanged. `:168` still says "for software development". The homepage hero button still lands here (`index.njk:20`). |
| F3 | P1 | Getting-started title says install; hero says waitlist; FAQ says "Nothing to install" | #9107 | **STILL OPEN** (slightly worse) | `:3` "Install Your AI Organization in Two Commands" is now true for 1 of the 5 listed tools. `:18` hero button is still the waitlist. `:267` and JSON-LD `:307` still open with "Nothing to install." |
| F1 | P1 | Blog index targets developer queries | #9104 | **STILL OPEN** | `pages/blog.njk:3-4` still says "Agentic Engineering" and "engineering deep dives". `:11` H1 is still "Blog". |
| F2 | P1 | Founder posts filed under engineering and CaaS labels | #9105 | **STILL OPEN** (affects 9 more posts) | `pages/blog.njk:41-46` is unchanged. None of the 9 new posts has the `CaaS`, `ai-agents`, `comparison` or `case-study` tag, so all 9 fall into "Engineering Deep Dives" (`:117`), including the founder-problem post on recurring jobs. |
| F4 | P1 | Competitor revenue stated as fact | #7179 | **STILL OPEN** | `pages/ai-agents-for-solo-founders.njk:33`; `pages/company-as-a-service.njk:35,41`; `pages/compare-soleur-vs-cursor.njk:30` ("roughly 1 billion dollars in annual recurring revenue", **re-dated 2026-10-22** with this sentence unchanged); `blog/2026-03-24-ai-agents-for-solo-founders.md:64`; `blog/2026-03-19-soleur-vs-cursor.md:105,140` ("Cursor's $2B+ ARR"). The Polsia post (`blog/2026-03-26-soleur-vs-polsia.md:123`) attributes its figures and complies. |
| F5 | P1 | "9 hats / nine departments" vs 8 | #8462 | **STILL OPEN** | `index.njk:221` and JSON-LD `:282` "wearing 9 hats who want to hand off 8"; `blog/2026-05-05-soleur-vs-tanka.md:5`; `blog/2026-04-21-soleur-vs-devin.md:44,52,78` (`:52` "Engineering is one of nine" sits next to `{{ stats.departments }}`); `blog/2026-04-21-one-person-billion-dollar-company.md:86`. |
| F7 | P1 | Homepage hero and meta lead with CaaS | #9112 | **STILL OPEN** | `index.njk:4,14,16,17`. |
| F6 | P1 | Skills title is brand-only; H1 is technical | #5601 | **STILL OPEN** | `pages/skills.njk:2` `title: Soleur Skills`, no `seoTitle`; `:13` H1 "Agentic Engineering Skills"; `:24` still opens on the Karpathy link and MCP, and now also lists 5 tool names. |
| F9 | P2 | Model-support claims disagree | #9500, #6376 | **PARTLY FIXED** | The homepage (`index.njk:21,41`), pricing (`:303`), getting-started (`:37,50`), compare-cursor (`:32`) and the vision FAQ (`pages/vision.njk:197`) now agree: self-hosted runs on 5 tools with whichever provider each is set up for, and hosted uses Anthropic. The vision FAQ now separates "the implementation" from "the vision". **Still open:** the `pages/vision.njk:87` card is in the present tense ("Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy."), which contradicts the page's own FAQ. The `:79` card ("Plug in your own API keys (Anthropic, OpenAI, Gemini, Llama…)") does not match hosted being Anthropic-only. |
| F10 | P2 | Pricing scenario says "ready to sign" | #9111 | **STILL OPEN** | `pages/pricing.njk:196`. |
| F12 | P2 | Agents described as "trained" | #6378 | **STILL OPEN** | `pages/agents.njk:27,93,125`. `:93` and `:125` also still say "within Claude Code" only, which now disagrees with the 5-tool copy elsewhere. |
| F8 | P2 | AI CMO cost figure inconsistent | #9499 | **STILL OPEN** | `pages/ai-cmo.njk:3` "$240K", `:4` "$290K", `:61` "~$294,000". `/ai-cto/` shows how to do it: $280K is used consistently and sourced to Built In. |
| F13 | P2 | Community title and H1 generic | #6377 | **STILL OPEN** | `pages/community.njk:3,11`. |
| F14 | P2 | Founder-blog publishing gap | #8466 | **PARTLY FIXED** | 9 posts in the window, against 0 the week before. Only 1 of the 9 (2026-11-04) is a founder problem from title to call to action. None of the planned gap pieces (contracts, AI marketing, hire-or-delegate, self-hosted vs hosted) has been published. See F14 below. |
| N1 | P2 | Freshness dates moved without fixing the facts | — | **WORSE** | A second date bump, to 2026-10-22: `index.njk:7-8`, `pages/pricing.njk:9-10`, `pages/getting-started.njk:7-8`, `pages/vision.njk:6-7`, `pages/about.njk:6-7`, `pages/compare-soleur-vs-cursor.njk:9-10`, `pages/compare-soleur-vs-devin.njk:9-10`. The claims under them are unchanged: "9 hats" (F5), "ready to sign" (F10), GPT-4o routing (F9), Cursor ARR (F4), "70%" (F17). The getting-started bump has a real cause (OpenCode was added, `verified: 2026-10-22` comment at `:101`). The other bumps look like sweep side-effects. |

### Prior P3 findings

| Prior ID | Finding | Status | Evidence |
|---|---|---|---|
| F15 | About title, filler subtext, "agentic engineering" blog line | **STILL OPEN** | `pages/about.njk:2,13,36`. |
| F16 | Vision jargon and superlatives; CaaS origin claims disagree | **STILL OPEN** | `pages/vision.njk:26` ("infinite leverage"), `:29` ("one of the first model-agnostic orchestration engines"); `pages/glossary.njk:24` ("Soleur coined"); `pages/company-as-a-service.njk:174,270` ("a leading"). |
| F17 | Unsourced "70%"; "420+ PRs" on a general-register page | **STILL OPEN** | `pages/pricing.njk:291,331,389`; `pages/compare-soleur-vs-cursor.njk:26` ("the other 70 percent"). |
| F18 | "This Is the Way" label | **STILL OPEN** | `index.njk:70`. |
| F19 | Stale `last_updated` | **PARTLY FIXED** | Both compare pages are now 2026-10-22, though without a fact review (see N1). `pages/agents.njk:6` (2026-06-01) and `pages/skills.njk:7` (2026-06-15) remain. |
| N2 | "Running autonomously" contradicts the illustration | **STILL OPEN** (more pages) | `index.njk:82`. Also found at `pages/vision.njk:135`: "every department running autonomously on command". |
| N3 | Footer links to a developer troubleshooting page | **STILL OPEN** | `_data/site.json:75`; `pages/known-external-tools.md:3` ("footguns", "evidence literals"). |
| N4 | Pricing waitlist H2 says the product is ready | **STILL OPEN** | `pages/pricing.njk:27` "Your AI organization is ready." |

### Other plan items (from the AEO audit, but about content)

| Plan # | Finding | Issue | Status |
|---|---|---|---|
| 3 | `/vision/` presents the multi-provider roadmap as shipped | #6376 | **PARTLY FIXED** (FAQ fixed; cards at `:79`, `:87` still present tense) |
| 14 | CaaS pillar superlatives | #6085 | **STILL OPEN** |
| 18 | Conflicting claims about who coined CaaS | #9501 | **STILL OPEN** |

**Prior findings fully fixed: none.**

**Good changes since 2026-10-19 that were not tied to a finding:**

- Self-hosted support is described the same way on the homepage, pricing, getting-started, compare-cursor and the vision FAQ. That removes the Claude-only vs model-agnostic contradiction at the heart of F9.
- The vision FAQ "Is Soleur model-agnostic?" (`pages/vision.njk:197`) now separates what ships today from the roadmap. This is the right model for the vision cards.
- The new post on recurring jobs (2026-11-04) meets every clause of the Blog note: it opens with the founder's own week, gives a founder checklist, ends with a plain call to action, and links the technical write-up once at the end.
- The verification hub (2026-10-23) cites an external primary source (Osmani) and uses specific numbers throughout. Both raise AI-citation likelihood (GEO: source citations > statistics).

## Per-Page Analysis

### 1. Homepage (`/`, `plugins/soleur/docs/index.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" / "Stop hiring. Start delegating." |
| Meta description | "Company-as-a-Service for solo founders. AI agents across 8 departments…" (F7) |
| Detected keywords | AI agents for solo founders, Company-as-a-Service, self-hosted, Claude Code, Grok Build, Codex, Devin CLI, OpenCode, coding harness, plugin, MCP, Soleur vs Cursor/Copilot |
| Keyword alignment | **Strong title; weak meta and hero.** CaaS appears 4 times before the stats strip (F7). New since 2026-10-19: 5 developer tool names and "harness" appear 9 times on the page, 3 of them in FAQPage text (N5). |
| Search intent | Commercial with some informational. The FAQ matches both. |
| Readability | **Worse in the hero.** The line under the main button is now "Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode; you pay for your own model usage." (`:21`). A founder who does not code meets 6 unexplained terms before they learn what they would get. The compare section and FAQ say "Soleur ships as a plugin for your own coding harness" (`:189`, `:209`), which breaks the brand Don't on "plugin". The "How do I get started?" answer starts "Get the self-hosted version and run `/soleur:go` inside your own harness" (`:225`). Still open: "9 hats" (F5), "running autonomously" (N2), "This Is the Way" (F18). |
| Brand guide note | The 2026-10-06 hero CTA test is under way (review 2026-11-03). Its revert triggers include "hero copy drifts toward developer register". `:21` is that drift, and it went live on or about 2026-10-22, inside the measurement window (N5). |

### 2. Pricing (`/pricing/`, `pages/pricing.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." |
| Keyword alignment | Strong. |
| Search intent | Transactional. Matches. |
| Readability | Mostly strong. **New:** the "Is there a free version?" FAQ says "You run it inside your own harness" (`:303`, JSON-LD `:355`), and `:299` and `:347` also use "harness". Still open: "ready to sign" (F10), "other 70%" (F17), "420+ PRs" (F17), "Your AI organization is ready." (N4). Re-dated 2026-10-22 with none of these fixed (N1). |

### 3. Getting Started (`/getting-started/`, `pages/getting-started.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Get Started with Soleur — Install Your AI Organization in Two Commands" / "The AI that already knows your business." |
| Detected keywords | install Soleur, Claude Code plugin, Grok Build, Codex plugin, Devin CLI, OpenCode, self-hosted, waitlist |
| Keyword alignment | **Misaligned** (F3). "Two Commands" is now accurate for 1 of 5 tools. |
| Search intent | Split three ways (install, waitlist, self-hosted anchor from the homepage). |
| Readability | **Worse than on 2026-10-19 for the general register** (F11). From the `#self-hosted` anchor, a founder sees 5 install blocks, an OpenCode paragraph about hooks, `PATH`, `CLAUDE_PLUGIN_ROOT` and `<promise>DONE</promise>`, a 6-column command table, 2 callouts full of commands, and "a structured 6-step workflow for software development". The definition paragraph (`:32`) and citations (`:33-39`) are still good. |

### 4. Agents (`/agents/`, `pages/agents.njk`)

| Field | Assessment |
|---|---|
| Keyword alignment | Strong. |
| Search intent | Informational. Matches. |
| Readability | Good. Still says "trained" (F12). The FAQ and JSON-LD still say agents run "within Claude Code" only (`:93`, `:125`), which disagrees with the 5-tool copy elsewhere. `last_updated` 2026-06-01 (F19). |

### 5. Skills (`/skills/`, `pages/skills.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Skills" (no `seoTitle`) / "Agentic Engineering Skills" |
| Keyword alignment | Weak (F6). |
| Readability | More technical than on 2026-10-19. The first sentence (`:24`) now carries a Karpathy link, 5 tool names and MCP before it says what a skill does for the founder. |

### 6. Vision (`/vision/`, `pages/vision.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Vision: Company-as-a-Service" / "The Soleur Vision: Company-as-a-Service for the Solo Founder" |
| Keyword alignment | Adequate; overlaps the `/company-as-a-service/` pillar. |
| Readability / accuracy | **Mixed.** The FAQ answer at `:197` is now accurate and well framed. But the H2 "Model-Agnostic Architecture" (`:70`) and the cards at `:79` and `:87` still describe automatic per-task model routing and "GPT-4o for strategy" in the present tense. By 2026-10 "GPT-4o" is also a dated model name. "Running autonomously on command" (`:135`, N2) and "infinite leverage" (`:26`, F16) remain. Re-dated 2026-10-22 (N1). |

### 7. About (`/about/`, `pages/about.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "About Jean Deruelle" / "About Soleur and its founder, Jean Deruelle" |
| Readability | Good. Still open: "The founder behind Soleur." (`:13`) and "Jean writes about agentic engineering…" (`:36`) (F15). Re-dated 2026-10-22 without changes to either (N1). |

### 8. Community (`/community/`, `pages/community.njk`)

Unchanged. Title "Community — Soleur", H1 "Community" (F13).

### 9. Blog Index (`/blog/`, `pages/blog.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "Blog" |
| Keyword alignment | Misaligned with the Blog note (F1). |
| IA | **Categories still broken** (F2). All 9 new posts land in "Engineering Deep Dives". Listings sort newest first (`collections.blog \| reverse`), so the first card a visitor sees today is dated **November 17, 2026** (N6). |

### 10. AI Agents for Solo Founders (`pages/ai-agents-for-solo-founders.njk`)

Strong keyword alignment and intent match. Still breaks the competitor-revenue rule at `:33` (F4).

### 11. Company-as-a-Service (`pages/company-as-a-service.njk`)

Strong for "Company-as-a-Service (CaaS)". F4 (`:35`, `:41`) and "a leading company-as-a-service platform" (`:174`, `:270`; F16) remain.

### 12. AI CMO (`pages/ai-cmo.njk`)

Strong keyword ("AI CMO"). Three salary figures remain (F8).

### 13. AI CTO (`pages/ai-cto.njk`), new in sample

| Field | Assessment |
|---|---|
| Title / H1 | "AI CTO: What an AI Engineering Leader Actually Does (2026) \| Soleur" / same |
| Keyword alignment | Strong ("AI CTO"). Commercial-investigation intent. Matches. |
| Readability / GEO | **Strong.** The bold first-sentence definition is quotable as it stands. Salary figures are sourced (Built In, PayScale) and consistent ($280K throughout). This is the template F8 should follow. |
| Issues | The visible section label "Role Cluster" (`:13`) is internal SEO vocabulary shown to readers. There is no `date` or `last_updated`, although the title says "(2026)" (N13). |

### 14. Solo Founder AI Stack (`pages/solo-founder-ai-stack.njk`), new in sample

| Field | Assessment |
|---|---|
| Title / H1 | "Solo Founder AI Stack: The 7 Tools to Replace a 20-Person Team (2026) \| Soleur" / "The Solo Founder AI Stack: 7 Tools to Replace a 20-Person Team" |
| Keyword alignment | Strong for "solo founder AI stack". Commercial-investigation intent. |
| Readability / GEO | Strong. Quotable definition, a Carta statistic with its source, and Altman/Every/TechCrunch/a16z citations. "20-Person Team" in the title has no source on the page (P3, part of N13). The "Role Cluster" label and missing date also apply here (N13). |

### 15. Soleur vs Cursor (`pages/compare-soleur-vs-cursor.njk`)

Strong keyword alignment. Re-dated 2026-10-22, but `:30` still states Cursor's ARR as fact (F4, N1). The 5-tool description at `:32` is now consistent with the rest of the site.

### 16. Known external tools / footer

Unchanged (N3).

### 17. New blog posts (since 2026-10-19)

The Blog note asks for: the founder's problem in the title, SEO title, meta and first paragraph; no mechanism-led titles; founder search queries; no jargon; a non-technical call to action; and a technical link only once, at the end. All 9 posts were published after the 2026-09-25 note, so the note applies in full.

| Post (date) | Title / seoTitle | Target query detected | Intent | Founder-problem title? | Opening | Body jargon (undefined) | CTA | Verdict |
|---|---|---|---|---|---|---|---|---|
| Agentic verification checklist (10-23, **hub**) | "A Checklist for Trusting AI Work Was Just Published. We Shipped All of It." / "The Checklist for Trusting AI Work, Shipped in 4 Days" | agentic verification, trust AI work | Informational | Partly ("trusting AI work" is founder language; "shipped" is our story) | **Strong**: "what if it's wrong?" in paragraph 1 | Low. Property-based testing and differential testing are defined in the same sentence. | Waitlist | Good. Fix facts only (N12). |
| 102 guardrails (10-27) | "We Audited 102 Guardrails. Only Four Belong in Every Repository." / "…in Every Repo" | guardrails, repo | Informational (developer) | **No**: our audit, "Repository/Repo" | Good | "repository", "main line", "branch" (`:55`), "secrets scanner" | Waitlist | Retitle (N7) |
| Property test cannot fail (10-29) | "A Property Test That Cannot Fail Teaches Nothing" | property test | Informational (developer) | **No**: mechanism | Good | "tautology", "assertion", "self-oracles" (link URL), "what the ledger calls a P1… a P2" (`:59`) | Waitlist | Retitle (N7) |
| First property test found a bug (11-03) | "The First Property Test We Wrote Found a Real Bug" | property test, bug | Informational (developer) | **No**: mechanism and our bug | Good | "harness" in an H2 (`:47`) and in the meta, "database's own language", "random-number source… older versions" | Waitlist | Retitle (N7) |
| Recurring job (11-04) | "Before Your AI Team Takes a Recurring Job, It Answers Six Questions" (no seoTitle) | manage business automations | Informational | **Yes** | **Best on site**: "Somewhere in your business, a machine does something on a schedule every night." | "Idempotence is a property." (`:44`), "an API call" (`:52`) | "Try Soleur" | Model post. Fix FAQ (N9), 2 terms (N11), series box (N8). |
| Map that can't drift (11-05) | "A Map That Can't Drift" / "…The Feature Map That Guards Itself" | feature map | Informational (no clear query) | Weak (the "map" metaphor is undefined in the title) | **Strong**: onboarding tours and help articles that drift | "file-listing pattern", "census", link text "three parser defects" (`:75`) | Waitlist | Retitle (N7) |
| Test the migration (11-10) | "Test the Migration, Not Just the Schema" | migration testing, schema | Informational (developer) | **No**: "migration", "schema" | Good: replacing something that works | "oracle" (`:36`), "normalize", "negative control" (`:68`), "modulo that ledger" (`:96`, FAQPage text) | Waitlist | Retitle (N7) |
| Map the agent saw (11-12) | "The Map That Only Records What the Agent Saw" | — | Informational (no clear query) | Weak ("agent" without definition) | Good: "That is not testing. It is tourism." | "Presence, not conformance" (`:47`), "reachability check", "negative control" | Waitlist | Retitle (N7) |
| Flaky test (11-17) | "A Flaky Test Passed on Retry and the Loop Called It Fixed" | flaky test | Informational (developer) | **No**: "flaky test", "loop" | Good | "fix loop", "gone-in-circles detector" (`:35`), "tracker ticket", "suite", the six-axis list (seeds, clocks, state isolation, contention) | Waitlist | Retitle (N7) |

**Cluster architecture:** the hub links to every spoke, and every spoke links back to the hub and to at least one sibling. That satisfies the pillar/cluster rule. But the hub is not registered as a pillar in `_data/pillars.js`. All 8 posts declare `pillar: billion-dollar-solo-founder`, so each renders the "Part of The Billion-Dollar Solo Founder Stack series" box. That box lists 2 unrelated posts and does not list the post being read (N8). The recurring-job post declares `pillar: agentic-solo-founder` and is not a member of that series either.

**Searchable vs shareable:** the hub and the 102-guardrails audit are shareable (original data, an opinion on a widely read checklist). The 6 spokes are searchable, but they are aimed at developer queries. The recurring-job post is searchable for founder queries.

## Keyword Research: New Cluster vs Founder Queries

Relevance is judged against the brand guide's blog reader: a non-technical solo founder.

| Keyword / query | Intent | Relevance to blog ICP | Currently targeted by | Notes |
|---|---|---|---|---|
| agentic verification | Informational | Low (developer and AI-engineering term, coined by Osmani) | Hub | Fine to keep in the hub body. It is a growing term for the technical audience and for AI citations. Not a founder query. |
| property-based testing / property test | Informational | Low | 10-29, 11-03 | A developer query. The Blog note says not to target these. |
| flaky tests | Informational | Low | 11-17 | Developer query. |
| database migration testing / schema | Informational | Low | 11-10 | Developer query. |
| guardrails for AI code / repo | Informational | Low-medium | 10-27 | Developer query. "Is AI-written code safe" is the founder version. |
| how to check AI work / can I trust AI output | Informational | **High** | Hub (partly, in the title only) | The founder's form of the whole cluster's question. Matches the #1 objection in the brand guide (8/10 personas). |
| AI says it fixed it but didn't | Informational | **High** | None | The founder's experience of the flaky-test story. |
| is AI-generated code safe to ship | Commercial / informational | **High** for founders who build | None | The founder's form of 10-27. |
| keep help docs up to date with product | Informational | Medium-high | None | The founder's form of 11-05. The post's own opening already uses this framing. |
| how to safely replace software that works / rewrite without breaking things | Informational | Medium | None | The founder's form of 11-10. |
| what automations are running in my business / audit business automations | Informational | **High** | 11-04 (FAQ JSON-LD only) | Make it visible (N9) and add a `seoTitle`. |
| AI hallucination / AI made it up | Informational | **High** | None | The founder's form of 11-12 ("a map of places it never visited"). |

## Findings

Priority definitions:

- **P0:** wrong or misleading information live now on a primary surface, or a pre-declared revert trigger already met. Fix immediately.
- **P1:** blocks discoverability or conversion for the ICP.
- **P2:** accuracy or alignment gap that weakens ranking or trust.
- **P3:** polish.

| ID | P | Title | Affected URL(s) | Evidence | Fix | New / Carried |
|---|---|---|---|---|---|---|
| N6 | **P0** | Future-dated posts are live | `/blog/`, `/blog/audited-102-guardrails-four-portable/`, `/blog/property-test-cannot-fail-teaches-nothing/`, `/blog/first-property-test-found-real-bug/`, `/blog/before-your-ai-team-takes-a-recurring-job/`, `/blog/map-that-cant-drift/`, `/blog/test-the-migration-not-just-the-schema/`, `/blog/map-that-only-records-what-the-agent-saw/`, `/blog/flaky-test-passed-on-retry-quarantine/` | 7 posts are dated 2026-10-27 to 2026-11-17 (today is 2026-10-26). `eleventy.config.js` has no date filter. `blog.json` gives every post a permalink. `deploy-docs.yml` builds on push to `main`. `blog-post.njk:18` writes `datePublished` from `date`. The blog index sorts newest first, so the first card reads "November 17, 2026". The 10-27 post says "the build log we published last week", which is accurate only on its stated date. | Either (a) add a publish gate: exclude `date > now` from `collections.blog`, set `permalink: false` and `eleventyExcludeFromCollections` for future posts in `blog.json` computed data, and add a daily `schedule:` trigger to `deploy-docs.yml` so posts appear on their date; or (b) re-date the 7 posts to the date they actually went live. (a) keeps the editorial calendar. Also check that the RSS feed (`/blog/feed.xml`) and the sitemap use the same filter. | **New** |
| N5 | **P0** | Homepage and pricing copy uses developer register (hero-test revert trigger) | `/`, `/pricing/` | `index.njk:21` "Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode"; `:189` and `:209` "Soleur ships as a plugin for your own coding harness"; `:225` "run `/soleur:go` inside your own harness"; FAQPage JSON-LD `:258`, `:274`, `:290`; `pages/pricing.njk:299,303,347,355`. Brand guide: "hero copy drifts toward developer register" is a revert trigger for the test under way (#9579, #9588; review 2026-11-03). "Plugin" in public copy is a Don't. The general register requires every term to be defined in the same sentence. | Rewrite per R18. Annotate #9588 with the 2026-10-22 copy change as a confound in the before/after window. Keep the full tool list on `/getting-started/` only. | **New** |
| F11 | **P1** | The homepage's main button lands in a terminal manual | `/getting-started/#self-hosted` | See Delta. There are now 5 install blocks, an OpenCode internals paragraph (`:108`), a 6-column command table and 2 command callouts. | R1, R2 (updated). Put a plain-language "What you need" paragraph first. Fold the per-tool blocks into a collapsed "Setup by tool" section, with Claude Code open by default. Move the OpenCode capability caveats and the update callout to the README or the per-tool guides. | Carried (#2669), **worse** |
| F3 | **P1** | Getting-started title says install; hero says waitlist; FAQ says "Nothing to install" | `/getting-started/` | `:3-4`, `:18`, `:267`, `:307` | R3 (updated for 5 tools). | Carried (#9107) |
| N7 | **P1** | New verification posts target developer queries in titles and meta | 7 spoke URLs listed under N6 | 6 of the 7 titles name the mechanism or our own work: "Property Test" ×2, "Flaky Test", "Migration… Schema", "102 Guardrails… Repository". 2 more use undefined metaphors: "A Map That Can't Drift", "What the Agent Saw". This breaks Blog note > Open with their problem and Blog note > Search ("not developer queries"). See the keyword table. | If N6 option (a) is taken, these 7 posts are unpublished until their dates, so retitle them now (R20) and keep the slugs so the hub's links still resolve. If the posts are treated as already published, the scope rule allows fact fixes only. Then record the decision and apply R20 to the next cluster instead. | **New** |
| F1 | **P1** | Blog index targets developer queries | `/blog/` | `pages/blog.njk:3-4,11` | R4. | Carried (#9104) |
| F2 | **P1** | Founder posts filed under engineering and CaaS labels | `/blog/` | `pages/blog.njk:41-130`; all 9 new posts land in "Engineering Deep Dives" | R5. Give the verification cluster its own category or a "Trusting AI Work" heading. | Carried (#9105), more posts affected |
| F4 | **P1** | Competitor revenue stated as fact | `/ai-agents-for-solo-founders/`, `/company-as-a-service/`, `/compare/soleur-vs-cursor/`, `/blog/ai-agents-for-solo-founders/`, `/blog/soleur-vs-cursor/` | See Delta | R6. | Carried (#7179) |
| F5 | **P1** | "9 hats / nine departments" vs 8 | `/`, `/blog/soleur-vs-tanka/`, `/blog/soleur-vs-devin/`, `/blog/one-person-billion-dollar-company/` | See Delta; `blog/2026-04-21-soleur-vs-devin.md:52` added to the evidence | R7. Also change `:52` "Engineering is one of nine" to "one of eight". | Carried (#8462) |
| F7 | **P1** | Homepage hero and meta lead with CaaS | `/` | `index.njk:4,14,16,17` | R8 (after the 2026-11-03 review). | Carried (#9112) |
| F6 | **P1** | Skills title is brand-only; H1 and opening are technical | `/skills/` | `pages/skills.njk:2,13,24` | R9. | Carried (#5601) |
| F9 | **P2** | Vision cards present the model-routing roadmap as shipped | `/vision/` | `pages/vision.njk:70,79,87` contradict the page's own FAQ at `:197` | R10 (narrowed to the vision cards; the shared summary at `page-freshness.njk:26` is now acceptable, see R10 note). | Carried (#9500, #6376), **partly fixed** |
| F10 | **P2** | Pricing scenario says "ready to sign" | `/pricing/` | `:196` | R11. | Carried (#9111) |
| F12 | **P2** | Agents described as "trained"; FAQ says Claude Code only | `/agents/` | `:27,93,125` | R13 (updated). | Carried (#6378) |
| F8 | **P2** | AI CMO cost figure inconsistent | `/ai-cmo/` | `:3,4,61` | R14. Follow the `/ai-cto/` pattern. | Carried (#9499) |
| F13 | **P2** | Community title and H1 generic | `/community/` | `:3,11` | R15. | Carried (#6377) |
| F14 | **P2** | Founder-problem posts from the gap plan are still unpublished | `/blog/` | 9 posts shipped. 1 is founder-first. 0 of the 5 planned gap pieces are out. | Schedule the 2 P1 gap pieces (contracts, AI marketing) before the next verification spoke. See Content Gap Notes. | Carried (#8466), **partly fixed** |
| N1 | **P2** | Freshness dates bumped again without a fact review | `/`, `/pricing/`, `/getting-started/`, `/vision/`, `/about/`, `/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/` | See Delta | Revert the bumps that had no content change, or fix the listed facts first. Add a pre-bump checklist to the docs PR template: "open content-audit findings on this page are resolved or listed". | Carried, **worse** |
| N8 | **P2** | Verification posts show the wrong series box | All 8 verification posts; `/blog/before-your-ai-team-takes-a-recurring-job/` | `pillar: billion-dollar-solo-founder` in all 8. `_data/pillars.js:11-19` lists only `/blog/billion-dollar-solo-founder-stack/` and `/blog/one-person-billion-dollar-company/`. `pillar-series.njk` renders that list, so the current post is never marked "(you are here)". The 11-04 post declares `agentic-solo-founder` and is not in its member list (`:39-55`). | R21: add a `trusting-ai-work` pillar with the 10-23 hub as `pillar` and the 7 spokes as `cluster`. Add 11-04 to `agentic-solo-founder`. | **New** |
| N9 | **P2** | Recurring-job post has an empty visible FAQ | `/blog/before-your-ai-team-takes-a-recurring-job/` | `:77` "## Frequently asked questions" is followed directly by the JSON-LD (`:79-102`). The 2 questions exist only in machine-readable form, so readers see an empty heading. | R22: render the 2 Q&As as visible `###` sections above the script. Add a `seoTitle`. | **New** |
| N10 | **P2** | The same lesson is repeated across 6 posts | Hub and 5 spokes (10-27, 10-29, 11-03, 11-05, 11-17) | "A check that cannot fail" / "decoration wearing the costume of coverage" / "verify the verifiers" is the closing thesis of 6 posts. Near-duplicate FAQ questions: "Can an automated check itself be wrong?" (10-27), "Why did the checker need checking?" (11-05), "What does it mean for a test to be unable to fail?" (10-29). Answer engines will pick one URL and treat the others as duplicates. | Give each spoke one distinct founder takeaway (R20 column "Distinct takeaway"). Keep "verify the verifiers" as the hub's thesis only. Cut each spoke's repeated "The real lesson" section to one sentence that links to the hub. | **New** |
| N11 | **P2** | Undefined technical terms in new post bodies and FAQ text | 10-27, 10-29, 11-03, 11-04, 11-05, 11-10, 11-12, 11-17 | See the "Body jargon" column above. FAQPage text includes "modulo that ledger" (11-10 `:96`, `:124`). Blog note > Jargon limits: "a reader who has never opened a terminal can repeat each paragraph back." | R23 substitution table. | **New** |
| F15 | P3 | About title, filler subtext, "agentic engineering" blog line | `/about/` | `:2,13,36` | R16. | Carried |
| F16 | P3 | Vision jargon and superlatives; CaaS origin claims disagree | `/vision/`, `/glossary/`, `/company-as-a-service/` | See Delta | R10 (`:29`), and pick one origin statement for CaaS. | Carried (#9501, #6085) |
| F17 | P3 | Unsourced "70%"; "420+ PRs" on pricing | `/pricing/`, `/ai-agents-for-solo-founders/`, `/compare/soleur-vs-cursor/` | See Delta | Source the 70% or replace it with "everything that isn't code". Replace "420+ PRs" with "every department". | Carried (#9111) |
| F18 | P3 | "This Is the Way" label | `/` | `index.njk:70` | Use "The Problem". | Carried |
| F19 | P3 | Stale `last_updated` on agents and skills | `/agents/`, `/skills/` | `agents.njk:6`, `skills.njk:7` | Re-date after F6 and F12 are fixed. | Carried, **partly fixed** |
| N2 | P3 | "Running autonomously" contradicts the trust copy | `/`, `/vision/` | `index.njk:82`; `pages/vision.njk:135` (newly found) | R12. Apply to both. | Carried, more pages |
| N3 | P3 | Footer links to a developer troubleshooting page | Sitewide | `_data/site.json:75` | R17. | Carried |
| N4 | P3 | Pricing waitlist H2 says the product is ready | `/pricing/` | `:27` | R11. | Carried |
| N12 | P3 | Hub post: time-relative title, unverifiable superlative, one overclaim | `/blog/agentic-verification-checklist-shipped/` | `:2` "Was Just Published" will read as stale within weeks. `:19` "among the most followed in the industry" cannot be checked. `:86` "Every row of the checklist arrived with at least one way the verifier itself could lie" contradicts `:35` (3 of 7 rows were already in place and not shipped in this work). | Fact fixes only, as the scope rule allows: `:19` becomes "an engineering leader at Google who writes widely about AI-assisted development". If that affiliation cannot be confirmed, use "who writes widely about AI-assisted development". `:86` becomes "Every row we shipped arrived with…". Keep the title (scope rule), but treat "Just" titles as a pattern to avoid in future. | **New** |
| N13 | P3 | Role-cluster pages show an internal label and have no date | `/ai-cto/`, `/solo-founder-ai-stack/` | `ai-cto.njk:13`, `solo-founder-ai-stack.njk:13` "Role Cluster". Neither page has `date` or `last_updated`, although both titles say "(2026)". "20-Person Team" is unsourced. | Change the label to "AI Leadership" or "Founder Guide". Add `date` and `last_updated`. Source or soften "20-person". | **New** |
| N14 | P3 | "Third time" is used for two different events | `/blog/first-property-test-found-real-bug/` | `:39` "the third time the same cleanup had drifted" and `:43` "the third time the two implementations… had drifted apart" | Fact clarification: keep one count and say which drift it refers to. | **New** |

## Rewrite Suggestions

All rewrites use the **general register**, the brand guide default for the website and blog. They lead with the outcome, keep the trust language ("you approve"), and avoid "AI-powered", "just/simply", "copilot/assistant", "plugin" outside literal commands, stated competitor revenue, and exact counts in static prose. None of them changes the homepage hero **button**, which is under test until 2026-11-03.

### Carried rewrites (unchanged from 2026-10-19 unless noted)

R4 (blog title/meta/H1), R5 (blog categories), R6 (competitor revenue), R7 (counts), R8 (homepage tagline/meta, after 2026-11-03), R9 (skills), R11 (pricing), R12 ("Agents Execute" card), R14 (AI CMO), R15 (community), R16 (about) and R17 (footer) still apply as written in `knowledge-base/marketing/audits/soleur-ai/2026-10-19-content-audit.md`. Updated versions follow.

### R1 (updated). `/getting-started/#self-hosted` opening (fixes F11)

- **Current label (`:47`):** `Source-available. Install in your own harness.`
- **Suggested:** `Source-available. Runs on your own computer.`
- **Current first paragraph (`:50`):** `Prefer to run it yourself? Soleur is source-available and runs self-hosted on Claude Code, Grok Build, Codex, Devin CLI, and OpenCode today …`
- **Suggested:** `Run your AI team today, on your own computer. Self-hosted Soleur works inside an AI workspace you may already use, such as Claude Code (Anthropic's), Codex (OpenAI's) or one of three others, and you pay that provider for what you use. Your company's memory stays as plain files you own. If you would rather not set anything up, join the waitlist for the hosted version.`
- **Structure:** follow this with a collapsed `Setup by tool` block. Open Claude Code by default, collapse the other 4, and move the OpenCode capability caveats (`:108`) into its linked guide.
- **Rationale:** says what the founder gets and what it costs before any command. Each tool name comes with a plain gloss. A non-technical founder has a clear way out, which protects the cohort-mix goal in the hero test note.

### R2 (unchanged). Update callout and command FAQ (fixes F11)

Replace the `:164` callout with: `**Updating later?** Run both update commands; the first one alone does not update what you run. Full steps are in the [README](<GitHub README anchor>).` Rewrite the command FAQ (`:339`) as "Do I have to pick a workflow myself?" / "No. Describe what you need in plain words and Soleur picks the right workflow."

### R3 (updated). `/getting-started/` title, meta, first FAQ (fixes F3)

- **SEO title:** `Get Started with Soleur — Run Your AI Team Today or Join the Hosted Waitlist`
- **Meta:** `Two ways to start: run the free self-hosted version on your own computer today, or join the waitlist for hosted Soleur. Your AI team for marketing, legal, finance and operations remembers your business.`
- **First FAQ answer (`:267`, `:307`):** `For the hosted version, nothing: it runs in your browser once your access opens. The self-hosted version runs on your own computer inside an AI workspace such as Claude Code or Codex. Setup takes two commands on Claude Code, and each other workspace has its own short guide.`

### R10 (narrowed). `/vision/` model cards (fixes F9, F16)

- **H2 (`:70`):** `Model-Agnostic Architecture` → `On the Roadmap: The Right Model for Each Job`
- **Card (`:87`):** `Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy. Local models for privacy-sensitive data. One orchestrator across every provider.` → `Today you choose the AI provider your workspace uses. Next, Soleur will pick the best model for each job: a coding model for engineering, a reasoning model for strategy, a local model for sensitive data.`
- **Card (`:79`):** add `Self-hosted today; hosted plans start with Anthropic.`
- **`:29`:** `one of the first model-agnostic orchestration engines` → `an orchestration engine built so the agents, not the model, carry your company's knowledge`
- **Note on `page-freshness.njk:26`:** with 5 self-hosted tools across providers, "model-agnostic" is now defensible for self-hosted. It is still jargon for the general register. Prefer `works with several AI providers` if this summary ever renders on general-register pages.

### R13 (updated). `/agents/` (fixes F12)

`Each Soleur agent is trained for a specific function` → `Each Soleur agent is built for one business function, with its own instructions, its own checks, and access to your company's shared memory`. In `:93` and `:125`, replace `within Claude Code` with `inside the AI workspace you run it in, or in the hosted version once it opens`.

### R18 (new). Homepage and pricing tool copy (fixes N5)

| Location | Current | Suggested |
|---|---|---|
| `index.njk:21` (hero note) | `Source-available. Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode; you pay for your own model usage.` | `Source-available. Runs on your own computer inside the AI workspace you already use. You pay your AI provider directly.` |
| `index.njk:41` | `Self-hosted runs inside your own Claude Code, Grok Build, Codex, Devin CLI, or OpenCode — signed in with …` | `Self-hosted works with Claude Code, Codex and three other AI workspaces, using your own AI plan or key. The getting started page has a short guide for each.` |
| `index.njk:189`, `:209` (+ JSON-LD) | `Soleur ships as a plugin for your own coding harness — … — and is built on the Model Context Protocol (MCP)…` | `Soleur runs inside the AI workspace you already use and connects to your other tools through an open standard (the Model Context Protocol).` |
| `index.njk:225` (+ JSON-LD `:290`) | `Get the self-hosted version and run /soleur:go inside your own harness — …` | `Two ways: run the free self-hosted version on your own computer today (the getting started page walks you through it), or join the waitlist for the hosted version. Then describe what you need, such as a feature, a contract or a competitor analysis, and Soleur routes it to the right specialists.` |
| `index.njk:217`, `pricing.njk:303` (+ JSON-LD) | `…runs inside your own (coding) harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode — …` | `…runs on your own computer inside an AI workspace such as Claude Code or Codex, and you pay your AI provider for what you use.` |

**Rationale:** removes "harness", "plugin" and command syntax from first-contact copy and FAQPage text, as the general register and the "plugin" Don't require. The full tool list stays on `/getting-started/`, where it belongs. Record the change on #9588 so the 2026-11-03 review can separate its effect from the button test.

### R19 (new). Publish gate (fixes N6; process, not copy)

In `plugins/soleur/docs/blog/blog.json`, convert to `blog.11tydata.js` with computed `permalink` and `eleventyExcludeFromCollections` that return `false` / `true` when `data.page.date > new Date()`. Add `schedule: - cron: "15 6 * * *"` to `deploy-docs.yml` so each post appears on its date. Check that `feed.xml` and the sitemap read the same filtered collection. Until this lands, the hub post (10-23) is the only verification post whose date is honest.

### R20 (new). Founder-problem titles for the scheduled verification spokes (fixes N7, N10)

Keep the slugs (the hub links to them). Change `title`, `seoTitle` and `description` only, and only while the posts are unpublished under R19.

| Post | Suggested title | Suggested seoTitle | Suggested meta description | Target query (intent) | Distinct takeaway |
|---|---|---|---|---|---|
| 10-27 guardrails | `Your AI Writes Code Faster Than You Can Read It. Which Safety Checks Do You Need?` | `Safety Checks for AI-Written Code: The 4 Every Founder Needs` | `We graded 102 automated safety checks to find the ones any founder's product needs. Four made the cut, and each must prove it catches a planted mistake first.` | is AI-written code safe to ship (informational) | Start with 4 checks, in warning mode, each proven on a planted mistake. |
| 10-29 cannot fail | `When a Green Checkmark Means Nothing` | `When a Green Checkmark Means Nothing: How to Tell if a Check Can Fail` | `A check that cannot fail looks like protection and catches nothing. Here is the one question to ask of every "verified" badge your AI tools show you.` | how to verify AI output (informational) | Ask "what would make this fail?" of any instruction or example you give an AI. |
| 11-03 first bug | `The Mistake Your Checklist Can't Imagine` | `The Mistake Your Checklist Can't Imagine: Rules Beat Remembered Cases` | `Every checklist is a list of cases someone remembered. On its first run, a rule-based check found a bug that months of hand-picked examples had missed.` | how to test AI-generated work (informational) | Replace a remembered list with a rule a machine can attack. |
| 11-05 map drift | `Your Help Docs Promise Features You Removed` | `Why Product Docs Drift, and a Check That Stops It` | `Onboarding tours and help articles drift away from the product, always toward promising more. A map that fails when it disagrees with the product keeps them honest.` | keep documentation up to date with product (informational) | Make docs something that can fail, in both directions. |
| 11-10 migration | `Replacing Something That Works? Make the Old Version Referee the New One` | `How to Replace Software Without Breaking What Customers Rely On` | `A change applied cleanly, and the chat feature was broken for three weeks. Before you retire anything that works, ask for proof the new version does what the old one did.` | how to safely replace software (informational) | Three questions to ask any contractor or AI before retiring the old system. |
| 11-12 agent map | `Don't Let Your AI Describe Pages It Never Visited` | `Stop Your AI From Inventing How Your Product Works` | `Ask an AI for a map of your product and it will write one, including pages it never opened. Only trust records of what it actually saw.` | AI made it up / AI hallucination in my app (informational) | "Show me the walk, not the confidence." |
| 11-17 flaky | `When Your AI Says "Fixed" Because It Tried Again` | `When Your AI Says It Fixed It, but It Only Tried Again` | `A check that passes on the second try was never fixed. Here is why an AI learns to retry instead of repair, and what a real "all clear" has to show.` | AI says it fixed a bug but didn't (informational) | "Did it pass, or did it pass eventually?" |

**Rationale:** each title names something the founder has already lived through (Blog note > Open with their problem). The queries are ones a founder types (Blog note > Search). Each post keeps a different takeaway, which cuts the overlap in N10. The mechanism names ("property test", "differential testing", "quarantine") stay in the body, defined in the same sentence, where they help AI engines cite the post without driving its keyword target.

### R21 (new). Series box (fixes N8)

Add to `_data/pillars.js`:

```js
"trusting-ai-work": {
  title: "Trusting the Work Your AI Does",
  description: "How to tell whether AI-produced work was actually checked — and what a check has to prove before you rely on it.",
  members: [
    { url: "/blog/agentic-verification-checklist-shipped/", relation: "pillar" },
    { url: "/blog/audited-102-guardrails-four-portable/", relation: "cluster" },
    { url: "/blog/property-test-cannot-fail-teaches-nothing/", relation: "cluster" },
    { url: "/blog/first-property-test-found-real-bug/", relation: "cluster" },
    { url: "/blog/map-that-cant-drift/", relation: "cluster" },
    { url: "/blog/test-the-migration-not-just-the-schema/", relation: "cluster" },
    { url: "/blog/map-that-only-records-what-the-agent-saw/", relation: "cluster" },
    { url: "/blog/flaky-test-passed-on-retry-quarantine/", relation: "cluster" },
  ],
},
```

Set `pillar: trusting-ai-work` on the 8 posts. Add `/blog/before-your-ai-team-takes-a-recurring-job/` to `agentic-solo-founder.members`. The series list will only show posts that are already published once R19 lands, so check that `pillar-series.njk` skips members missing from `collections.blog`. Its title lookup already returns empty for them.

### R22 (new). Recurring-job post (fixes N9, N11)

- Insert visible Q&As under `:77`, using the JSON-LD text as it stands: `### How do I find out what automations are running in my business?` and `### What is the difference between scheduling work and duplicating it?`
- Add `seoTitle: "What Every Automation in Your Business Should Answer Before It Runs"`.
- `:44` `Order is a courtesy. Idempotence is a property.` → `Order is a courtesy. Doing the work only once is a guarantee you have to build.`
- `:52` `Jobs armed by an API call that leaves no file behind at all` → `Jobs switched on by one system sending another a request, which leaves no file behind at all`

### R23 (new). Jargon substitutions for new post bodies (fixes N11)

These are fact-preserving wording fixes, so they are allowed on the published hub and on the scheduled spokes.

| Term (post:line) | Suggested |
|---|---|
| "the old system is the oracle" (11-10:36) | "the old system is the referee: the definition of correct" |
| "negative control" (11-10:68, 11-12) | "a deliberate test that should fail: remove the thing, and confirm the check notices" |
| "modulo that ledger" (11-10:96, JSON-LD :124) | "apart from the differences written in that list" |
| "what the ledger calls a P1… a P2" (10-29:59) | "one defect at our highest severity… one a grade below" |
| "The harness needed fixing too" (11-03:47) and meta | "The checking machinery needed fixing too" |
| "Presence, not conformance" (11-12:47) | "The rule is that the map exists in one known place. Nothing checks every field" |
| "gone-in-circles detector" (11-17:35) | "the step that stops the loop when it keeps trying the same fix" |
| "repository / repo" (10-27 title, seoTitle, body) | "codebase (the files that make up your product)" on first use, "codebase" after that |
| "main line / side branch" (10-27:55) | "the live version of your product / a separate draft copy where changes can be reviewed" |

## Content Gap Notes (F14)

The 2026-10-05 gap list still applies, and none of it has been published. The verification cluster used the publishing capacity of the window. Before the next spoke, publish:

| Planned piece | Target query | Intent | Type | Priority | Pillar / sibling links |
|---|---|---|---|---|---|
| How to handle contracts as a solo founder | "how to handle contracts as a solo founder" | Informational | Searchable | P1 | `/ai-agents-for-solo-founders/`; sibling: the recurring-job post (11-04) |
| Can AI run my marketing? What to delegate and what to keep | "AI to run my marketing" | Commercial | Searchable | P1 | `/ai-cmo/`; sibling: `/solo-founder-ai-stack/` |
| Can I trust what my AI produces? A founder's checklist | "can I trust AI output" | Informational | Searchable | P1 (new: the founder-language entry point to the verification cluster, which is missing) | Hub (10-23); siblings: 10-29, 11-17 |
| Self-hosted or hosted? Choosing how to start with an AI team | "self-hosted vs hosted AI tools for small business" | Commercial | Searchable | P2 (supports both hero-test paths in plain language and absorbs the tool list from N5) | `/getting-started/`; sibling: `/pricing/` |
| Hire or delegate? The first-hire decision | "should I hire my first employee" | Informational | Searchable + shareable | P2 | `/ai-agents-for-solo-founders/` |
| What the founding cohort taught us (beta-checkpoint data, #2603) | n/a (original data) | n/a | Shareable | P2 | Sibling: `blog/2026-09-26-beta-testers-went-quiet` |

**Searchable/shareable balance:** the window's output was 2 shareable and 7 searchable pieces. The searchable ones mostly target developer queries. The plan above is mostly searchable, so keep at least one shareable, data- or opinion-led founder piece a month.

**Scoring (1-5: customer impact / content-market fit / search potential / resource cost, where 5 = cheapest):**

| Piece | Impact | Fit | Search | Cost | Total |
|---|---|---|---|---|---|
| Can I trust what my AI produces? | 5 | 5 (the cluster already holds the evidence) | 4 | 5 | **19** |
| Contracts as a solo founder | 5 | 4 | 4 | 3 | 16 |
| AI to run my marketing | 5 | 4 | 4 | 3 | 16 |
| Self-hosted or hosted? | 4 | 5 | 3 | 4 | 16 |
| Hire or delegate? | 4 | 3 | 4 | 3 | 14 |
| Founding cohort data | 3 | 5 | 1 | 3 | 12 |

## Caveats

- WebFetch was blocked again, so rendered HTML and the live site were not checked. "Live" in N6 is inferred from the source: no date filter, permalinks for every post, and deploy on push to `main`. Confirm it by loading `https://soleur.ai/blog/flaky-test-passed-on-retry-quarantine/`.
- `git log` was not used (the hooks block shell pipelines). Dates of changes come from frontmatter and `verified:` comments. N5 is dated "on or about 2026-10-22" from the `last_updated` bumps and the OpenCode `verified: 2026-10-22` comment.
- N7 depends on a decision. If the 7 future-dated posts count as published, the Blog scope rule allows only fact fixes (R12-style and R23), and R20 becomes guidance for the next cluster.
- F9 and R10 depend on what product wants to promise in public about multi-provider support (#9500).
- R8 and R18 touch the homepage during the hero CTA test window (review 2026-11-03). R18 removes copy that already meets a revert trigger, so it should ship now with an annotation on #9588. R8 should wait for the review.
- Under the Blog note scope rule, no title, slug, H1, meta or keyword rewrites are proposed for posts published before this window. The exceptions are fact corrections (F4, F5, N12, N14) and the Tanka meta count fix, which still needs confirmation.
