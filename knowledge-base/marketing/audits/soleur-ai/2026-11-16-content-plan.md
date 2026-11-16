---
title: Content Plan — soleur.ai — 2026-11-16
date: 2026-11-16
type: content-plan
site: https://soleur.ai
---

# Content Plan — soleur.ai — 2026-11-16

Built from the three audits written in this cycle:

- [2026-11-16-content-audit.md](./2026-11-16-content-audit.md): 2 P0, 11 P1, 17 P2, 15 P3 (45). Of 40 carried findings: 0 fixed, 4 partly fixed, 3 worse, 32 open, 1 unverifiable. 5 new (B1 to B5).
- [2026-11-16-aeo-audit.md](./2026-11-16-aeo-audit.md): **75/100 (B+)**, up 1 (8-component: 79, up 1). Structure 34/40, Authority 27/35, Presence 14/25.
- [2026-11-16-seo-audit.md](./2026-11-16-seo-audit.md): **78/100 (B)**, unchanged for the fourth cycle.

## Scores and trend

| Audit | 10-19 | 10-26 | 11-02 | 11-09 | **11-16** | Change vs 11-09 |
|---|---|---|---|---|---|---|
| AEO (SAP) | 76 (B+) | 76 (B+) | 74 (C) | 75 (B+) | **75 (B+)** | 0 (+1 vs 11-02 report on disk) |
| AEO (8-component) | 81 | 82 | 78 | 79 | **79** | 0 |
| Technical SEO | 83 (B+) | 78 (B) | 78 (B) | 78 (B) | **78 (B)** | 0 |
| Content findings (P0/P1) | 23 (0/8) | 33 (2/9) | 40 (2/9) | 48 (2/11) | **45 (2/11)** | −3 (dates passed, not fixes) |

Note: the 2026-11-09 reports are not in this directory (that run's PR did not land); this cycle's agents compared against 2026-11-02. The 11-09 scores come from issue #12461.

**How to read this:**

- **All three audits read source files only, again.** Cron containment refused WebFetch, `curl`, `git log` and the Eleventy build (#8467, #6088). `validate-seo.sh` did not run. No finding is confirmed against production.
- **Zero P0s shipped in six cycles.** The future-dated post count fell from 8 to 3 only because calendar dates passed. The finding count dropped for the same reason.
- **No new posts in 14 days.** The publishing queue ends on 12-03. That is a window: repair work now competes with nothing.

## Headline

**The site is stable but static: scores have not moved in four weeks because no repair has shipped. Two of the last three retitle windows on the verification arc close this week (11-17 tomorrow, 11-19 Thursday).**

## Part 1 — Findings mapped to issues (one issue per defect, per #8469)

### New this cycle

| # | Finding | Source | Priority | Issue |
|---|---|---|---|---|
| B1 | Hero CTA test review (2026-11-03) is 13 days past; no outcome recorded; developer-register revert trigger still met | Content B1 | P1 | #9588 (new evidence) |
| B2 | Both compare pages and two pillar pages (`/company-as-a-service/`, `/ai-agents-for-solo-founders/`) end on a Claude-Code-only terminal install command, against the brand guide Website note | Content B2 | P1 | #12794 (new; related: #9591) |
| B3 | `/compare/soleur-vs-devin/` says Soleur "runs in your Claude Code environment" and never says it runs inside Devin CLI; "why it matters now" rests on an April 2025 price cut | Content B3 | P2 | #12795 (new) |
| B4 | Antigravity FAQ names "Gemini 2.5 Pro and Gemini Flash" with no source | Content B4, AEO N14 | P2 | #12459 |
| B5 | "Learn" nav mixes 2 developer pages into founder guides | Content B5 | P3 | none (kept in report) |
| N13 | MVP post: no outside source, Gitleaks not named | AEO N13 | P2 | #12460 |

### Carried (status this cycle)

| # | Finding | Priority | Issue | Status |
|---|---|---|---|---|
| 1 | No publish gate; 3 future-dated posts live (11-17, 11-19, 12-03), 12-03 card tops `/blog/`; parked 11-19 post built | **P0** | #11132 | Open (exposure lower by calendar only) |
| 2 | Developer register on `/` and `/pricing/` ("coding harness", "ships as a plugin", `/soleur:go` ×4) | **P0** | #11133 | Open |
| 3 | Citation tracker never run (22 Mondays missed) | **P0** | #6084 | Open |
| 4 | No third-party Presence surface (14/25, 7th flat cycle) | **P0** | #5610, #2601 | Open |
| 5 | `/vision/` unbuilt features in present tense | **P0** | #6376 | Open |
| 6 | Cron containment blocks build, WebFetch, `git log` | **P0** (process) | #8467, #6088 | Open |
| 7 | Arc titles target developer queries; only 11-17 and 11-19 retitle windows left | P1 | #11134 | **Worse** |
| 8 | Arc posts cite no outside source | P1 | #11135 | Open |
| 9 | Supported-tool list: 6 in 4 places, 5 in ~10, Claude-only in 2 | P1 | #11833 | Partly fixed |
| 10 | FAQPage schema with no visible FAQ (5 posts; 11-04 now live with empty heading) | P1 | #9101 | **Worse** |
| 11 | Founder `Person` `sameAs` conflict | P1 | #9102 | Open |
| 12 | Hero self-host button lands on install manual | P1 | #2669 | Open |
| 13 | Getting-started "Two Commands" vs "Nothing to install" | P1 | #9107 | Partly fixed |
| 14 | Blog index title/meta, founder posts under Engineering | P1 | #9104, #9105 | Open |
| 15 | Competitor revenue stated as fact | P1 | #7179 | Open |
| 16 | "9 hats" vs 8 departments; CaaS-led hero; `/skills/` title | P1 | #8462, #9112, #5601 | Open |
| 17 | CaaS pillar superlatives; September posts unsourced | P1 | #6085, #9108 | Open |
| 18 | Vendor-lock-in post "any model", 67 agents, install CTA | P2 | #11836 | Partly fixed |
| 19 | "102" vs "nearly 700" automated checks | P2 | #11835 | Open |
| 20 | Arc hygiene (series box, jargon, stray `pillar` tag) | P2 | #11136 | Open |
| 21 | Reused OG cards (3 posts) | P2 | #11137 | Open |
| 22 | `last_updated` without fact review | P2 | #11138 | Open |
| 23 | Sitemap `lastmod` ignores `updated:`; 22 undated pages | P2 | #9106, #7180, #8468 | Open |
| 24 | Homepage `og:title`, generic `og:image:alt` (43/45), `llms.txt` 9 URLs | P2 | #2674, #2557, #7181 | Open |
| 25 | Head-term cannibalisation, `pillars.js` routing | P2 | #8463, #8464 | Open |
| 26 | Accuracy copy: pricing "70%", AI CMO costs, CaaS origin, `/agents/` superlative | P2 | #9111, #9499, #9501, #6378 | Open |
| 27 | Inc.com "As seen in" | P1 | #9103 | Looks fixed in source; close after live check |

## Part 2 — Prioritised plan

### P0 — this week

1. **Retitle 11-17 today and 11-19 before Thursday (#11134).** Rewrites R-10 and R-6 are in the content audit. Keep slugs. This is the only item with a hard deadline that expires this week; after 11-19 the arc's retitle window is closed for good.
2. **Date gate (#11132).** One PR: `blog.11tydata.js` that sets `permalink: false` and excludes `date > now` from `collections.blog`, feed and sitemap; daily `schedule:` on `deploy-docs.yml`; future-`lastmod` check in `validate-seo.sh`; forward links only to published posts; hold `parked` posts. About 1 hour. **SEO returns to ~83.**
3. **Record the hero CTA decision on #9588, then ship R-1 on `/` and `/pricing/` (#11133).** The review is 13 days late; every day without a record makes the test result less usable.
4. **Run the citation tracker once (#6084)** on Perplexity and Claude.ai. Only lever on Presence (14/25).
5. **`/vision/` roadmap cards in future tense (#6376).**
6. **Cron containment allowlist (#8467, #6088):** Eleventy build, `validate-seo.sh`, WebFetch to soleur.ai, read-only `git log`. Without it, no audit can confirm a fix.

### P1 — four PRs

| PR | Scope | Issues | Expected lift |
|---|---|---|---|
| **A. Single source of facts** | `_data/harnesses.js` rendered in every template, FAQ and JSON-LD (fix `getting-started.njk` FAQs first); scope or remove the "nearly 700" count; vendor-lock-in meta and CTA | #11833, #11835, #11836, #9500 | AEO Entity +1, Statistics +1 |
| **B. Commercial-page CTAs** | Replace the terminal install block on both compare pages and two pillars with a waitlist button plus a link to getting-started (R-11); fix the Devin compare row and add "Soleur runs inside Devin CLI" (R-12) | #12794, #12795, #9591 | Conversion; Structure +1 |
| **C. Schema parity** | Visible FAQ on the 5 schema-only posts (11-04 first, it is live with an empty heading); one founder `sameAs`; unique OG cards | #9101, #9102, #11137 | SEO +2 |
| **D. First-contact pages + blog hub** | Getting-started founder lede and collapsed install blocks; "8 jobs"; hero leads with the founder problem; founder-first `/blog/` title/meta and category | #2669, #9107, #8462, #9112, #9104, #9105 | Structure +1 |

**Expected if P0 + A–C land:** AEO ~79–80 (B+), 81–83 with a tracker run. SEO ~87–88.

### P2 — trust and freshness (next 2–3 weeks)

- **Post-level fact checks:** #12459 (Antigravity link and Gemini names — drop names or cite Google docs), #12460 (MVP post: name and link Gitleaks, one primary source on leaked secrets).
- **Arc citations (#11135, #11136):** 1–2 primary sources per arc post.
- **Honest freshness:** #11138, #7180, #8468, #9106.
- **Accuracy copy:** #9111, #9499, #9501, #6378, #7179.
- **Social/AI metadata:** #2674, #2557, #7181.

### P3 — new content (only after P0 and PR A)

The queue is empty after 12-03. Use the gap for repair, then resume at 2 posts per month:

1. **Founder-problem gap pieces (#8466):** contracts without a lawyer; AI marketing for a solo founder; hire or delegate. Each with a visible FAQ, matching schema and 2+ outside sources.
2. **First-party data piece:** founder-register summary of the 102-check audit and the 1.88× measurement, pitched as a Show HN (#5610).
3. **Beta-checkpoint post with tester quotes (#2603)**, with consent (also closes AEO F12, no testimonials).
4. **On hold:** new pillars, compare and use-case pages until #8463 / #8464 resolve.

**Content-writer checklist (carried, still not added):** "2+ outside sources"; "cross-page facts (tool list, agent count, department count) come from `_data/`"; "`date:` is the merge date"; "no terminal commands on commercial-intent pages".

## Part 3 — Keyword note

Keyword research is still the 2026-05-25 set (175 days old); WebSearch is blocked in cron. Rule until re-research: **the title names the founder's problem; the mechanism appears only in the body.**
