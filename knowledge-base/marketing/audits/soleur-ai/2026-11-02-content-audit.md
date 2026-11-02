# Content Audit: soleur.ai — 2026-11-02

| Item | Detail |
|---|---|
| Date | 2026-11-02 (scheduled CI run, unattended) |
| Scope | Keyword alignment, search-intent match and readability for `/`, `/pricing/`, `/getting-started/`, `/blog/`, `/about/`, `/vision/`, `/agents/`, `/skills/`, `/community/`, the pillar pages (`/company-as-a-service/`, `/ai-agents-for-solo-founders/`, `/ai-cmo/`, `/ai-cto/`, `/solo-founder-ai-stack/`), `/compare/soleur-vs-cursor/`, and every blog post dated 2026-10-23 or later (13 posts, 3 of them not seen by the last audit). |
| Method | **Source only.** The cron-containment hook blocked WebFetch (`tool class not permitted: WebFetch`), WebSearch, and `git log` (`not allowlisted`). This is the 17th run in a row with no live fetch (#8467, #6088). The Eleventy source in `plugins/soleur/docs/` was read with Read, Grep and Glob. Build config: `eleventy.config.js` (repo root), `plugins/soleur/docs/blog/blog.json`, `.github/workflows/deploy-docs.yml`. "Live" is inferred from the build config: there is no date filter, and the site deploys on push to `main`. Because `git log` was blocked, "new since 2026-10-26" means "files absent from the 2026-10-26 audit's full sweep of posts dated 2026-10-19 or later". |
| Brand guide | `knowledge-base/marketing/brand-guide.md` was read: Identity, Voice (Do's/Don'ts, Audience Voice Profiles, Value Proposition Framings), Channel Notes > Website / Landing Page (including the 2026-10-06 hero CTA test note, review date **2026-11-03**), and Channel Notes > Blog. All rewrites use the **general register** (founder-first). |
| Prior audit | [2026-10-26-content-audit.md](./2026-10-26-content-audit.md) and [2026-10-26-content-plan.md](./2026-10-26-content-plan.md) |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, llms.txt and OG files (owned by seo-aeo-analyst). JSON-LD *text* is assessed only for what it says. This is a content audit, not an AEO audit, so no SAP or 8-component scorecard is produced. |

## Executive Summary

**Since 2026-10-26, no copy fix has landed on any core page.** The homepage, pricing, getting-started (apart from one new install block), blog index, vision, agents, skills, about and community source still contains every sentence cited last week. Instead, the week added 3 new posts and 1 new install path (Google Antigravity CLI). These added new evidence to open issues and created 2 new consistency defects.

**Prior findings (33):** 0 fixed, 3 partly fixed, 7 worse, 23 still open. Of the tracked issues named for this run, **#9103 (Inc.com "As seen in") looks fixed in source**: there is no "As seen in" strip, and Inc. is now cited as an attributed quote with a link. Close it after a live check.

**The two P0s are still open, and both get more urgent tomorrow:**

1. **#11132: future-dated posts go live early. Worse.** There is still no date gate. 7 posts carry dates after today, from 2026-11-03 to **2026-12-03**. The furthest is 31 days ahead. Two of them are new: `first-we-made-green-mean-something` (11-19) and `alarm-passed-every-rehearsal-never-rings` (12-03). The 11-19 post links to the 12-03 post, so a date gate that lands without care will leave a broken link in the 11-19 post for 14 days.
2. **#11133: homepage and pricing drifted to developer register. Unchanged.** The "coding harness", "ships as a plugin" and `/soleur:go` copy is all still there. **The hero CTA test review is 2026-11-03, tomorrow.** "Hero copy drifts toward developer register" is a named revert trigger, and it is still met. If the drift is not fixed today, the review must at least record it as a confound (#9588).

**New this week (6 findings, 0 P0):**

- **Supported-tool count disagrees across the site (P2, NEW).** Getting-started's body now lists **6** self-hosted tools (Antigravity added). Getting-started's own FAQ and JSON-LD, the homepage, pricing, compare-cursor and the vendor-lock-in post's FAQ still say **5**. The vendor-lock-in post says 6 in the body and 5 in its own FAQ. Answer engines quote the FAQPage text, so they will repeat "5".
- **The Antigravity post is a product announcement in mechanism register (P2, NEW).** Its seoTitle is "Run an AI Team on Any Harness". It has about 330 words, no call to action, no FAQ and no outside source. It says "8-department" but lists 6 departments.
- **The vendor-lock-in post has the right founder problem but overclaims (P2, NEW).** The meta says "on any model they choose", which hosted (Anthropic-only) does not support. The body hard-codes "67 specialist agents" and says "Soleur eliminates that risk". The call to action sends founders to the install manual.
- **The 11-19 post repeats the arc's problems (new evidence for #11134 and #11136).** It has an our-story title, engineering metrics ("nearly 700 automated checks", "twelve merges, zero broken mains"), the wrong series box, and a FAQ question copied word for word from the 10-27 post.
- **Good changes:** the 10-23 vendor-lock-in post and the 12-03 alarm post are the strongest founder-register openings since the 11-04 recurring-job post. The 12-03 post is the first arc post whose title, seoTitle and meta all name the founder's problem.

**Headline counts this run:** 2 P0, 9 P1, 15 P2, 14 P3 (40 total). 34 are carried: the 33 prior findings plus #9109, now listed as its own row. 6 are new (A1 to A6).

## Prior-Findings Status (2026-10-26 → 2026-11-02)

Status key: **FIXED**, **PARTIAL**, **STILL OPEN**, **WORSE** (still open and the evidence has grown).

| Prior ID | Prior P | Finding | Issue | Status 11-02 | Evidence (current source) |
|---|---|---|---|---|---|
| N6 | P0 | Future-dated posts live early | #11132 | **WORSE** | `eleventy.config.js` still has no date filter. `blog.json` still sets a permalink for every post. `deploy-docs.yml` has no `schedule:` trigger (only `push`, `workflow_run`, `workflow_dispatch`). The 10-27 and 10-29 posts have reached their dates. 2 new future posts were added: 11-19 and 12-03, the latter 31 days ahead. 7 posts are now future-dated: 11-03, 11-04, 11-05, 11-10, 11-12, 11-17, 11-19, plus 12-03 (8 counting 11-03, which is tomorrow). |
| N5 | P0 | Homepage and pricing in developer register | #11133 | **STILL OPEN** | `index.njk` hero note: "Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode". Compare section: "Soleur ships as a plugin for your own coding harness". "Go deeper" list: "What the Soleur plugin adds to your coding harness." The FAQ "How do I get started?" still contains `/soleur:go` (visible text and JSON-LD). `pricing.njk` FAQ: "You run it inside your own harness". The review is tomorrow (2026-11-03). |
| F11 | P1 | Hero button lands in a terminal manual | #2669 | **WORSE** | `getting-started.njk` `#self-hosted` now has **6** install blocks, with a new "Google Antigravity CLI" block: "Soleur loads as an Antigravity plugin via `.antigravity-plugin/plugin.json`", `agy`, `view_file`, `write_to_file`, `invoke_subagent`. The command table has a 7th column. The label is still "Source-available. Install in your own harness." The OpenCode paragraph (`CLAUDE_PLUGIN_ROOT`, `<promise>DONE</promise>`) is unchanged. |
| F3 | P1 | "Two Commands" title vs waitlist hero vs "Nothing to install" FAQ | #9107 | **WORSE** | seoTitle "Install Your AI Organization in Two Commands" is now true for 1 of 6 tools. The FAQ still opens "Nothing to install." and names only 5 harnesses, while the body names 6. |
| N7 | P1 | Arc titles target developer queries | #11134 | **WORSE** | None of the 7 titles changed. 10-27 ("102 Guardrails… Repository") and 10-29 ("Property Test") have now reached their dates, so under the Blog scope rule the chance to retitle them before publishing has closed. New post 11-19, "First We Made 'Green' Mean Something", is an our-story title. 12-03 is a positive exception (see below). |
| F1 | P1 | Blog index targets developer queries | #9104 | **STILL OPEN** | `pages/blog.njk` seoTitle "…Agentic Engineering, and Building at Scale With AI Teams". The meta still says "engineering deep dives". The H1 is still "Blog". |
| F2 | P1 | Founder posts filed under engineering and CaaS labels | #9105 | **WORSE** | The category logic is unchanged. New misfiles: the vendor-lock-in post (no `CaaS`/`ai-agents` tag) lands in "Engineering Deep Dives". The Antigravity product announcement (`ai-agents` tag) lands in "What is Company-as-a-Service?". 11-19 and 12-03 land in "Engineering Deep Dives". |
| F4 | P1 | Competitor revenue stated as fact | #7179 | **STILL OPEN** | `ai-agents-for-solo-founders.njk` ("annual recurring revenue"); `company-as-a-service.njk` (two places); `compare-soleur-vs-cursor.njk` "Cursor reached roughly 1 billion dollars in annual recurring revenue at a 29.3 billion dollar valuation" (the link goes to CNBC, but the sentence states it as fact; the rule needs in-sentence attribution); `blog/2026-03-19-soleur-vs-cursor.md` "$2B+ ARR" ×2; `blog/2026-03-24-ai-agents-for-solo-founders.md`. |
| F5 | P1 | "9 hats / nine departments" vs 8 | #8462 | **STILL OPEN** | `index.njk` FAQ and JSON-LD "wearing 9 hats who want to hand off 8"; `blog/2026-05-05-soleur-vs-tanka.md` "9 departments"; `blog/2026-04-21-soleur-vs-devin.md` "nine" ×6; `blog/2026-04-21-one-person-billion-dollar-company.md` "nine" ×3. |
| F7 | P1 | Hero and meta lead with CaaS | #9112 | **STILL OPEN** | `index.njk` meta "Company-as-a-Service for solo founders…". Badge "Company-as-a-Service". Tagline "The Company-as-a-Service platform that already knows your business." The hero-sub repeats CaaS. |
| F6 | P1 | Skills title brand-only; H1 technical | #5601 | **STILL OPEN** | `skills.njk` `title: Soleur Skills`, no seoTitle; H1 "Agentic Engineering Skills". |
| F9 | P2 | Model-support claims | #9500, #6376 | **PARTIAL** (with new regressions) | The `/vision/` "Model-Agnostic Architecture" cards are unchanged: "Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy." and "Plug in your own API keys (Anthropic, OpenAI, Gemini, Llama, and more)". New: the vendor-lock-in meta says "on any model they choose", and the tool count now disagrees (see A1). |
| F10 | P2 | Pricing "ready to sign" / "autopilot" | #9111 | **STILL OPEN** | `pricing.njk` "…formatted, footnoted, and ready to sign." and "Your public presence on autopilot." |
| F12 | P2 | Agents "trained"; Claude Code only | #6378 | **STILL OPEN** | `agents.njk` "is trained" ×3 (body, FAQ, JSON-LD). |
| F8 | P2 | AI CMO cost figure inconsistent | #9499 | **STILL OPEN** | `ai-cmo.njk` seoTitle "$240K", meta "$290K" (body "~$294,000" not re-checked). |
| F13 | P2 | Community title/H1 generic | #6377 | **STILL OPEN** | seoTitle "Community — Soleur", H1 "Community". |
| F14 | P2 | Founder-problem gap pieces unpublished | #8466 | **PARTIAL** | Cadence holds (3 more posts). 2 of the 3 new posts are founder-first: vendor lock-in (10-23) and alarm (12-03, future-dated). 0 of the planned gap pieces (contracts, AI marketing, hire or delegate, self-hosted vs hosted) are published. The vendor-lock-in post partly covers "self-hosted vs hosted". |
| N1 | P2 | `last_updated` bumped without fact review | #11138 | **STILL OPEN** | No new bumps this week, but none of the 7 bumps to 2026-10-22 was reverted or backed by fixes. The opposite error also appeared: Antigravity was added to `getting-started.njk` (`verified: 2026-10-26`) while `last_updated` stays 2026-10-22. |
| N8 | P2 | Arc posts show the wrong series box | #11136 | **WORSE** | `_data/pillars.js` has no `trusting-ai-work` entry. **10** posts now declare `pillar: billion-dollar-solo-founder` (11-19 and 12-03 added). 11-19 also carries a stray `pillar` tag. |
| N9 | P2 | Recurring-job post has an empty visible FAQ | #11136 | **STILL OPEN** | `2026-11-04-before-your-ai-team-takes-a-recurring-job.md` "## Frequently asked questions" is followed directly by `<script type="application/ld+json">`. There is no seoTitle. |
| N10 | P2 | Same lesson repeated across the arc | #11136 | **WORSE** | 11-19 repeats "Can an automated check itself be wrong?", copied word for word from the 10-27 FAQ, and closes on the "verify the verifiers" thesis again ("catch the lesson, write it into the machinery"). |
| N11 | P2 | Undefined jargon in arc bodies/FAQ | #11136 | **STILL OPEN** | "Order is a courtesy. Idempotence is a property." (11-04) is unchanged. 11-19 adds "fixture", "soak test", "bootstrap problem", "zero broken mains", "serial", "census". |
| F15 | P3 | About filler and "agentic engineering" line | — | **STILL OPEN** | `about.njk` "The founder behind Soleur."; "Jean writes about agentic engineering…". It also still says "running in Claude Code today", which disagrees with 6 tools. |
| F16 | P3 | Vision superlatives; CaaS origin claims disagree | #9501, #6085 | **STILL OPEN** | `vision.njk` "infinite leverage", "first model-agnostic"; `glossary.njk` "Soleur coined"; `company-as-a-service.njk` "a leading company…" ×2. |
| F17 | P3 | Unsourced "70%"; "420+ PRs" | #9111 | **STILL OPEN** | `pricing.njk` "the other 70% of running a company" (visible and JSON-LD); "420+ PRs across all 8 domains"; `compare-soleur-vs-cursor.njk` "the other 70 percent". |
| F18 | P3 | "This Is the Way" label | — | **STILL OPEN** | `index.njk` problem-section label. |
| F19 | P3 | Stale `last_updated` on agents/skills | #7180, #8468 | **PARTIAL** | `agents.njk` 2026-06-01 and `skills.njk` 2026-06-15 are unchanged. |
| N2 | P3 | "Running autonomously" | — | **STILL OPEN** | `index.njk` "every department, running autonomously on your command."; `vision.njk` "every department running autonomously on command." |
| N3 | P3 | Footer links to developer troubleshooting page | — | **STILL OPEN** | `_data/site.json` still links `known-external-tools`. |
| N4 | P3 | Pricing waitlist H2 says product is ready | — | **STILL OPEN** | `pricing.njk` "Your AI organization is ready." |
| N12 | P3 | Hub post superlative and overclaim | — | **STILL OPEN** | `2026-10-23-agentic-verification-checklist-shipped.md` "among the most followed…"; "Every row of the checklist arrived with…". |
| N13 | P3 | "Role Cluster" label; undated role pages | — | **STILL OPEN** (wider) | "Role Cluster" now confirmed on `ai-cmo.njk` too, as well as `ai-cto.njk` and `solo-founder-ai-stack.njk`. None of the three has `date` or `last_updated`. |
| N14 | P3 | "Third time" used for two events | — | **STILL OPEN** | `2026-11-03-first-property-test-found-real-bug.md`, two "third time" sentences. |

**Tally of the 33 prior findings:** 0 FIXED, 3 PARTIAL (F9, F14, F19), 7 WORSE (N6, F11, F3, N7, F2, N8, N10), 23 STILL OPEN.

### Tracked issues named for this run

| Issue | Topic | Status 11-02 | Note |
|---|---|---|---|
| #11133 | Homepage/pricing developer register (P0) | STILL OPEN | Hero test review is tomorrow. See N5. |
| #11132 | Future-dated posts live early (P0) | WORSE | See N6 and A3. |
| #11134 | Arc titles target developer queries | WORSE | See N7. |
| #11136 | Arc hygiene (series box, repeated lesson, jargon) | WORSE | See N8 to N11. |
| #11138 | `last_updated` bumped without fact review | STILL OPEN | See N1. |
| #9112 | Hero leads with CaaS jargon | STILL OPEN | See F7. |
| #9111 | Pricing autopilot / "ready to sign" claim | STILL OPEN | See F10, F17. |
| #9109 | Lifecycle described 3 ways | STILL OPEN | `getting-started.njk` says "a structured 6-step workflow" and "brainstorm → plan → work → review". `skills.njk`, `company-as-a-service.njk` and `compare-soleur-vs-cursor.njk` say "brainstorm, plan, implement, review". `company-as-a-service.njk` also has "brainstorm-plan-implement-review". |
| #9104 / #9105 | Blog index targeting and categories | STILL OPEN / WORSE | See F1, F2. |
| #9103 | Inc.com "As seen in" | **Appears FIXED** | A case-insensitive search for "as seen", "seen in" and "featured" across `.njk/.json/.js/.md` in `plugins/soleur/docs/` finds nothing. `index.njk` now presents Inc. as an attributed, linked quote ("Inc. report by Ben Sherry, May 23, 2025"). Confirm live, then close. |
| #9499 | AI CMO costs | STILL OPEN | See F8. |
| #9500 | Model-support claim | PARTIAL, regressing | See F9, A1, A4. |
| #8466 | Publishing stopped | PARTIAL | Cadence restored; gap pieces still unpublished. |

## Per-Page Analysis

### 1. Homepage (`/`, `plugins/soleur/docs/index.njk`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" / "Stop hiring. Start delegating." Both strong. |
| Meta | "Company-as-a-Service for solo founders. AI agents across 8 departments…" leads with an unfamiliar category term (#9112). |
| Detected keywords | AI agents for solo founders, Company-as-a-Service (×5 above the fold), self-hosted, coding harness, Claude Code, Grok Build, Codex, Devin CLI, OpenCode, plugin, MCP |
| Keyword alignment | Strong title; weak meta and hero. "Harness" appears 9 times and "plugin" 6 times, including 3 FAQPage answers (#11133). |
| Search intent | Commercial, with some informational. The FAQ matches both. |
| Readability | **Unchanged since 10-26.** A founder who does not code meets "coding harness" plus 5 product names right under the main button. The tool list (5) is now also out of date against getting-started (6). |
| Brand note | The hero-test revert trigger ("hero copy drifts toward developer register") is still met on the day before the review. |

### 2. Pricing (`/pricing/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." Strong. |
| Intent | Transactional. Matches. |
| Readability | "Harness" in the free-version FAQ (#11133). "Ready to sign" and "autopilot" (#9111). Unsourced "70%" and "420+ PRs" (F17). "Your AI organization is ready." (N4). Lists 5 tools. |

### 3. Getting Started (`/getting-started/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Get Started with Soleur — Install Your AI Organization in Two Commands" / "The AI that already knows your business." |
| Keyword alignment | Misaligned (#9107). "Two Commands" is now true for 1 of 6 tools. |
| Intent | Split three ways: install, waitlist, and the self-hosted anchor from the homepage. |
| Readability | **Worse (#2669).** It now has 6 install blocks. The new Antigravity block names five internal tool primitives and a manifest path, and calls Soleur "an Antigravity plugin" in visible prose (brand Don't: "plugin" outside literal commands). The body says 6 tools; the FAQ and JSON-LD say 5 (A1). The definition paragraph and citations near the top are still good. |

### 4. Blog index (`/blog/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "Blog" |
| Alignment | Targets developer queries, against the Blog note (#9104). |
| IA | Newest first. With no date gate, the first card is dated **December 3, 2026** (#11132). Category misfiles have grown (#9105): a product announcement sits under "What is Company-as-a-Service?" and a founder post sits under "Engineering Deep Dives". |

### 5. About, Vision, Agents, Skills, Community

These are unchanged since 2026-10-26. Status is in the table above (F6, F9, F12, F13, F15, F16, F19, N2). One new note: `about.njk` "running in Claude Code today" now understates support (6 tools) and should use the same line as the other pages (A1).

### 6. Pillar and role pages

| Page | Alignment | Notes |
|---|---|---|
| `/company-as-a-service/` | Strong for "Company-as-a-Service (CaaS)" | F4 (ARR ×2), "a leading company…" ×2 (#6085), lifecycle wording (#9109). |
| `/ai-agents-for-solo-founders/` | Strong | F4 (ARR). |
| `/ai-cmo/` | Strong for "AI CMO" | $240K vs $290K (#9499). "Role Cluster" label (N13). |
| `/ai-cto/` | Strong; the template for sourced cost figures | "Role Cluster" label, no date (N13). |
| `/solo-founder-ai-stack/` | Strong | "Role Cluster", no date, unsourced "20-Person Team" (N13). |
| `/compare/soleur-vs-cursor/` | Strong for "Soleur vs Cursor" | ARR stated as fact (F4). The tool list says 5 (A1). |

### 7. Blog posts dated 2026-10-23 or later

The Blog note applies in full to every post below. "New" marks posts not present in the 2026-10-26 sweep.

| Post (date) | Title / seoTitle | Target query detected | Intent | Founder-problem title? | Opening | Jargon / proof-point issues | CTA | Verdict |
|---|---|---|---|---|---|---|---|---|
| **New:** Vendor lock-in (10-23) | "What Happens to Your Business When Your AI Provider Changes the Rules?" / "Own Your AI Team Without Vendor Lock-In \| Soleur" | AI vendor lock-in, own your AI data | Informational / commercial | **Yes** | **Strong**: "You are three months into building your company… Then on a Tuesday morning, the provider changes its pricing model" | "repository", "Git", "harness", "open-weights", "Ollama, llama.cpp" (in FAQPage text). "67 specialist agents" hard-coded (brand rule: soft floor). "Soleur eliminates that risk". Tool count is 6 in the body and 5 in the FAQ. | "Get started" → `/getting-started/` (the install manual, which the Blog note forbids) | Good founder post. Fix facts and CTA (A4). |
| **New:** Antigravity (10-26) | "Run Your AI Company on Google Antigravity Without Losing Your Business Memory" / "Soleur on Google Antigravity CLI — Run an AI Team on Any Harness" | Google Antigravity CLI (developer, navigational) | Navigational / informational (developer) | Partly: the title names memory loss, but the seoTitle and meta name the mechanism | Adequate: "every time a faster model or a more powerful harness launches, switching means leaving your company's context… behind" | "agentic coding tools", "harness" ×3, "native reactive wakeups", "repository". "8-department AI team" but the body lists 6. "Devin" vs "Devin CLI". Reuses another post's OG image. About 330 words, no FAQ, no outside source, no Gemini support source. | **None** (only the GitHub PR link) | Product announcement; belongs in the changelog or GitHub, or needs a founder rewrite (A2). |
| Hub (10-23) | unchanged | — | — | Partly | Strong | N12 still open | Waitlist | Fact fixes only. |
| 102 guardrails (10-27) | unchanged | guardrails, repo | Informational (developer) | No | Good | N11 | Waitlist | Now on its date; retitle window closed (#11134). |
| Property test (10-29) | unchanged | property test | Informational (developer) | No | Good | N11 | Waitlist | Now on its date; retitle window closed (#11134). |
| First property test (11-03) | unchanged | property test | Developer | No | Good | "harness" in the meta | Waitlist | Retitle **today** (dated tomorrow). |
| Recurring job (11-04) | unchanged | audit business automations | Informational | **Yes** | Best on site | "Idempotence", empty FAQ (N9) | Try Soleur | Fix N9 before 11-04. |
| Map that can't drift (11-05) | unchanged | feature map | Unclear | Weak | Strong | N11 | Waitlist | Retitle (#11134). |
| Test the migration (11-10) | unchanged | migration, schema | Developer | No | Good | N11 | Waitlist | Retitle (#11134). |
| Agent map (11-12) | unchanged | — | Unclear | Weak | Good | N11 | Waitlist | Retitle (#11134). |
| Flaky test (11-17) | unchanged | flaky test | Developer | No | Good | N11 | Waitlist | Retitle (#11134). |
| **New:** Green means something (11-19) | "First We Made 'Green' Mean Something. Then We Made It Fast." / "We Made Green Mean Something, Then Made It Fast" | — (our story; no founder query) | Informational | **No**: our work ("We made…") | **Good**: "a green check mark is the bargain you made… what does that green actually prove?" | Engineering metrics the Blog note forbids: "nearly 700 automated checks", "twelve merges, zero broken mains", "1.88 times faster". Jargon: "fixture", "soak test", "bootstrap problem", "serial", "census", "ratchet". Duplicate FAQ (N10). Wrong series box (N8). Links to the unpublished 12-03 post (A3). | Waitlist | Retitle and trim metrics before 11-19 (#11134, #11136). |
| **New:** Alarm never rings (12-03) | "Your Alarm Passed Every Rehearsal. In Real Life It Never Rings." / "Your Error Alerts Can Pass Every Test and Never Fire" | error alerts not firing, test passed but broke in production | Informational | **Yes** | **Strong**: "Somewhere in your business there is an alarm you were told works." Plain analogies (a note passed down a line; a translator who strips the letterhead). | Light. "Nine scheduled jobs" is a factual count, which is fine. | — | **Model arc post.** Only fix: its date (31 days ahead) and the series box (N8). |

**Searchable vs shareable:** the 3 new posts are 2 searchable (vendor lock-in, alarm) and 1 announcement (Antigravity, neither). 11-19 is shareable in intent (build-in-public) but uses engineering metrics instead of founder proof points.

## Keyword Notes

WebSearch was blocked, so no new volume or difficulty data was gathered. Relevance and intent below are judged against the Blog note reader (a non-technical solo founder). The base keyword set is still the 2026-05-25 research, now 161 days old.

| Keyword / query | Intent | Relevance | Currently targeted by | Note |
|---|---|---|---|---|
| AI vendor lock-in / switch AI provider without losing data | Informational / commercial | **High** | 10-23 vendor-lock-in post (seoTitle) | Good target. Add "own your company's data" to the H2s. |
| Google Antigravity CLI | Navigational (developer) | Low for blog ICP | 10-26 Antigravity post | Developer query; belongs in the docs or changelog. |
| run AI team on Gemini | Commercial | Medium | Antigravity meta (implied) | Usable founder query, but only if Gemini support is sourced. |
| error alerts not working / alert never fired | Informational | Medium-high | 12-03 seoTitle | Founder version of "error propagation". Good. |
| can I trust AI test results / what does "all checks passed" mean | Informational | **High** | 11-19 FAQ only | Use it in the 11-19 seoTitle (R-6). |
| can I trust AI output | Informational | **High** | None (hub partly) | Still the top unclaimed founder query for the arc (content plan P1). |

## Issues

Severity: **P0** = wrong or misleading on a primary surface now, or a pre-declared revert trigger met. **P1** = blocks discoverability or conversion for the ICP. **P2** = accuracy or alignment gap. **P3** = polish.

| ID | Sev | Defect | Evidence (page + quote) | Fix | Issue |
|---|---|---|---|---|---|
| N6 | **P0** | Future-dated posts live before their dates; now up to 31 days early | `blog/2026-12-03-alarm-passed-every-rehearsal-never-rings.md` `date: 2026-12-03`; `blog/2026-11-19-first-we-made-green-mean-something.md` `date: 2026-11-19`; plus 11-03 to 11-17. `eleventy.config.js` has no date filter. `deploy-docs.yml` has no `schedule:`. | Add a date gate: exclude `date > now` from `collections.blog` and set `permalink: false` (via `blog.11tydata.js`). Add a daily `schedule:` to `deploy-docs.yml`. Apply the same filter to the feed and sitemap. | #11132 (new evidence) |
| N5 | **P0** | Homepage and pricing in developer register; hero-test revert trigger met the day before review | `/`: "Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode"; "Soleur ships as a plugin for your own coding harness"; FAQ "run `/soleur:go` inside your own harness". `/pricing/`: "You run it inside your own harness". | Apply the R-1 rewrites today. If they cannot ship before 2026-11-03, annotate #9588 that the trigger was met on about 2026-10-22 and was still met at review. | #11133 |
| F11 | P1 | Hero button lands in a 6-tool terminal manual | `/getting-started/#self-hosted`: 6 install blocks; "Soleur loads as an Antigravity plugin via `.antigravity-plugin/plugin.json`"; OpenCode `CLAUDE_PLUGIN_ROOT` paragraph | Put a plain "What you need" paragraph first (R-3). Collapse the per-tool blocks under "Setup by tool", with Claude Code open. Move the capability caveats to the per-tool guides. | #2669 |
| F3 | P1 | "Two Commands" vs waitlist vs "Nothing to install" | `/getting-started/` seoTitle "Install Your AI Organization in Two Commands"; FAQ "Nothing to install." | R-3. | #9107 |
| N7 | P1 | Arc titles target developer queries; 5 remaining spokes and 11-19 still pre-date | 11-03 "The First Property Test We Wrote Found a Real Bug" (dated **tomorrow**); 11-05, 11-10, 11-12, 11-17 unchanged; 11-19 "First We Made 'Green' Mean Something" | Retitle while still unpublished, using the R20 table in the 10-26 audit plus R-6 below. Keep the slugs. 10-27 and 10-29 are now past their dates, so they get fact fixes only. | #11134 |
| F1 | P1 | Blog index targets developer queries | `/blog/` "…Agentic Engineering, and Building at Scale With AI Teams" | R-4. | #9104 |
| F2 | P1 | Founder posts misfiled by tag-driven categories | Vendor-lock-in post in "Engineering Deep Dives"; Antigravity announcement in "What is Company-as-a-Service?" | Add a "Running Your Company" category keyed on `solo-founder`. Retire the catch-all "Engineering Deep Dives". | #9105 |
| F4 | P1 | Competitor revenue stated as fact | `/compare/soleur-vs-cursor/` "Cursor reached roughly 1 billion dollars in annual recurring revenue"; `/company-as-a-service/`; `/ai-agents-for-solo-founders/`; 2 blog posts | Attribute in the sentence ("CNBC reported in February 2026 that Cursor…") or replace with funding/valuation. | #7179 |
| F5 | P1 | "9 hats / nine" vs 8 departments | `/` FAQ "wearing 9 hats who want to hand off 8"; tanka, devin, one-person-billion posts | Use "doing 8 jobs" (brand pain-point framing). | #8462 |
| F7 | P1 | Hero/meta lead with CaaS | `/` meta "Company-as-a-Service for solo founders…" | R-2 after the 11-03 review. | #9112 |
| F6 | P1 | Skills title brand-only; H1 technical | `/skills/` "Soleur Skills" / "Agentic Engineering Skills" | R-5. | #5601 |
| A1 | P2 | **Supported-tool count disagrees: 6 in getting-started body, 5 everywhere else, including FAQPage text** | `/getting-started/` body "Claude Code, Grok Build, Codex, Devin CLI, OpenCode, and Google Antigravity CLI"; its FAQ "Claude Code, Grok Build, Codex, Devin CLI, or OpenCode"; `/`, `/pricing/`, `/compare/soleur-vs-cursor/` list 5; `/about/` "running in Claude Code today"; the vendor-lock-in post has 6 in the body and 5 in its FAQ | Stop listing tools in first-contact copy (R-1: "the AI workspace you already use"). Keep the one authoritative list on `/getting-started/` and update its FAQ and JSON-LD to match. Add the list to the drift test that pins the tool sentence. | **NEW** (related #9500) |
| A2 | P2 | **Antigravity post is a mechanism-led product announcement on the founder blog** | `/blog/run-your-ai-company-on-google-antigravity/` seoTitle "Soleur on Google Antigravity CLI — Run an AI Team on Any Harness"; meta "Soleur now runs natively on Google Antigravity CLI… on Gemini models"; "8-department AI team" while listing 6 departments; no CTA, no FAQ, about 330 words | Fact fixes now (scope rule): list all 8 departments or drop the count; source or remove "Gemini models"; add a founder CTA ("Join the waitlist" or a related founder post). Change seoTitle and meta only if the post counts as unpublished, otherwise record the miss. Going forward, route tool-support announcements to the changelog/GitHub (Blog note > Where technical detail goes). | **NEW** |
| A3 | P2 | **Forward link to a post a month in the future** | `/blog/first-we-made-green-mean-something/` links "[Your Alarm Passed Every Rehearsal…]({{ site.url }}/blog/alarm-passed-every-rehearsal-never-rings/)"; target `date: 2026-12-03` | When the date gate lands, either re-date 12-03 before 11-19 or render the link only if the target is in `collections.blog`. Add a link check for links to unpublished posts to the gate PR. | #11132 (new evidence) |
| A4 | P2 | **Vendor-lock-in post overclaims model choice and sends founders to the install manual** | `/blog/own-your-ai-team-without-vendor-lock-in/` meta "an 8-department AI team they actually own — on any model they choose. Start building."; "Soleur eliminates that risk"; "(67 specialist agents across 8 departments)"; CTA "[Get started with Soleur](https://soleur.ai/getting-started/)" | Fact fixes: meta "…on the AI provider you choose" plus a hosted caveat; "Soleur removes that dependency"; "60+ AI specialists" (soft floor); CTA "Join the waitlist" or link the 11-04 post; FAQ tool list matches the body. | **NEW** (related #9500) |
| F9 | P2 | Vision cards present model routing as shipped | `/vision/` "Soleur selects the best model for each task. Claude for coding. GPT-4o for strategy." | R10 (10-26 audit). | #6376, #9500 |
| F10 | P2 | "Ready to sign" / "autopilot" | `/pricing/` | R11 (10-19 audit). | #9111 |
| F12 | P2 | Agents "trained" | `/agents/` ×3 | R13 (10-26 audit). | #6378 |
| F8 | P2 | AI CMO $240K / $290K | `/ai-cmo/` seoTitle vs meta | One sourced figure, following the `/ai-cto/` pattern. | #9499 |
| F13 | P2 | Community title/H1 generic | `/community/` | R15 (10-19 audit). | #6377 |
| F14 | P2 | Founder gap pieces unpublished | 0 of 4 planned pieces | Schedule "Can I trust what my AI produces?" and "Contracts as a solo founder" before the next arc spoke. | #8466 |
| N1 | P2 | Freshness dates not backed by fact review; Antigravity added without a date bump | 7 pages at 2026-10-22; `getting-started.njk` changed on 10-26 | Fix facts, then re-date in the same PR. | #11138 |
| N8 | P2 | Wrong series box, now on 10 posts | `pillar: billion-dollar-solo-founder` on all arc posts plus 11-19 and 12-03 | R21 (10-26 audit); add 11-19 and 12-03 as cluster members. | #11136 |
| N9 | P2 | Empty visible FAQ on the 11-04 post (dated in 2 days) | "## Frequently asked questions" followed directly by JSON-LD | R22 (10-26 audit), before 11-04. | #11136 |
| N10 | P2 | Lesson and FAQ repeated across the arc | 11-19 "Can an automated check itself be wrong?" = 10-27 FAQ | Replace the 11-19 FAQ with "How do I know if 'all checks passed' means anything?". | #11136 |
| N11 | P2 | Undefined jargon and engineering metrics | 11-04 "Idempotence is a property."; 11-19 "nearly 700 automated checks", "twelve merges, zero broken mains", "soak test", "fixture" | R23 (10-26 audit) plus R-6. | #11136 |
| F15 | P3 | About filler; "agentic engineering"; Claude-only line | `/about/` "The founder behind Soleur."; "running in Claude Code today" | R16 (10-19 audit) plus the A1 line. | — |
| F16 | P3 | Superlatives; CaaS origin conflict | `/vision/`, `/glossary/`, `/company-as-a-service/` | Pick one origin line. | #9501, #6085 |
| F17 | P3 | "70%" and "420+ PRs" | `/pricing/`, `/compare/soleur-vs-cursor/` | Source or remove the 70%; replace "420+ PRs" with "every department". | #9111 |
| F18 | P3 | "This Is the Way" | `/` | "The Problem". | — |
| F19 | P3 | Agents/skills dated June | `/agents/`, `/skills/` | Re-date after F6/F12. | #7180, #8468 |
| N2 | P3 | "Running autonomously" | `/`, `/vision/` | "…working on your command, with your approval". | — |
| N3 | P3 | Footer links developer page | `_data/site.json` | R17 (10-19 audit). | — |
| N4 | P3 | "Your AI organization is ready." | `/pricing/` | "Your AI organization is almost ready." | — |
| N12 | P3 | Hub superlative and overclaim | 10-23 hub | Fact fixes per 10-26. | — |
| N13 | P3 | "Role Cluster" label; undated role pages | `/ai-cmo/`, `/ai-cto/`, `/solo-founder-ai-stack/` | "Founder Guide" label; add `date`/`last_updated`. | — |
| N14 | P3 | "Third time" used twice | 11-03 post | Pick one. | — |
| #9109 | P3 | Lifecycle described 3 ways | "6-step workflow" / "brainstorm → plan → work → review" / "brainstorm, plan, implement, review" | One wording across pages; in general-register pages use "plan, build, review, remember". | #9109 |
| A5 | P3 | **Two posts appear to have been added after 2026-10-26 with earlier dates** | `2026-10-23-own-your-ai-team-without-vendor-lock-in.md` and `2026-10-26-run-your-ai-company-on-google-antigravity.md` were absent from the 10-26 audit's sweep of every post dated 2026-10-19 or later | Unconfirmed (git log blocked). If backdated, set `date` to the real publish date so the feed and newest-first listing surface them. | **NEW** (unverified) |
| A6 | P3 | **Stray `pillar` tag on 11-19** | `tags: … - pillar` | Remove the tag; series membership comes from `pillar:` frontmatter. | **NEW** |

## Rewrite Suggestions (title / meta / H1)

All rewrites use the general register: outcome first, the founder as decision-maker, no "plugin", "harness", "AI-powered", "just/simply", or exact agent counts in static prose. Rewrites R1 to R23 from the [2026-10-26 audit](./2026-10-26-content-audit.md) still apply. Only new or changed rewrites are listed here.

| ID | Page | Element | Current | Suggested | Rationale |
|---|---|---|---|---|---|
| R-1 | `/` | Hero note (under main button) | "Source-available. Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode; you pay for your own model usage." | "Source-available. Runs on your own computer inside the AI workspace you already use. You pay your AI provider directly." | Removes the revert-trigger copy (#11133) and the tool count that goes stale with each new tool (A1). |
| R-1 | `/` | "How do I get started?" FAQ (+ JSON-LD) | "Get the self-hosted version and run `/soleur:go` inside your own harness…" | "Two ways: run the free self-hosted version on your own computer today (the getting started page walks you through it), or join the waitlist for the hosted version. Then describe what you need in plain words, and your AI team routes it to the right specialists." | FAQPage text is quoted by answer engines word for word, so it must be in founder language. |
| R-1 | `/pricing/` | "Is there a free version?" FAQ (+ JSON-LD) | "You run it inside your own harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode — and pay for your own model usage." | "It runs on your own computer inside an AI workspace such as Claude Code or Codex, and you pay your AI provider for what you use." | Same as above. |
| R-2 | `/` | Meta description (after the 11-03 review) | "Company-as-a-Service for solo founders. AI agents across 8 departments — engineering, marketing, legal…" | "You're doing 8 jobs. Soleur gives you an AI team for marketing, legal, finance and operations that remembers your business. You approve; it executes." | Pain-point framing (brand guide primary framing) plus trust scaffolding (#9112). |
| R-3 | `/getting-started/` | seoTitle | "Get Started with Soleur — Install Your AI Organization in Two Commands" | "Get Started with Soleur — Run Your AI Team Today or Join the Hosted Waitlist" | True for all 6 tools and both paths (#9107). |
| R-3 | `/getting-started/` | Meta | "Install Soleur in two commands and run a full AI organization…" | "Two ways to start: run the free self-hosted version on your own computer today, or join the waitlist for hosted Soleur. Your AI team for marketing, legal, finance and operations remembers your business." | Drops "install" and a count that is no longer true. |
| R-3 | `/getting-started/` | Section label | "Source-available. Install in your own harness." | "Source-available. Runs on your own computer." | Removes "harness" from the landing spot of the hero button (#2669). |
| R-4 | `/blog/` | seoTitle / meta / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "…engineering deep dives…" / "Blog" | "Running a Company Alone: Playbooks for Solo Founders \| Soleur Blog" / "Practical playbooks for founders running every department alone: marketing, contracts, money, and how to trust the AI work you delegate." / "Running a company alone, without doing everything alone" | Targets founder queries (#9104); the H1 uses the brand's general thesis. |
| R-5 | `/skills/` | seoTitle / H1 | "Soleur Skills" / "Agentic Engineering Skills" | "AI Workflows for Every Department \| Soleur Skills" / "The workflows your AI team follows to get things done" | Uses the brand glossary definition of "skills" (#5601). |
| R-6 | 11-19 post (unpublished) | Title / seoTitle / meta | "First We Made 'Green' Mean Something. Then We Made It Fast." / "We Made Green Mean Something, Then Made It Fast" / "Our automated checks said 'green' while four different lies hid inside the scoreboard…" | "When 'All Checks Passed' Doesn't Mean It Works" / "What 'All Checks Passed' Really Proves (and When It Doesn't)" / "A green check mark can hide checks that never ran and failures quietly excused. Here are four ways a 'pass' lies, and the one question to ask before you trust it." | Names the founder's problem (Blog note > Open with their problem) and targets "can I trust AI test results". Also replace "nearly 700 automated checks" with "hundreds of automated checks", and "twelve merges, zero broken mains" with "a dozen changes, none of which broke the live product". |
| R-7 | 11-03 post (dated tomorrow) | Title / seoTitle | "The First Property Test We Wrote Found a Real Bug" | "The Mistake Your Checklist Can't Imagine" / "The Mistake Your Checklist Can't Imagine: Rules Beat Remembered Cases" | Carried from R20; **last day** before the date passes. |
| R-8 | Antigravity post | Meta (fact fix) | "Soleur now runs natively on Google Antigravity CLI. Run your 8-department AI team on Gemini models…" | "Soleur now also runs on Google's Antigravity, so you can choose Google's AI for your AI team and keep your company's memory in files you own." | Removes the unsourced "Gemini models" claim and the miscount. If the post counts as published, apply only the count and Gemini fixes. |
| R-8 | Antigravity post | Body list (fact fix) | "AI specialists across marketing, legal, finance, operations, product, and engineering" | "AI specialists across all eight departments: engineering, marketing, legal, finance, operations, product, sales and support" | Matches the "8-department" claim. |
| R-9 | Vendor-lock-in post | Meta (fact fix) | "…run an 8-department AI team they actually own — on any model they choose. Start building." | "…run an 8-department AI team they actually own, on the AI provider they choose. Join the waitlist." | "Any model" is not true for hosted (Anthropic-only). The CTA moves from install to waitlist (#9500). |
| R-9 | Vendor-lock-in post | CTA | "Ready to build a company you actually own? [Get started with Soleur](https://soleur.ai/getting-started/)." | "Ready to build a company you actually own? [Join the Soleur waitlist](https://soleur.ai/pricing/#waitlist)." | Blog note > Call to action: never an install step. |

## Top 5 Actions

1. **Today, before the 2026-11-03 hero review: ship R-1 on `/` and `/pricing/` (#11133).** If it cannot merge in time, annotate #9588 that the developer-register revert trigger was met throughout the window.
2. **Land the date gate (#11132), and handle the 11-19 → 12-03 forward link in the same PR (A3).** Without it, December-dated content stays live and the arc's retitle window keeps closing: 11-03 passes tomorrow.
3. **Before each spoke's date, retitle the remaining arc posts and fix N9 (#11134, #11136).** Do 11-03 today, 11-04's empty FAQ before Wednesday, and apply R-6 to 11-19. Use 12-03 as the template: founder problem in the title, seoTitle and meta.
4. **Make one supported-tools statement and stop listing tools in first-contact copy (A1, A4, #9500).** Fix the getting-started FAQ and JSON-LD (5 → 6), `/about/`, compare-cursor, and the vendor-lock-in post's meta ("any model") and CTA.
5. **Move tool-support announcements off the founder blog (A2).** Fact-fix the Antigravity post (department count, Gemini claim, add a CTA). Send future integration launches to the changelog/GitHub, and spend the blog slot on a gap piece ("Can I trust what my AI produces?", #8466).

## Caveats

- WebFetch, WebSearch and `git log` were all blocked by cron containment, so no rendered page was checked. The status of #9103 and A5 comes from source alone and should be confirmed live.
- Line positions shift between runs, so evidence cites quoted text and file names rather than line numbers wherever possible.
- Whether the arc spokes count as "published" (which decides how far they may be rewritten) is still the CMO decision recorded on #11134. The suggestions above assume posts dated after today are unpublished.
