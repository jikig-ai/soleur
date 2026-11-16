---
title: "Content Audit: soleur.ai — 2026-11-16"
date: 2026-11-16
type: content-audit
site: https://soleur.ai
---

# Content Audit: soleur.ai — 2026-11-16

| Item | Detail |
|---|---|
| Date | 2026-11-16 (scheduled CI run, unattended) |
| Scope | Keyword alignment, search-intent match and readability for `/`, `/pricing/`, `/getting-started/`, `/blog/`, `/agents/`, `/skills/`, `/about/`, `/vision/`, `/community/`, both comparison pages in the "Learn" nav (`/compare/soleur-vs-cursor/`, `/compare/soleur-vs-devin/`), the pillar pages, and every blog post dated 2026-10-23 or later (13 posts). Key posts read in full this run: Antigravity (10-26), vendor lock-in (10-23), recurring job (11-04), flaky test (11-17), green (11-19), alarm (12-03). |
| Method | **Source only.** WebFetch on `https://soleur.ai/` was refused by the cron-containment hook (`cron-containment: tool class not permitted: WebFetch`). This is the 18th run in a row without a live fetch. WebSearch was not attempted (it was refused under the same hook on 2026-11-02). `git log` was not used (forbidden for this run). The Eleventy source in `plugins/soleur/docs/` was read with Read, Grep and Glob. "Live" is inferred from the build config: `eleventy.config.js` has no date filter, and `.github/workflows/deploy-docs.yml` deploys on `push`, `workflow_run` and `workflow_dispatch`. |
| Brand guide | `knowledge-base/marketing/brand-guide.md` was read: Identity, Voice (Do's/Don'ts, Audience Voice Profiles, Value Proposition Framings), Channel Notes > Website / Landing Page (including the 2026-10-06 hero CTA test note), and Channel Notes > Blog. All rewrites use the **general register**: founder first, no "plugin", "harness", "AI-powered", "just" or "simply", and no exact agent counts in static prose. |
| Prior audit | [2026-11-02-content-audit.md](./2026-11-02-content-audit.md) |
| Out of scope | JSON-LD validity, meta-tag mechanics, sitemap, llms.txt and OG files belong to seo-aeo-analyst. JSON-LD *text* is assessed only for what it says, because answer engines quote it word for word. This is a content audit, so no SAP or 8-component AEO scorecard is produced. |

Priority key: **P0** = wrong or misleading on a primary surface now, or a pre-declared revert trigger is met. **P1** = blocks discoverability or conversion for the ICP. **P2** = accuracy or alignment gap. **P3** = polish.

## Executive Summary

**The first copy fixes in three weeks have landed, but none of them is on a P0 or P1.** Between 11-02 and today, the getting-started "Nothing to install" FAQ and the vendor-lock-in FAQ were updated from 5 tools to 6. The Antigravity post gained a full department list, a new seoTitle, a FAQ and a call to action. The homepage, pricing, blog index, skills, agents and vision source still contains every sentence cited on 11-02. **No new post has been added since 11-02**, so the publishing queue ends on 2026-12-03.

**Top 5 findings:**

1. **N5 + B1 (P0 + P1): the homepage is still in developer register, and the hero test review passed without a recorded outcome.** The hero note still reads "Runs inside your own coding harness — Claude Code, Grok Build, Codex, Devin CLI, or OpenCode". The homepage FAQ still contains `/soleur:go`. Pricing still says "You run it inside your own harness". The review date in the brand guide (2026-11-03) is 13 days past. The guide records no outcome, and the "hero copy drifts toward developer register" revert trigger is still met.
2. **N6 (P0): there is still no date gate.** 3 future-dated posts are live: 11-17 (tomorrow), 11-19 and 12-03. 12-03 is 17 days ahead, and its card still heads the blog index. The 11-19 post still links to the 12-03 post (A3). Exposure is smaller than on 11-02 (3 posts, not 8), but the defect will return with the next post dated ahead.
3. **N7 (P1, worse): the retitle window has closed on 4 more arc posts.** 11-03, 11-05, 11-10 and 11-12 reached their dates with developer titles ("The First Property Test We Wrote Found a Real Bug", "Test the Migration, Not Just the Schema"). The last two chances are **11-17 (tomorrow)** and **11-19 (in 3 days)**. R-10 and R-6 below give ready replacements.
4. **B2 (P1, new): founder-facing comparison and pillar pages end on a terminal install.** `/compare/soleur-vs-devin/`, `/compare/soleur-vs-cursor/`, `/company-as-a-service/` and `/ai-agents-for-solo-founders/` close with a `claude plugin install soleur@soleur-marketplace` code block. That path works for 1 of the 6 supported tools. The Website note says: "Do not reference CLI installation as the primary CTA in any new landing page content."
5. **A1/A2/A4 (P2, partly fixed): the supported-tool story is half-repaired, and the Antigravity fix added a new unsourced claim.** The site now says 6 tools in 4 places, 5 tools in about 10 places, and "Claude Code" alone in 2. The Antigravity post's new FAQPage answer says "Gemini 2.5 Pro and Gemini Flash", with no source (B4). Answer engines will quote that text as written.

**Headline counts this run:** 2 P0, 11 P1, 17 P2, 15 P3 (45 total). 40 are carried from 11-02 and 5 are new (B1 to B5).

## Delta since 2026-11-02

Status key: **FIXED**, **PARTIAL** (improved this period but not closed), **STILL OPEN**, **WORSE** (still open and the evidence or exposure has grown), **UNVERIFIABLE**.

**Tally of the 40 findings carried from 11-02:** 0 FIXED, 4 PARTIAL (F3, A1, A2, A4), 3 WORSE (N7, N9, F14), 1 UNVERIFIABLE (A5), 32 STILL OPEN.

| Prior ID | Prior P | Finding | Status 11-16 | Evidence (current source) |
|---|---|---|---|---|
| N6 | P0 | Future-dated posts live early | **STILL OPEN** (less exposure) | `eleventy.config.js` has no date filter and no custom collection. `blog.json` is the only data file in `blog/`; there is no `blog.11tydata.js`. `deploy-docs.yml` has no `schedule:`. Future-dated posts are now 11-17, 11-19 and 12-03. |
| N5 | P0 | Homepage and pricing in developer register | **STILL OPEN** | `index.njk`: "Runs inside your own coding harness"; "Soleur ships as a plugin for your own coding harness"; "What the Soleur plugin adds to your coding harness."; `soleur:go` ×4. `pricing.njk`: "You run it inside your own harness" (visible and JSON-LD). |
| F11 | P1 | Hero button lands in a terminal manual | **STILL OPEN** | `getting-started.njk` `#self-hosted` label "Source-available. Install in your own harness."; 6 install blocks; "Soleur loads as an Antigravity plugin via `.antigravity-plugin/plugin.json`". |
| F3 | P1 | "Two Commands" vs waitlist vs "Nothing to install" | **PARTIAL** | The FAQ now names all 6 tools and adds "Setup is two commands on Claude Code; the other harnesses install from this repository". The seoTitle "Install Your AI Organization in Two Commands" and the meta "Install Soleur in two commands…" are unchanged. |
| N7 | P1 | Arc titles target developer queries | **WORSE** | No title changed. 11-03, 11-05, 11-10 and 11-12 passed their dates with developer titles, so their retitle window is closed. 11-17 (tomorrow) and 11-19 are the last open windows. |
| F1 | P1 | Blog index targets developer queries | **STILL OPEN** | `pages/blog.njk` seoTitle "…Agentic Engineering, and Building at Scale With AI Teams"; meta "…engineering deep dives…"; H1 "Blog". |
| F2 | P1 | Founder posts misfiled by tag-driven categories | **STILL OPEN** (misfile moved) | The category logic is unchanged. The Antigravity post's `ai-agents` tag was removed, so it moved from "What is Company-as-a-Service?" into "Engineering Deep Dives". The vendor-lock-in, recurring-job, 11-19 and 12-03 founder posts also land in "Engineering Deep Dives". |
| F4 | P1 | Competitor revenue stated as fact | **STILL OPEN** | "Cursor reached…" still appears in `compare-soleur-vs-cursor.njk`, `company-as-a-service.njk` and `ai-agents-for-solo-founders.njk`. "ARR" or "annual recurring revenue" still appears in `2026-03-19-soleur-vs-cursor.md`, `2026-03-26-soleur-vs-polsia.md` and others. |
| F5 | P1 | "9 hats / nine departments" vs 8 | **STILL OPEN** | `index.njk` FAQ and JSON-LD: "wearing 9 hats who want to hand off 8 of them". The devin, tanka and one-person-billion posts are unchanged. |
| F7 | P1 | Hero and meta lead with CaaS | **STILL OPEN** | `index.njk` meta "Company-as-a-Service for solo founders…"; badge "Company-as-a-Service"; the hero-tagline and hero-sub repeat it. |
| F6 | P1 | Skills title brand-only; H1 technical | **STILL OPEN** | `skills.njk` `title: Soleur Skills`, no seoTitle; H1 "Agentic Engineering Skills". |
| A1 | P2 | Supported-tool count disagrees | **PARTIAL** | Now 6 tools: the getting-started body, the "Nothing to install" FAQ and its JSON-LD, the vendor-lock-in body and FAQ, and the Antigravity post. Still 5 tools: the homepage (×3), the pricing FAQ, the getting-started "differences" FAQ and its JSON-LD, the `/vision/` FAQ, `/community/`, `/compare/soleur-vs-cursor/` and `/compare/soleur-vs-devin/`. 4 tools: the getting-started OS FAQ, which omits Antigravity. Claude Code only: `/about/` "running in Claude Code today" and the compare-devin table "Partial (runs in your Claude Code environment)". The getting-started entry-command JSON-LD also omits Antigravity. |
| A2 | P2 | Antigravity post is a mechanism-led announcement | **PARTIAL** | Fixed: the body now lists "all eight departments"; the seoTitle is now "Run an AI Team on Google Antigravity Without Losing Business Context \| Soleur"; a 3-question FAQ and a CTA were added. Still open: the meta says "Soleur now runs natively on Google Antigravity CLI… on Gemini models"; the CTA's first link is an install anchor (`/getting-started/#google-antigravity-cli`); FAQ answers contain `agy` in backticks and "agentic harness". New claim: see B4. The OG image is still borrowed (`og-ai-team-from-your-codebase.png`). |
| A3 | P2 | Forward link to a post weeks in the future | **STILL OPEN** | The 11-19 post links `/blog/alarm-passed-every-rehearsal-never-rings/` (dated 12-03). |
| A4 | P2 | Vendor-lock-in post overclaims model choice and sends founders to the install manual | **PARTIAL** | Fixed: the FAQ (visible and JSON-LD) now names 6 tools. Still open: the meta "…on any model they choose. Start building."; "Soleur eliminates that risk"; "(67 specialist agents across 8 departments)"; the CTA "[Get started with Soleur](https://soleur.ai/getting-started/)". |
| F9 | P2 | Vision presents model routing as shipped | **STILL OPEN** | `vision.njk` "GPT-4o" card is unchanged. |
| F10 | P2 | "Ready to sign" / "autopilot" | **STILL OPEN** | `pricing.njk` "formatted, footnoted, and ready to sign."; "Your public presence on autopilot." |
| F12 | P2 | Agents described as "trained" | **STILL OPEN** | `agents.njk` "is trained" ×3 (body, FAQ, JSON-LD). The FAQ also says "within Claude Code" only. |
| F8 | P2 | AI CMO cost figure inconsistent | **STILL OPEN** | `ai-cmo.njk` seoTitle "$240K" vs meta "$290K". |
| F13 | P2 | Community title and H1 generic | **STILL OPEN** | seoTitle "Community — Soleur"; H1 "Community". |
| F14 | P2 | Founder-problem gap pieces unpublished | **WORSE** | No new post was added in 14 days (13 post files dated ≥10-23, the same set as on 11-02). 0 of 4 gap pieces are published. Nothing is queued after 12-03. |
| N1 | P2 | `last_updated` not backed by a fact review | **STILL OPEN** | `index.njk`, `pricing.njk`, `getting-started.njk`, `vision.njk` and `about.njk` all show 2026-10-22. getting-started changed after that date (an FAQ edit and an Antigravity block `verified: 2026-10-26`). |
| N8 | P2 | Arc posts show the wrong series box | **STILL OPEN** | `_data/pillars.js` has no arc (trusting-AI-work) entry. 10 posts declare `pillar: billion-dollar-solo-founder`, which is not their series. |
| N9 | P2 | Empty visible FAQ on the recurring-job post | **WORSE** (now live by date) | `2026-11-04-before-your-ai-team-takes-a-recurring-job.md`: "## Frequently asked questions" is followed directly by `<script type="application/ld+json">`. The post reached its date on 11-04. |
| N10 | P2 | Same lesson repeated across the arc | **STILL OPEN** | 11-19 still has "Can an automated check itself be wrong?", copied word for word from the 10-27 FAQ. |
| N11 | P2 | Undefined jargon and engineering metrics | **STILL OPEN** | 11-04 "Idempotence is a property."; 11-19 "nearly 700 automated checks", "twelve merges, zero broken mains", "fixture", "soak", "1.88". |
| F15 | P3 | About filler; "agentic engineering"; Claude-only line | **STILL OPEN** | `about.njk` "running in Claude Code today". |
| F16 | P3 | Superlatives; CaaS origin claims disagree | **STILL OPEN** | `vision.njk`, `glossary.njk`, `company-as-a-service.njk` are unchanged. |
| F17 | P3 | Unsourced "70%"; "420+ PRs" | **STILL OPEN** | `pricing.njk` "the other 70% of running a company" (visible and JSON-LD); "420+ PRs across all 8 domains". |
| F18 | P3 | "This Is the Way" label | **STILL OPEN** | `index.njk` section label. |
| F19 | P3 | Stale `last_updated` on agents and skills | **STILL OPEN** | `agents.njk` 2026-06-01; `skills.njk` 2026-06-15. |
| N2 | P3 | "Running autonomously" | **STILL OPEN** | `index.njk` "every department, running autonomously on your command." |
| N3 | P3 | Footer links to a developer troubleshooting page | **STILL OPEN** | `_data/site.json` footer "Known external tools". |
| N4 | P3 | Pricing waitlist H2 says the product is ready | **STILL OPEN** | `pricing.njk` "Your AI organization is ready." |
| N12 | P3 | Hub post superlative and overclaim | **STILL OPEN** | 10-23 hub is unchanged. |
| N13 | P3 | "Role Cluster" label; undated role pages | **STILL OPEN** | "Role Cluster" on `ai-cto.njk`, `ai-cmo.njk` and `solo-founder-ai-stack.njk`. |
| N14 | P3 | "Third time" used for two events | **STILL OPEN** | 11-03 post, two "It was the third time…" sentences. |
| #9109 | P3 | Lifecycle described 3 ways | **STILL OPEN** | `getting-started.njk` "a structured 6-step workflow"; other pages say "brainstorm, plan, implement, review". |
| A5 | P3 | Two posts possibly backdated | **UNVERIFIABLE** | `git log` was not available to this run. |
| A6 | P3 | Stray `pillar` tag | **STILL OPEN** (wider than reported) | The tag is not only on 11-19. 9 arc posts carry `tags: - pillar` (10-23 hub, 10-27, 10-29, 11-03, 11-05, 11-10, 11-12, 11-17, 11-19). No template reads a `pillar` tag; series membership comes from `pillar:` frontmatter. |

### Tracked issues

| Issue | Topic | Status 11-16 |
|---|---|---|
| #11133 | Homepage/pricing developer register | STILL OPEN. Review date passed (see B1). |
| #11132 | Future-dated posts live early | STILL OPEN (3 posts). |
| #11134 | Arc titles target developer queries | WORSE. 2 windows left (11-17, 11-19). |
| #11136 | Arc hygiene (series box, empty FAQ, repeated lesson, jargon) | STILL OPEN; N9 now live. |
| #11138 | `last_updated` without a fact review | STILL OPEN. |
| #9112 | Hero leads with CaaS | STILL OPEN. |
| #9111 | Pricing "autopilot", "ready to sign", "70%" | STILL OPEN. |
| #9109 | Lifecycle described 3 ways | STILL OPEN. |
| #9104 / #9105 | Blog index targeting and categories | STILL OPEN. |
| #9103 | Inc.com "As seen in" | **Still absent from source.** A case-insensitive search for "seen in" across `plugins/soleur/docs/` finds 0 matches. Close after a live check. |
| #9499 | AI CMO costs | STILL OPEN. |
| #9500 | Model-support claims | PARTIAL; B4 regresses it. |
| #8466 | Founder gap pieces / cadence | WORSE (no new posts in 14 days). |
| #2669 | Hero button lands in a terminal manual | STILL OPEN. |
| #9107 | "Two commands" title | PARTIAL. |
| #7179 | Competitor revenue | STILL OPEN. |
| #8462 | "9 hats" | STILL OPEN. |
| #5601 | Skills title | STILL OPEN. |

## Findings Table

| ID | Priority | Page | Issue | Recommendation |
|---|---|---|---|---|
| N6 | **P0** | `/blog/` and 3 posts | Future-dated posts (11-17, 11-19, 12-03) are live and listed; the 12-03 card heads the index 17 days early | Exclude `date > now` from `collections.blog` and set `permalink: false` for those posts (`blog.11tydata.js`). Apply the same filter to the feed and sitemap. Add a daily `schedule:` to `deploy-docs.yml`. Fix A3 in the same PR. (#11132) |
| N5 | **P0** | `/`, `/pricing/` | "coding harness", "ships as a plugin", `/soleur:go` and "inside your own harness" in hero, compare section and FAQPage text | Apply R-1 (carried). (#11133) |
| B1 | P1 | brand guide → `/` | **NEW.** The hero CTA test review (2026-11-03) is 13 days past. The guide records no outcome, and a revert trigger (developer-register drift) is still met | Record the outcome under the 2026-10-06 note: keep, revert, or extend, with the confound. If kept, ship R-1 so the trigger stops firing. |
| B2 | P1 | `/compare/soleur-vs-devin/`, `/compare/soleur-vs-cursor/`, `/company-as-a-service/`, `/ai-agents-for-solo-founders/` | **NEW.** Commercial-intent pages end on a Claude-Code-only terminal install (`claude plugin install soleur@soleur-marketplace`), against the Website note | Replace the code block with R-11: a waitlist button plus a plain link to getting-started. |
| F11 | P1 | `/getting-started/` | Hero button lands in a 6-tool terminal manual | R-3 (carried): plain "What you need" paragraph first; collapse per-tool blocks under "Setup by tool". (#2669) |
| F3 | P1 | `/getting-started/` | seoTitle and meta still promise "two commands"; the FAQ now concedes this is Claude Code only | R-3 seoTitle and meta. (#9107) |
| N7 | P1 | 11-17, 11-19 posts | Developer and our-story titles; the last 2 open retitle windows close on 11-17 and 11-19 | R-10 (11-17) today; R-6 (11-19) before 11-19. Keep slugs. (#11134) |
| F1 | P1 | `/blog/` | seoTitle and meta target "Agentic Engineering" and "engineering deep dives"; H1 "Blog" | R-4 (carried). (#9104) |
| F2 | P1 | `/blog/` | 5 founder posts and the Antigravity post sit under "Engineering Deep Dives" | Add a "Running Your Company" category keyed on `solo-founder`; retire the catch-all. (#9105) |
| F4 | P1 | compare-cursor, CaaS, AI-agents pillar, 2+ posts | "Cursor reached roughly 1 billion dollars in annual recurring revenue" stated as fact | Attribute in the sentence or use funding and valuation. (#7179) |
| F5 | P1 | `/` FAQ + 3 posts | "wearing 9 hats who want to hand off 8" | "doing 8 jobs" (brand pain-point framing). (#8462) |
| F7 | P1 | `/` | Meta and badge lead with "Company-as-a-Service" | R-2 (carried). (#9112) |
| F6 | P1 | `/skills/` | Title "Soleur Skills"; H1 "Agentic Engineering Skills" | R-5 (carried). (#5601) |
| A1 | P2 | site-wide | Tool count: 6 in 4 places, 5 in about 10 places, Claude Code only in 2 | R-14. Stop listing tools in first-contact copy; keep one authoritative list on getting-started. |
| A2 | P2 | Antigravity post | Meta still says "on Gemini models"; install-first CTA; `agy` and "harness" in FAQ answers | R-8 meta (carried); R-13 FAQ; make waitlist the first CTA link. |
| B4 | P2 | Antigravity post (FAQPage) | **NEW.** "connects natively to Google's Gemini models, including Gemini 2.5 Pro and Gemini Flash" has no source; model names will go stale | R-13: drop model names or cite Google's Antigravity docs. Check that the `github.com/google/antigravity` link resolves (not verified this run). |
| A3 | P2 | 11-19 post | Links to the 12-03 post | Render the link only if the target is in `collections.blog`, or re-date. |
| A4 | P2 | Vendor-lock-in post | "on any model they choose"; "eliminates"; "67 specialist agents"; install CTA | R-9 (carried); "removes that dependency"; "60+ AI specialists". |
| B3 | P2 | `/compare/soleur-vs-devin/` | **NEW (first audit of this page).** The table says "Partial (runs in your Claude Code environment)", although Soleur runs *inside Devin CLI*. The page never says so, even in "Can Devin and Soleur be used together?". The "why it matters now" section rests on the Devin 2 price cut (April 2025, about 19 months old) | R-12. Re-verify current Devin pricing against cognition.ai before the next `last_updated` bump. |
| F9 | P2 | `/vision/` | "GPT-4o for strategy" shown as shipped | R10 (10-26 audit). (#6376, #9500) |
| F10 | P2 | `/pricing/` | "ready to sign", "autopilot" | Add trust scaffolding: "ready for your review". (#9111) |
| F12 | P2 | `/agents/` | "trained" ×3; "within Claude Code" | "Each agent is set up for one function…"; drop Claude-only. (#6378) |
| F8 | P2 | `/ai-cmo/` | $240K vs $290K | One sourced figure. (#9499) |
| F13 | P2 | `/community/` | Generic title and H1 | R15 (10-19 audit). (#6377) |
| F14 | P2 | `/blog/` | 0 new posts in 14 days; queue ends 12-03; 0 of 4 gap pieces | Commission "Can I trust what my AI produces?" and "Contracts as a solo founder" for the slots after 12-03. (#8466) |
| N1 | P2 | 5 core pages | `last_updated` 2026-10-22 not backed by a fact review; getting-started edited after it | Re-date only in the PR that fixes the facts. (#11138) |
| N8 | P2 | 10 arc posts | Wrong series box | Add an arc entry to `pillars.js`. (#11136) |
| N9 | P2 | 11-04 post (live) | Visible "Frequently asked questions" heading with no visible answers | R-15. (#11136) |
| N10 | P2 | 11-19 post | Duplicate FAQ question from 10-27 | Replace with "How do I know if 'all checks passed' means anything?". |
| N11 | P2 | 11-04, 11-19 posts | Jargon and engineering metrics | R-6 metric swaps; define "idempotence" or cut it. |
| F15 | P3 | `/about/` | Filler; "running in Claude Code today" | R16 + R-14 line. |
| F16 | P3 | `/vision/`, `/glossary/`, CaaS | Superlatives; conflicting origin claims | One origin line. (#9501, #6085) |
| F17 | P3 | `/pricing/`, compare-cursor | Unsourced "70%"; "420+ PRs" | Source or remove; "every department". |
| F18 | P3 | `/` | "This Is the Way" label | "The Problem". |
| F19 | P3 | `/agents/`, `/skills/` | June `last_updated` | Re-date after F6 and F12. |
| N2 | P3 | `/`, `/vision/` | "running autonomously" | "…working on your command, with your approval". |
| N3 | P3 | footer | "Known external tools" developer page | R17 (10-19 audit). |
| N4 | P3 | `/pricing/` | "Your AI organization is ready." | "Your AI organization is almost ready." |
| N12 | P3 | 10-23 hub | Superlative and overclaim | Fact fixes per 10-26. |
| N13 | P3 | role pages | "Role Cluster"; no dates | "Founder Guide"; add dates. |
| N14 | P3 | 11-03 post | "third time" ×2 | Pick one. |
| #9109 | P3 | several | Lifecycle described 3 ways | "plan, build, review, remember" in general-register pages. |
| A5 | P3 | 10-23, 10-26 posts | Possible backdating | Verify with git history in an interactive run. |
| A6 | P3 | 9 arc posts | Unused `pillar` tag | Remove the tag from all 9. |
| B5 | P3 | global nav | **NEW.** "Learn" menu has 10 links. 2 of them, "Agentic Engineering" and "Claude Code Plugins", are developer-query pages placed beside founder guides. The homepage "Go deeper" list says "What the Soleur plugin adds to your coding harness." | Move both into a "For developers" group (or the footer). Rewrite the Go-deeper line: "How Soleur runs inside the AI tools developers already use." |

## Per-Page Analysis

### 1. Homepage (`/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur — AI Agents for Solo Founders \| Every Department, One Platform" / "Stop hiring. Start delegating." Strong and on the primary framing. |
| Meta | "Company-as-a-Service for solo founders. AI agents across 8 departments…" leads with a term that, per the brand guide, "requires market education" (F7). |
| Detected keywords | AI agents for solo founders; Company-as-a-Service (badge, tagline, hero-sub, section title, meta); coding harness; plugin; Claude Code, Grok Build, Codex, Devin CLI, OpenCode; MCP. |
| Keyword alignment | Title strong; meta and above-the-fold body weak. Founder query words ("hire", "delegate", "marketing", "legal") are present but outweighed by tool names. |
| Search intent | Commercial with some informational. The FAQ matches both. |
| Readability | Unchanged since 10-26. The line under the main button names 5 developer tools and the word "harness". The tool list is out of date (5 vs 6). The "9 hats" FAQ contradicts "8 departments" two lines later. |
| Issues | N5 (P0), B1, F5, F7 (P1), A1 (P2), F18, N2, B5 (P3). |

### 2. Pricing (`/pricing/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Pricing — AI Agents for Solo Founders \| Soleur" / "Every department. One price." Strong. |
| Meta | Good: names the 8 departments and "$49/month once hosted plans open. Join the waitlist." Transactional intent is met. |
| Readability | The free-version FAQ uses "harness" and 5 tools (N5, A1). "ready to sign" and "autopilot" lack trust scaffolding (F10). "70%" and "420+ PRs" are unsourced or engineering metrics (F17). The "Your AI organization is ready." H2 sits above a waitlist (N4). |

### 3. Getting Started (`/getting-started/`)

| Field | Assessment |
|---|---|
| Title / H1 | seoTitle "Get Started with Soleur — Install Your AI Organization in Two Commands" / H1 "The AI that already knows your business." |
| Keyword alignment | Misaligned. "Two commands" is true for 1 of 6 tools, and the page's own FAQ now says so ("Setup is two commands on Claude Code"). |
| Intent | Split three ways: install, waitlist, and the homepage `#self-hosted` anchor. |
| Readability | The section label "Source-available. Install in your own harness." is the first thing a founder sees after clicking the hero button. Below it are 6 install blocks, a 7-column command table, and the OpenCode `CLAUDE_PLUGIN_ROOT` paragraph. |
| Change since 11-02 | The "Nothing to install" FAQ now lists 6 tools (A1 partial, F3 partial). The OS FAQ, the "differences" FAQ and the entry-command JSON-LD still list 4 or 5 tools. |

### 4. Blog index (`/blog/`)

| Field | Assessment |
|---|---|
| Title / H1 | "Soleur Blog — Company-as-a-Service, Agentic Engineering, and Building at Scale With AI Teams" / "Blog". |
| Alignment | Targets developer queries, against the Blog note "Search" rule (F1). |
| IA | 4 category sections, driven by tags. 6 founder or announcement posts fall into "Engineering Deep Dives" (F2). The newest card is dated December 3, 2026 (N6). |

### 5. Agents (`/agents/`) and Skills (`/skills/`)

| Page | Title / H1 | Alignment | Issues |
|---|---|---|---|
| `/agents/` | H1 "Your AI Organization: {{ stats.agents }} Specialists Across {{ stats.departments }} Departments" | Good: computed counts, founder framing | "is trained" ×3 and "within Claude Code" in FAQPage text (F12); `last_updated` 2026-06-01 (F19). |
| `/skills/` | "Soleur Skills" / "Agentic Engineering Skills" | Weak: brand-only title, developer H1 | F6 (P1); 5-tool list (A1); `last_updated` 2026-06-15 (F19). |

### 6. Comparison pages (in "Learn" nav)

| Page | Title / Meta | Intent match | Strengths | Issues |
|---|---|---|---|---|
| `/compare/soleur-vs-cursor/` | "Soleur vs Cursor" | Commercial; matches the query | One-sentence summary; sourced link | Cursor ARR stated as fact (F4); "the other 70 percent" (F17); 5-tool list (A1); ends on a terminal install (B2). |
| `/compare/soleur-vs-devin/` | seoTitle "Soleur vs Devin: Autonomous Coding Agent vs AI Organization \| Soleur"; meta "Devin is an autonomous software engineer that dropped from 500 to 20 dollars a month. Soleur is a full AI organization. A fair comparison for solo founders." | Commercial; strong match for "Soleur vs Devin" and "Devin alternative" | Best-structured page this run. One-sentence summary; inline citations (cognition.ai, VentureBeat); public pricing rather than revenue (brand rule followed); fair "When to pick Devin" section; "Your expertise, amplified" trust scaffolding; 4-question FAQ | **First audit of this page (B3).** The table row "Partial (runs in your Claude Code environment)" is wrong: the page's own body says Soleur runs in Devin CLI, and that is the strongest "use together" answer. "Why it matters now" leans on an April 2025 price cut. The CTA is a terminal install (B2). "compound step" in a FAQ answer is internal vocabulary. |

### 7. About, Vision, Community

All three are unchanged since 11-02 (F13, F15, F16, F9, N2). The `/vision/` FAQ and `/community/` both list 5 tools. `/community/` says "The platform ships as a plugin for Claude Code, Grok Build, Codex, Devin CLI, and OpenCode". That is acceptable on a contributor page, but it is out of date (A1).

### 8. Blog posts reviewed

| Post (date) | Title / seoTitle | Target query | Intent | Founder-problem title? | Readability / jargon | CTA | Verdict |
|---|---|---|---|---|---|---|---|
| Vendor lock-in (10-23, live) | "What Happens to Your Business When Your AI Provider Changes the Rules?" / "Own Your AI Team Without Vendor Lock-In \| Soleur" | AI vendor lock-in; own your AI data | Informational / commercial | Yes | Strong opening. "harness" ×5, "repository", "Git", "open-weights", "Ollama, llama.cpp". FAQ tool list now correct. | Install manual (`/getting-started/`) | Good post; finish A4 fact fixes. |
| Antigravity (10-26, live) | "Run Your AI Company on Google Antigravity Without Losing Your Business Memory" / "Run an AI Team on Google Antigravity Without Losing Business Context \| Soleur" | Google Antigravity (developer, navigational); "AI team without losing context" | Navigational / informational | Partly: the seoTitle is better; the meta still leads with the mechanism | About 330 words of body. "agentic coding tools", "harness" ×4, "native reactive wakeups", `agy` in FAQ. Unsourced Gemini model names (B4). | Install anchor, then waitlist | Improved. The seoTitle change on a live post is outside the Blog Scope rule (refreshes keep title and meta); record it as a one-off. Finish A2 and B4. |
| Recurring job (11-04, live) | "Before Your AI Team Takes a Recurring Job, It Answers Six Questions" | audit business automations | Informational | Yes | Best opening on site. "Idempotence is a property." undefined. | "Try Soleur" → homepage | Fix N9 (empty visible FAQ) now that it is live. |
| Flaky test (11-17, **tomorrow**) | "A Flaky Test Passed on Retry and the Loop Called It Fixed" (same seoTitle) | flaky test (developer) | Informational (developer) | **No**: mechanism ("flaky test", "loop") | Opening is good and founder-facing ("Your AI produces work faster than you can check it…"). The title and meta are not. | Waitlist | **Retitle today** (R-10). |
| Green (11-19, in 3 days) | "First We Made 'Green' Mean Something. Then We Made It Fast." | none (our story) | Informational | No | "nearly 700 automated checks", "twelve merges, zero broken mains", "1.88", "soak", "fixture"; duplicate FAQ (N10); links to 12-03 (A3) | Waitlist | Apply R-6 before 11-19. |
| Alarm (12-03, future) | "Your Alarm Passed Every Rehearsal. In Real Life It Never Rings." / "Your Error Alerts Can Pass Every Test and Never Fire" | error alerts not firing | Informational | Yes | Plain analogies; light jargon. | Waitlist | Model arc post. Only N6 (date) and N8 (series box) apply. |
| 10-27, 10-29, 11-03, 11-05, 11-10, 11-12 (live) | unchanged | developer queries ("property test", "migration", "schema", "feature map") | Developer | No | N11 | Waitlist | Retitle window closed. Fact fixes only (N14 on 11-03). |

**Searchable vs shareable:** the live queue is 3 founder-searchable posts (vendor lock-in, recurring job, alarm), 1 announcement (Antigravity) and 9 build-in-public arc posts. The arc posts are shareable in intent but carry developer titles, so they get neither search reach nor founder-share reach. No data-led shareable piece is planned.

## Keyword Notes

WebSearch was not run (see Method). No new volume or difficulty data was gathered. Relevance is judged against the Blog note reader.

| Keyword / query | Intent | Relevance | Currently targeted by | Note |
|---|---|---|---|---|
| Soleur vs Devin / Devin alternative | Commercial | High | `/compare/soleur-vs-devin/` | Well targeted. Add "Devin alternative for solo founders" to the first H2 or FAQ. |
| AI vendor lock-in / switch AI provider without losing data | Informational / commercial | High | Vendor-lock-in post | Good. |
| run AI team on Gemini / Google | Commercial | Medium | Antigravity meta | Usable only once the Gemini claim is sourced (B4). |
| can I trust AI test results / what does "all checks passed" mean | Informational | High | 11-19 FAQ only | Use it in the R-6 seoTitle. |
| AI keeps retrying until it passes / can I trust AI that checks its own work | Informational | Medium-high | None | Founder version of "flaky test"; use it in R-10. |
| can I trust AI output | Informational | High | None (hub partly) | Top unclaimed founder query; F14 gap piece. |
| Claude Code plugins / agentic engineering | Navigational (developer) | Low for ICP | Nav "Learn" menu, blog index seoTitle, skills H1 | Keep the pages, but take them out of founder-first surfaces (F1, F6, B5). |

## Rewrite Suggestions

All rewrites use the general register. R-1 to R-9 from the [2026-11-02 audit](./2026-11-02-content-audit.md) still apply unchanged. R-6 (11-19 title, seoTitle and meta) is now due **before 2026-11-19**. Only new rewrites are listed here.

| ID | Page | Element | Current | Suggested | Rationale |
|---|---|---|---|---|---|
| R-10 | 11-17 post (dated tomorrow) | Title / seoTitle / meta | "A Flaky Test Passed on Retry and the Loop Called It Fixed" / same / "A flaky test passed on retry and the loop called it fixed. We shipped a deterministic quarantine instead — and review caught it lying twice." | "When Your AI Says 'Fixed' Because It Tried Again" / "Passed on the Second Try Isn't Fixed: How to Trust AI Work" / "If your AI reruns a failed check until it passes, it learns that problems go away on their own. One rule keeps a pass honest, and you can ask for it today." | Names the founder's problem, not the mechanism ("flaky", "quarantine", "loop"). Targets "can I trust AI that checks its own work". The opening paragraph already fits; only the title, seoTitle and meta change. Last day before the date passes. |
| R-11 | `/compare/soleur-vs-devin/`, `/compare/soleur-vs-cursor/`, `/company-as-a-service/`, `/ai-agents-for-solo-founders/` | Closing "Get started" block | "…or install the self-hosted version:" + `claude plugin marketplace add jikig-ai/soleur-marketplace` / `claude plugin install soleur@soleur-marketplace` | "**Get your AI organization.** Join the waitlist for hosted Soleur, or run the free self-hosted version today on the AI tool you already use. [Join the waitlist](/pricing/#waitlist) · [See the setup options](/getting-started/)" | Website note: no CLI install as the primary CTA. The install command works for 1 of 6 tools. Declarative, no "just" or "simply". |
| R-12 | `/compare/soleur-vs-devin/` | Table row "Sandboxed browser and terminal", Soleur cell | "Partial (runs in your Claude Code environment)" | "Uses the environment of the AI tool you run it in, including Devin CLI" | Corrects a factual understatement and turns it into a differentiator. |
| R-12 | `/compare/soleur-vs-devin/` | FAQ "Can Devin and Soleur be used together?" (+ JSON-LD) | "Yes. Use Soleur for the full organizational workflow… Soleur's compound step captures the architectural decisions…" | "Yes, in two ways. Soleur runs inside Devin CLI itself, so your whole AI team can work where Devin works. Or use Soleur for planning, legal, finance and marketing, and hand well-scoped coding tasks to Devin. Either way, the decisions Devin surfaces are written into your company's memory." | Adds the strongest true answer. Replaces internal "compound step" with the glossary term "your company's memory". |
| R-13 | Antigravity post | FAQ "Which models can I use with Google Antigravity?" (+ JSON-LD) | "Google Antigravity CLI connects natively to Google's Gemini models, including Gemini 2.5 Pro and Gemini Flash, giving your AI specialists fast inference and large context windows…" | "The models Google makes available in Antigravity. Your AI team works the same way on any of them, and your company's memory stays in files you own, so changing models never resets what your team knows." | Removes unsourced model names that go stale (B4). Leads with the founder outcome. If model names are kept, cite Google's Antigravity documentation in the same answer. |
| R-13 | Antigravity post | FAQ "Does Soleur run on Google Antigravity CLI?" (+ JSON-LD) | "Yes. Soleur installs natively on Google Antigravity CLI (`agy`), allowing you to run your full AI team… directly within Google's agentic harness." | "Yes. Your full AI team, covering engineering, marketing, legal, finance, operations, product, sales and support, runs inside Google's Antigravity, with the same company memory it uses everywhere else." | Blog jargon limit: no backticks or commands in FAQ answers; no "harness". |
| R-14 | Site-wide (A1) | Every tool list outside `/getting-started/` | "Claude Code, Grok Build, Codex, Devin CLI, or OpenCode" (homepage ×3, pricing, vision, community, compare ×2); "running in Claude Code today" (about) | First-contact pages: "the AI workspace you already use, such as Claude Code or Codex". `/getting-started/` keeps the single authoritative 6-tool list, and its OS FAQ, differences FAQ and entry-command JSON-LD add Google Antigravity. | One source of truth stops drift on every new integration. Pin the getting-started list in the existing drift test. |
| R-15 | 11-04 post (live) | Visible FAQ | "## Frequently asked questions" with no visible Q&A | Render the questions and answers already present in the JSON-LD as visible `###` question headings and plain answers, above the script block | The FAQPage text must match visible content. Readers currently see an empty heading. |
| R-16 | `/` | "Go deeper" link description | "What the Soleur plugin adds to your coding harness." | "How Soleur works inside the AI tools developers already use." | Removes "plugin" and "harness" from founder-facing copy (B5, N5). |

## Top 5 Actions

1. **Record the hero-test review outcome in the brand guide and ship R-1 plus R-16 (N5, B1).** Every week the trigger stays met makes the test window harder to read.
2. **Today: retitle the 11-17 post (R-10). Before 11-19: apply R-6.** These are the last two arc posts whose titles can still change under the Blog Scope rule (N7).
3. **Land the date gate and handle the 11-19 → 12-03 link in the same PR (N6, A3).**
4. **Replace the terminal-install endings on the compare and pillar pages with R-11, and fix the Devin table row and FAQ (B2, B3, R-12).** These are the highest commercial-intent pages in the nav.
5. **Finish the half-done tool and model fixes (A1, A2, A4, B4), then fill the post-12-03 queue with a founder gap piece (F14).** "Can I trust what my AI produces?" fits the arc and the top unclaimed query.

## Caveats

- WebFetch was blocked by cron containment, so no rendered page was checked. Every status above comes from source. #9103 should be confirmed live before it is closed.
- `git log` was not used, so A5 is unverifiable and "no new post in 14 days" is inferred from the file set matching the 11-02 audit's sweep.
- Evidence cites quoted text and file names, not line numbers.
- Whether a post dated after today counts as "published" (which decides how far it may be rewritten) is still the CMO decision recorded on #11134. R-10 and R-6 assume it does not.
