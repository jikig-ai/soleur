---
title: "Content Audit: soleur.ai — 2026-11-23"
date: 2026-11-23
type: content-audit
site: https://soleur.ai
---

# Content Audit: soleur.ai — 2026-11-23

| Item | Detail |
|---|---|
| Date | 2026-11-23 (scheduled CI run, unattended) |
| Scope | Keyword alignment, search-intent match and readability for `/`, `/pricing/`, `/getting-started/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/vision/`, `/community/`, `/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/`, the pillar and role pages (`/company-as-a-service/`, `/ai-agents-for-solo-founders/`, `/ai-cmo/`, `/ai-cto/`, `/solo-founder-ai-stack/`), and the 13 blog posts dated 2026-10-23 or later. Posts read closely this run: 11-04 (recurring job), 11-17 (flaky test), 11-19 (green), 12-03 (alarm), 10-26 (Antigravity), 10-23 (vendor lock-in). |
| Method | **Source only.** The cron-containment hook refused WebFetch on `https://soleur.ai/` (`tool class not permitted: WebFetch`), WebSearch (`tool class not permitted: WebSearch`) and `git log` (`not allowlisted`). This is the 19th run in a row without a live fetch. "Live" is inferred from the build: `eleventy.config.js` defines no date filter, and `plugins/soleur/docs/blog/` contains only `blog.json` (no `blog.11tydata.js`). The Eleventy source in `plugins/soleur/docs/` was read with Read, Grep and Glob. |
| Brand guide | `knowledge-base/marketing/brand-guide.md` was read: Identity, Voice (Do's/Don'ts, Audience Voice Profiles, Value Proposition Framings), Channel Notes > Website / Landing Page (including the 2026-10-06 hero CTA test notes) and Channel Notes > Blog (Reader, Search, Jargon limits, Call to action, Scope). All rewrites use the **general register**: founder first; no "plugin", "harness", "AI-powered", "just" or "simply"; no exact agent counts in static prose; trust scaffolding where output quality is promised. |
| Prior audit | [2026-11-16-content-audit.md](./2026-11-16-content-audit.md) |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, `llms.txt` and OG files belong to seo-aeo-analyst. JSON-LD *text* is assessed only for what it says, because answer engines quote it word for word. This is a content audit, so no SAP or 8-component AEO scorecard is produced. |

Priority key: **P0** = wrong or misleading on a primary surface now, or a pre-declared revert trigger is met. **P1** = blocks discoverability or conversion for the ICP. **P2** = accuracy or alignment gap. **P3** = polish.

## Executive Summary

**Nothing on the site changed in the 7 days since 2026-11-16.** Every sentence cited in the prior report is still in the source. No post file was added, removed or retitled; the post set is the same 13 files dated 10-23 to 12-03. No finding is fixed this week.

Time made three things worse. The 11-17 and 11-19 posts reached their dates with developer titles, so **every post in the "trusting AI work" series now has a fixed title**: the Blog Scope rule only allows fact updates on published posts. The hero test review is **20 days** overdue with no recorded outcome. The publishing queue still ends on 12-03, and there has been **no new post file for 21 days**.

**Top 5 findings:**

1. **N5 + B1 (P0 + P1): the homepage and pricing page still use developer language, and the hero test has no recorded outcome.** `index.njk` still says "Runs inside your own coding harness", "Soleur ships as a plugin for your own coding harness" and "What the Soleur plugin adds to your coding harness.", and `soleur:go` is still in the FAQ. The hero test review date (2026-11-03) passed 20 days ago. The test's own revert trigger ("hero copy drifts toward developer register") still fires. R-1 below gives ready replacement text.
2. **N6 (P0, less exposure): there is still no date gate.** One future-dated post is live: 12-03, which is 10 days ahead. Its card heads `/blog/`, and the now-live 11-19 post links to it (A3). The problem will come back with the next post dated in the future.
3. **C1 (P1, NEW): the 9-post series has no founder search entry, and its titles can no longer change.** The retitle window closed on 11-17 and 11-19. The fix now has to come from new content: one founder-facing hub post ("Can You Trust What Your AI Team Says It Finished?", R-17) and a series box for the series in `_data/pillars.js` (N8, R-18). Neither touches a published title.
4. **F14 (P2 → P1, WORSE): there is nothing scheduled after 12-03.** No post file has been added for 21 days. None of the 4 founder-problem gap pieces is published. The C1 hub post is the obvious next piece, because it targets "can I trust AI output", the top unclaimed founder query.
5. **B2 + F4 (P1): the comparison and pillar pages convert badly and assert a competitor's revenue.** `/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/`, `/company-as-a-service/` and `/ai-agents-for-solo-founders/` still end on `claude plugin install soleur@soleur-marketplace`, a command that works for only 1 of the 6 supported tools. Three of these pages still say "Cursor reached…" in revenue terms, which the brand guide forbids.

**Headline counts:** 2 P0, 12 P1, 17 P2, 15 P3 (46 active). 44 are carried from 11-16. N7 is closed unfixed and replaced by C1. 2 findings are new (C1, C2). 1 was escalated (F14, P2 → P1).

## Delta since 2026-11-16

Status key: **FIXED**, **PARTIAL**, **STILL OPEN**, **WORSE** (still open, more exposure or more urgent), **CLOSED-UNFIXED** (can no longer be fixed as written), **UNVERIFIABLE**.

**What was fixed:** nothing. 0 of the 45 findings from 11-16 changed in source.

**What changed status (time-driven only):**

| Prior ID | Prior P | Finding | Status 11-23 | Evidence (current source) |
|---|---|---|---|---|
| N7 | P1 | Arc titles target developer queries | **CLOSED-UNFIXED** → replaced by C1 | 11-17 is still "A Flaky Test Passed on Retry and the Loop Called It Fixed" and 11-19 is still "First We Made 'Green' Mean Something. Then We Made It Fast."; both are now past their dates. The Blog Scope rule ("A refresh … keeps its title, slug, H1, meta description and target keywords") now locks all 9 series posts. |
| N6 | P0 | Future-dated posts live early | **STILL OPEN** (1 post, was 3) | 12-03 is the only post dated after today. There is still no date filter in `eleventy.config.js` and no `blog.11tydata.js`. |
| A3 | P2 | Forward link to a future post | **STILL OPEN** (source now live) | 11-19 (live since 11-19) still links `alarm-passed-every-rehearsal-never-rings` (12-03). The issue resolves itself on 12-03, but the pattern does not. |
| B1 | P1 | Hero test review passed without an outcome | **WORSE** | The brand guide's 2026-10-06 note still shows "Review date: 2026-11-03", with no outcome line. That is now 20 days overdue. |
| F14 | P2 | Founder gap pieces unpublished | **WORSE → P1** | Same 13 post files as on 11-02. 0 of 4 gap pieces published. Nothing is queued after 12-03. |
| N9 | P2 | Empty visible FAQ on the 11-04 post | **STILL OPEN** (live 19 days) | "## Frequently asked questions" is followed directly by `<script type="application/ld+json">`. |

**What persists unchanged (38):** F11, F3 (partial), F1, F2, F4, F5, F7, F6, B2, A1 (partial), A2 (partial), A4 (partial), B3, B4, F9, F10, F12, F8, F13, N1, N8, N10, N11, F15, F16, F17, F18, F19, N2, N3, N4, N12, N13, N14, #9109, A6, B5, and A5 (still UNVERIFIABLE). Spot checks: `index.njk` meta still reads "Company-as-a-Service for solo founders…" (F7) and still has "9 hats" in the visible FAQ and the JSON-LD (F5). `pricing.njk` still says "ready to sign", "autopilot", "the other 70%", "420+ PRs" and "You run it inside your own harness". `skills.njk` still has `title: Soleur Skills` and the H1 "Agentic Engineering Skills". `blog.njk` still has the seoTitle "…Agentic Engineering, and Building at Scale With AI Teams" and the H1 "Blog". `agents.njk` still says "is trained" and "within Claude Code". `vision.njk` still has "GPT-4o for strategy". `ai-cmo.njk` still gives both $240K and $290K. The Devin table row still says "Partial (runs in your Claude Code environment)". The Antigravity FAQ still says "Gemini 2.5 Pro and Gemini Flash" and still uses `agy` in backticks.

**What is new:**

- **C1 (P1):** with all 9 series titles fixed, the series needs a new founder-searchable hub post and a series box. See R-17 and R-18.
- **C2 (P2):** legal pages describe the product as running on 4 tools ("…Grok Build, Codex, and Devin CLI" in `terms-and-conditions.md`, `privacy-policy.md`, `acceptable-use-policy.md`, `gdpr-policy.md` and `data-protection-disclosure.md`). They omit OpenCode and Google Antigravity CLI, which the marketing pages list. This is a fourth tool count, alongside 6, 5 and Claude Code only (A1). Route to legal-compliance-auditor; do not edit from a growth run.

### Tracked issues (unchanged since 11-16 unless noted)

#11133 (N5, review overdue), #11132 (N6, 1 post), #11134 (N7: close as superseded and open the C1 hub-post task), #11136 (N8/N9/N10/N11), #11138 (N1), #9112 (F7), #9111 (F10/F17), #9109, #9104/#9105 (F1/F2), #9499 (F8), #9500 (A1/B4), #8466 (F14, escalate), #2669 (F11), #9107 (F3), #7179 (F4), #8462 (F5), #5601 (F6). #9103 (Inc.com "As seen in") is still absent from source; close it after a live check. Issue states were not re-queried because the `gh` CLI is out of scope for this run.

## Prioritized Findings

| ID | Priority | Page | Finding | Recommendation |
|---|---|---|---|---|
| N5 | **P0** | `/`, `/pricing/` | "coding harness", "ships as a plugin", "Soleur plugin", `soleur:go` (FAQ) and "inside your own harness" (pricing FAQ, visible and JSON-LD) on first-contact surfaces | Apply R-1 (below). (#11133) |
| N6 | **P0** | `/blog/`, 12-03 post | A post dated 10 days ahead is live and heads the index | Exclude `date > now` from `collections.blog` and set `permalink: false` for those posts (`blog.11tydata.js`). Apply the same filter to the feed and sitemap. Add a daily `schedule:` to `deploy-docs.yml`. (#11132) |
| B1 | P1 | brand guide → `/` | Hero test review 20 days overdue, no outcome recorded, a revert trigger still met | Record keep, revert or extend under the 2026-10-06 note. If kept, ship R-1 so the trigger stops firing. |
| C1 | P1 | 9 series posts (10-23 → 11-19) | **NEW.** All series titles are now fixed in developer register ("Property Test", "Migration", "Schema", "Flaky Test", "Green"). The series has no founder-searchable entry point | Publish R-17 as the series hub (new post, not a retitle) and point the series box at it (R-18). |
| F14 | P1 (↑) | `/blog/` | 21 days without a new post file; nothing after 12-03; 0 of 4 gap pieces | Slot R-17 for the first date after 12-03, then "Contracts as a solo founder". (#8466) |
| B2 | P1 | compare-cursor, compare-devin, CaaS, AI-agents pillar | Pages end on a terminal install that works for 1 of 6 tools, against the Website note | R-11: waitlist button plus a plain link to getting-started. |
| F11 | P1 | `/getting-started/` | The hero button lands on "Source-available. Install in your own harness." with 6 install blocks | R-3: a plain "What you need" paragraph first; per-tool blocks collapsed under "Setup by tool". (#2669) |
| F3 | P1 | `/getting-started/` | seoTitle and meta promise "two commands"; the page's own FAQ says that is Claude Code only | R-3 seoTitle and meta (below). (#9107) |
| F1 | P1 | `/blog/` | seoTitle targets "Agentic Engineering"; H1 "Blog" | R-4 (below). (#9104) |
| F2 | P1 | `/blog/` | Founder posts fall into the "Engineering Deep Dives" catch-all, because `blog.njk` sorts by tags | Add a "Running Your Company" category keyed on `solo-founder`; retire the catch-all. (#9105) |
| F4 | P1 | compare-cursor, CaaS, AI-agents pillar, 2+ posts | "Cursor reached…" states revenue as fact | Attribute it in the sentence, or use funding and valuation instead. (#7179) |
| F5 | P1 | `/` FAQ + 3 posts | "wearing 9 hats who want to hand off 8" contradicts the 8 departments | R-1d. (#8462) |
| F7 | P1 | `/` | Meta and badge lead with "Company-as-a-Service" (education-heavy framing) | R-1a. (#9112) |
| F6 | P1 | `/skills/` | Title "Soleur Skills"; H1 "Agentic Engineering Skills" | R-5 (below). (#5601) |
| C2 | P2 | 5 legal pages | **NEW.** Product scope lists 4 tools (omits OpenCode and Antigravity) | Hand off to legal-compliance-auditor. Suggest pointing to "the supported tools listed at /getting-started/". |
| A1 | P2 | site-wide | Tool count: 6 (getting-started body, vendor post), 5 (homepage, pricing, vision, community, compare ×2, skills), 4 (legal), Claude Code only (about, agents FAQ, Devin table) | R-14: stop listing tools in first-contact copy; keep one list on getting-started. |
| A2 | P2 | Antigravity post | Meta "on Gemini models"; first CTA link is an install anchor; `agy` and "harness" in FAQ answers | R-8 meta; R-13 FAQ; make the waitlist the first CTA link. |
| B4 | P2 | Antigravity post (FAQPage) | "Gemini 2.5 Pro and Gemini Flash" has no source and will go stale | R-13. |
| A3 | P2 | 11-19 post | Live post links to the post dated 12-03 | Render the link only if the target is in `collections.blog`. |
| A4 | P2 | Vendor-lock-in post | "on any model they choose", "eliminates that risk", "67 specialist agents", install CTA | R-9; "removes that dependency"; "your AI team" for the agent count; waitlist CTA. |
| B3 | P2 | `/compare/soleur-vs-devin/` | Table says "runs in your Claude Code environment", but Soleur also runs inside Devin CLI; "compound step" is internal vocabulary | R-12. |
| F9 | P2 | `/vision/` | "GPT-4o for strategy" presented as shipped | Mark it as roadmap, or remove the model names. (#9500) |
| F10 | P2 | `/pricing/` | "ready to sign", "autopilot" with no trust scaffolding | "ready for your review"; "Your public presence, kept current." (#9111) |
| F12 | P2 | `/agents/` | "is trained" (body, FAQ, JSON-LD); "within Claude Code" | "Each agent is set up for one function…"; drop the Claude-only wording. |
| F8 | P2 | `/ai-cmo/` | $240K (seoTitle) vs $290K (meta) | Use one sourced figure. (#9499) |
| F13 | P2 | `/community/` | Generic title and H1 | "Soleur Community — Build With Other Solo Founders". |
| N1 | P2 | 5 core pages | `last_updated: 2026-10-22` not backed by a fact review | Change the date only in the PR that fixes the facts. (#11138) |
| N8 | P2 | 9 series posts (+12-03) | `pillar: billion-dollar-solo-founder` shows the wrong series box | R-18. |
| N9 | P2 | 11-04 post | Visible FAQ heading with no visible Q&A | R-15: show the JSON-LD Q&As as `###` headings with plain answers. |
| N10 | P2 | 11-19 post | Repeats the 10-27 FAQ question "Can an automated check itself be wrong?" | Fact-level fix: answer it differently, or link to 10-27. |
| N11 | P2 | 11-04, 11-19 posts | "Idempotence is a property."; "nearly 700 automated checks"; "twelve merges, zero broken mains" | Define "idempotence" in the same sentence ("it can run twice without doing the work twice") as a fact-level clarity edit. |
| F15 | P3 | `/about/` | "running in Claude Code today" | "running today in the AI tools founders already use". |
| F16 | P3 | `/vision/`, `/glossary/`, CaaS | Superlatives; the pages disagree on where CaaS came from | Use one origin line everywhere. |
| F17 | P3 | `/pricing/`, compare-cursor | Unsourced "70%"; "420+ PRs" (engineering metric) | Source the 70% or remove it; replace "420+ PRs" with "every department". |
| F18 | P3 | `/` | Section label "This Is the Way" | "The Problem". |
| F19 | P3 | `/agents/`, `/skills/` | `last_updated` from June | Re-date after F6 and F12 are fixed. |
| N2 | P3 | `/`, `/vision/` | "running autonomously on your command" | "…working on your command, with your approval". |
| N3 | P3 | footer | "Known external tools" (developer page) | Move it to a developer group. |
| N4 | P3 | `/pricing/` | "Your AI organization is ready." sits above a waitlist | "Your AI organization is almost ready." |
| N12 | P3 | 10-23 hub post | Superlative and overclaim | Fact fixes only. |
| N13 | P3 | ai-cmo, ai-cto, solo-founder-ai-stack | "Role Cluster" label (internal term) | "Founder Guide". |
| N14 | P3 | 11-03 post | "It was the third time…" used for two different events | Keep one. |
| #9109 | P3 | several | The lifecycle is described 3 ways | "plan, build, review, remember" on general-register pages. |
| A5 | P3 | 10-23, 10-26 posts | Possibly backdated | Verify with git history in an interactive run. |
| A6 | P3 | 9 series posts | `tags: - pillar` is unused | Remove the tag from all 9. |
| B5 | P3 | global nav | "Learn" mixes "Agentic Engineering" and "Claude Code Plugins" with founder guides | Move both to a "For developers" group; R-16. |

## Per-Page Analysis

### 1. Homepage (`/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" / "Stop hiring. Start delegating." Strong, and on the primary (pain-point) framing. |
| Meta | "Company-as-a-Service for solo founders. AI agents across 8 departments…" leads with the education-heavy CaaS framing (F7). |
| Detected keywords | AI agents for solo founders; Company-as-a-Service; coding harness; plugin; Claude Code, Grok Build, Codex, Devin CLI, OpenCode; MCP. |
| Keyword alignment | Strong in the title. Weak in the meta and above the fold: tool names outweigh founder query words ("hire", "delegate", "marketing", "legal"). |
| Search intent | Commercial, with some informational. The FAQ covers both. |
| Readability | The line under the hero button names 5 developer tools plus "harness". The tool list is out of date (5, not 6). The "9 hats" FAQ contradicts "8 departments". "This Is the Way" is a pop-culture section label with no information. |
| Issues | N5 (P0), B1, F5, F7 (P1), A1 (P2), F18, N2, B5 (P3). |

### 2. Pricing (`/pricing/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." Strong. |
| Meta / intent | Transactional intent is met ($49/month, waitlist). |
| Readability | The free-version FAQ says "inside your own harness" and lists 5 tools (N5, A1). "ready to sign" and "autopilot" lack trust scaffolding (F10). "70%" is unsourced and "420+ PRs" is an engineering metric (F17). The waitlist H2 says "ready" (N4). |

### 3. Getting Started (`/getting-started/`)

| Field | Assessment |
|---|---|
| Title / H1 | seoTitle "…Install Your AI Organization in Two Commands" / H1 "The AI that already knows your business." (memory-first variant, good). |
| Keyword alignment | Misaligned. "Two commands" is true for 1 of 6 tools, and the page's FAQ says so (F3). |
| Intent | Split three ways: install, waitlist, and the homepage `#self-hosted` anchor. |
| Readability | The first label is "Source-available. Install in your own harness." It is followed by 6 install blocks, a command table with 6 tool columns, and `.antigravity-plugin/plugin.json`. The page is right for developers and the wrong first page for founders (F11). |

### 4. Blog index (`/blog/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "Blog". |
| Alignment | Targets developer queries, against the Blog note's Search rule (F1). |
| IA | 4 tag-driven categories. Founder posts without the `CaaS` or `ai-agents` tags fall into "Engineering Deep Dives" (F2). The 12-03 card heads the list (N6). |

### 5. Agents (`/agents/`) and Skills (`/skills/`)

| Page | Title / H1 | Alignment | Issues |
|---|---|---|---|
| `/agents/` | "Your AI Organization: {{ stats.agents }} Specialists Across {{ stats.departments }} Departments" | Good: computed counts, founder framing | F12 ("trained", "within Claude Code"), F19. |
| `/skills/` | "Soleur Skills" / "Agentic Engineering Skills" | Weak: brand-only title, developer H1 | F6, A1, F19. |

### 6. Comparison, pillar and role pages

| Page | Intent match | Strengths | Issues |
|---|---|---|---|
| `/compare/soleur-vs-cursor/` | Commercial; matches "Soleur vs Cursor" | One-sentence summary; sourced link | F4, F17, A1, B2. |
| `/compare/soleur-vs-devin/` | Commercial; strong match for "Devin alternative" | Inline citations; public pricing rather than revenue; fair "When to pick Devin" section; trust scaffolding | B3 (table row and "compound step"), B2. The April 2025 price-cut framing is aging. |
| `/company-as-a-service/`, `/ai-agents-for-solo-founders/` | Informational pillars | Clear definitions | F4, B2. |
| `/ai-cmo/`, `/ai-cto/`, `/solo-founder-ai-stack/` | Informational / commercial ("AI CMO") | Year-stamped, query-shaped seoTitles | F8 (CMO cost), N13 ("Role Cluster"). |

### 7. About, Vision, Community

Unchanged since 11-02. `/about/` says "running in Claude Code today" (F15, A1). `/vision/` shows GPT-4o routing as shipped (F9) and says "running autonomously" (N2). `/community/` has a generic title and H1 (F13).

### 8. Blog posts

| Post (date) | Title / seoTitle | Target query | Intent | Founder-problem title? | Readability / jargon | CTA | Verdict |
|---|---|---|---|---|---|---|---|
| Vendor lock-in (10-23) | "What Happens to Your Business When Your AI Provider Changes the Rules?" / "Own Your AI Team Without Vendor Lock-In \| Soleur" | AI vendor lock-in | Informational / commercial | Yes | "harness" in 7+ lines (body, FAQ, JSON-LD), "Git repository", "open-weights", "Ollama, llama.cpp" | `/getting-started/` | Strong angle; finish A4. |
| Antigravity (10-26) | "Run Your AI Company on Google Antigravity Without Losing Your Business Memory" | Google Antigravity (navigational) | Navigational / informational | Partly | "agentic coding tools", "harness" ×4, `agy`, unsourced model names | Install anchor first | A2, B4. |
| Recurring job (11-04) | "Before Your AI Team Takes a Recurring Job, It Answers Six Questions" | audit business automations | Informational | Yes | Best opening on the site; "Idempotence is a property." is undefined | "Try Soleur" → homepage | Fix N9 (empty visible FAQ). |
| Flaky test (11-17, **now live**) | "A Flaky Test Passed on Retry and the Loop Called It Fixed" (same seoTitle) | flaky test (developer) | Informational (developer) | No | Founder-facing opening ("Your AI produces work faster than you can check it…"); developer title and meta | Waitlist | Title is now fixed (C1). |
| Green (11-19, **now live**) | "First We Made 'Green' Mean Something. Then We Made It Fast." / "We Made Green Mean Something, Then Made It Fast" | none (our own story) | Informational | No | "nearly 700 automated checks", "twelve merges, zero broken mains", "arbiter adjudicated its own rebuild" | Waitlist | Title is now fixed. Fact-level fixes only (N10, N11, A3). |
| Alarm (12-03, future) | "Your Alarm Passed Every Rehearsal. In Real Life It Never Rings." / "Your Error Alerts Can Pass Every Test and Never Fire" | error alerts not firing | Informational | Yes | Plain analogies; light jargon | Waitlist | The model post for the series. Only N6 and N8 apply. |
| 10-27, 10-29, 11-03, 11-05, 11-10, 11-12 | unchanged | "property test", "migration", "schema", "feature map" | Developer | No | N11 | Waitlist | Fixed titles; fact fixes only. |

**Searchable vs shareable:** 3 founder-searchable posts (vendor lock-in, recurring job, alarm), 1 announcement (Antigravity) and 9 build-in-public series posts. The series posts are meant to be shared but carry developer titles, so they reach neither founder searchers nor founder sharers. No data-led shareable piece is planned. R-17 gives the series a searchable hub without changing any published title.

## Keyword Notes

WebSearch was refused (see Method), so no new volume or difficulty data was gathered. Relevance is judged against the Blog note's reader.

| Keyword / query | Intent | Relevance | Currently targeted by | Note |
|---|---|---|---|---|
| can I trust AI output / how to check AI work | Informational | High | None (10-23 hub only partly) | Top unclaimed founder query. Target it with R-17. |
| AI says it's done but it isn't / AI retries until it passes | Informational | Medium-high | 11-17 body only | Founder phrasing of the 11-17 and 11-19 lessons; use as H2s in R-17. |
| error alerts not firing / how do I know my alerts work | Informational | Medium | 12-03 seoTitle | Well targeted. |
| AI vendor lock-in / switch AI provider without losing data | Informational / commercial | High | Vendor-lock-in post | Good. |
| Soleur vs Devin / Devin alternative | Commercial | High | `/compare/soleur-vs-devin/` | Add "Devin alternative for solo founders" to the first H2 or a FAQ question. |
| AI CMO cost / AI CMO vs hiring | Commercial | High | `/ai-cmo/` | Cost claim must be consistent (F8). |
| Claude Code plugins / agentic engineering | Navigational (developer) | Low for ICP | Nav, blog seoTitle, skills H1 | Keep these pages, but move them off founder-first surfaces (F1, F6, B5). |

## Rewrite Suggestions

All rewrites use the general register. R-3, R-6, R-8, R-9 and R-11 to R-16 from the [11-02](./2026-11-02-content-audit.md) and [11-16](./2026-11-16-content-audit.md) audits still apply. R-6 (11-19) and R-10 (11-17) are **withdrawn**: both posts are now published, and the Blog Scope rule only allows fact updates on published posts. The P0 and P1 rewrites are restated below so this report stands alone.

| ID | Page | Element | Current | Suggested | Rationale |
|---|---|---|---|---|---|
| R-1a | `/` | Meta description | "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal, finance, operations, product, sales, support." | "Stop hiring, start delegating. Your AI team covers marketing, legal, finance, operations, sales, support, product and engineering, and remembers your business." | Brand primary framing (pain-point) plus memory. CaaS stays in the badge and deeper sections (F7). |
| R-1b | `/` | Hero note under the button | "Source-available. Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode; you pay for your own model usage." | "Free and source-available. Runs inside the AI workspace you already use, such as Claude Code or Codex. You pay only for your own model usage." | Removes "harness". Stops the tool list drifting (A1). Clears the hero test's developer-register revert trigger (B1). |
| R-1c | `/` | Section description | "Soleur ships as a plugin for your own coding harness — … — and is built on the Model Context Protocol (MCP)…" | "Soleur works inside the AI tools you already use, and connects to your other software through the Model Context Protocol (MCP), the open standard for linking AI to outside tools." | Brand Don't: "plugin". Defines MCP in the same sentence. |
| R-1d | `/` | FAQ "Who is Soleur for?" (visible and JSON-LD) | "Solopreneurs and solo founders wearing 9 hats who want to hand off 8 of them." | "Solo founders doing 8 jobs who want help with 7 of them." | Matches the brand pitch ("You're doing 8 jobs. Soleur helps you tackle 7 of them") and the 8 departments (F5). |
| R-1e | `/pricing/` | FAQ "Is there a free version?" (visible and JSON-LD) | "You run it inside your own harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode — and pay for your own model usage." | "You run it inside the AI workspace you already use, and pay for your own model usage. Setup for each supported tool is on the getting started page." | N5 + A1. |
| R-1f | `/` | Remaining `soleur:go` mentions in FAQ text | `/soleur:go` | "Describe what you need in plain words, and Soleur routes it to the right specialist." | No commands on first-contact pages. |
| R-3 | `/getting-started/` | seoTitle / meta | "Get Started with Soleur — Install Your AI Organization in Two Commands" / "Install Soleur in two commands and run a full AI organization…" | "Get Started with Soleur — Join the Waitlist or Run It Free Today" / "Join the waitlist for hosted Soleur, or run the free self-hosted version today inside the AI tool you already use. Marketing, legal, finance and more, without hiring." | True for all 6 tools; covers both intents (F3). |
| R-4 | `/blog/` | seoTitle / meta / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / … / "Blog" | "Running a Company Alone With an AI Team — Soleur Blog" / "Guides for solo founders: delegating marketing, legal, finance and operations to an AI team, and knowing when to trust its work." / "Running a company alone, with an AI team" | Blog note Search rule: founder words, not "agentic engineering" (F1). |
| R-5 | `/skills/` | seoTitle / H1 | "Soleur Skills" / "Agentic Engineering Skills" | "Soleur Skills — The Workflows Your AI Team Follows" / "The workflows your AI team follows" | Uses the brand glossary definition of "skills" (F6). |
| R-17 | New post (first date after 12-03) | Title / seoTitle / meta / outline | (none) | **Title:** "Can You Trust What Your AI Team Says It Finished?" **seoTitle:** "How to Trust AI Work Before You Believe 'Done' \| Soleur" **Meta:** "Your AI finishes work faster than you can check it. Here is how to tell a real 'done' from a lucky one, and the questions to ask before you rely on it." **Outline:** (1) Your week: AI output piles up faster than you can review it. (2) "Passed on the second try" isn't fixed (lesson from 11-17). (3) A check that can never fail tells you nothing (10-29). (4) When "all green" hides problems (11-19). (5) An alarm that passes every drill can still stay silent (12-03). (6) What you still decide, and what your AI team checks for you. (7) FAQ: 3 founder questions. CTA: Join the waitlist. Link once to each series post as "the full story". | C1 + F14. Searchable and informational. Turns 9 posts that are hard to find into one founder hub, without touching published titles. Use only numbers a founder can check (Blog Proof points rule). |
| R-18 | `_data/pillars.js` + 10 posts | Series box | `pillar: billion-dollar-solo-founder` on the series posts | Add the entry `"trusting-ai-work": { title: "Trusting What Your AI Team Produces", … }` with R-17 as the hub, and set `pillar: trusting-ai-work` on the 10 series posts (10-23 → 12-03). | Fixes N8. A series box is page furniture, not title, H1 or meta, so the Scope rule allows it. |
| R-19 | 5 legal pages | Product scope list | "(Claude Code, Grok Build, Codex, and Devin CLI)" | Hand off to the CLO. Suggested wording: "(the supported AI coding tools listed at soleur.ai/getting-started)" | C2. One source of truth (R-14); legal must approve. |

## Top 5 Actions

1. **Record the hero test outcome in the brand guide, then ship R-1a to R-1f in one PR (N5, B1, F5, F7).** This clears both P0 and P1 homepage items and stops the revert trigger from firing.
2. **Add the date gate before 12-03 (N6, A3).** After 12-03 there is no future post, so the gate has to be in place before the next post dated in the future is merged.
3. **Commission R-17 and land R-18 (C1, F14, N8).** This is the only way left to make the 9-post series findable for founders, and it fills the empty post-12-03 queue with the top unclaimed founder query.
4. **Replace the terminal endings on the 4 comparison and pillar pages with R-11, and attribute or remove the Cursor revenue claim (B2, F4, B3).** These are the highest commercial-intent pages in the nav.
5. **Ship R-3, R-4 and R-5 (F3, F1, F6),** then finish the half-done tool and model fixes (A1, A2, A4, B4) and send C2 to legal.

## Caveats

- WebFetch, WebSearch and `git log` were all blocked by cron containment. No rendered page was checked. Every status comes from source. #9103 needs a live check before it is closed.
- "No new post file for 21 days" is inferred from the post file set matching the 11-02 and 11-16 sweeps, not from commit history.
- Evidence cites quoted text and file names, not line numbers.
- R-18 assumes the series box is not covered by the Blog Scope rule (title, slug, H1, meta, target keywords). The CMO should confirm this on #11134.
