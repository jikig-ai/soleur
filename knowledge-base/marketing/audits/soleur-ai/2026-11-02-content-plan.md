# Content Plan — soleur.ai — 2026-11-02

Built from the three audits written in this cycle:

- [2026-11-02-content-audit.md](./2026-11-02-content-audit.md): 2 P0, 9 P1, 15 P2, 14 P3 (40). Of the 33 prior findings, 0 are fixed, 3 are partly fixed, 7 are worse and 23 are still open. 6 findings are new (A1 to A6).
- [2026-11-02-aeo-audit.md](./2026-11-02-aeo-audit.md): **74/100 (C)** on SAP, down 2. **78** on the 8-component check, down 4.
- [2026-11-02-seo-audit.md](./2026-11-02-seo-audit.md): **78/100 (B)**, unchanged. The drop from 83 has not been recovered.

## Scores and trend

| Audit | 2026-10-05 | 2026-10-19 | 2026-10-26 | 2026-11-02 | Change vs 10-26 |
|---|---|---|---|---|---|
| AEO (SAP) | 76 (B+) | 76 (B+) | 76 (B+) | **74 (C)** | **−2** |
| AEO (8-component) | 81 | 81 | 82 | **78** | **−4** |
| Technical SEO | 83 (B+) | 83 (B+) | 78 (B) | **78 (B)** | 0 |
| Content findings (P0/P1) | 19 (0/7) | 23 (0/8) | 33 (2/9) | **40 (2/9)** | +7 findings |

**How to read this table:**

- **All three audits read the source files only, for the 17th run in a row.** Cron containment blocked WebFetch, WebSearch, `git log` and the Eleventy build (#8467, #6088). `validate-seo.sh` did not run. Live behaviour is inferred from the build config.
- **This is the first cycle with zero fixes of any kind.** No P0 has shipped in four cycles. New posts keep adding the same kinds of defect (no outside sources, facts typed in by hand that drift, future dates) faster than old ones are closed.
- **The AEO drop has three causes:** the future-dating got worse (now up to 31 days ahead), 11 of 13 recent posts cite no outside source, and a new contradiction about which tools Soleur runs on (5 vs 6).
- **SEO is flat because #11132 is still open.** That one fix brings it back to about 83.

## Headline

**Publishing is fast, but repair work is not getting scheduled. One bundled repair PR would get the B+ AEO grade back without writing any new content.**

The week added 4 posts and an install path for Google Antigravity CLI. The two newest arc posts (11-19, 12-03) are the best built on the site: visible FAQs, a 1.88× measurement with its limits stated, and "what this does not prove" sections. But:

- **#11132 (P0) got worse.** 8 posts are dated after today, the furthest 2026-12-03. The 11-19 post links to the 12-03 post. The 11-19 post is `status: parked` in distribution but is built anyway.
- **#11133 (P0) is unchanged, and the hero CTA test review is tomorrow (2026-11-03).** The developer-register drift is a named revert trigger. If it is not fixed today, record it on #9588 as a confound.
- **Antigravity was added to one page only.** `/getting-started/` now lists 6 tools. Its own FAQ, the homepage, pricing, compare pages and the vendor-lock-in FAQ list 5.

## Part 1 — Findings mapped to issues (one issue per defect, per #8469)

### New this cycle

| # | Finding | Source | Priority | Issue |
|---|---|---|---|---|
| N-a | Supported-tool list has two versions: 6 on `/getting-started/` body, 5 in its FAQ/JSON-LD and on `/`, `/pricing/`, `/vision/`, `/community/`, both compare pages, vendor-lock-in FAQ | AEO N10, Content A1 | P1 | new (see audit issue) |
| N-b | Antigravity announcement post is thin: mechanism seoTitle ("Any Harness"), ~330 words, no CTA, no FAQ, no outside link, lists 6 departments under an "8-department" description | AEO N11, Content A2 | P2 | new |
| N-c | Unscoped, conflicting counts of "automated checks": 102 / "more than a hundred" (hub, audit post) vs "nearly 700" (11-19) | AEO N12 | P2 | new |
| N-d | Vendor-lock-in post overclaims: meta "on any model they choose" (hosted is Anthropic-only), hard-coded "67 specialist agents", "eliminates that risk", CTA goes to the install manual | Content A4 | P2 | new |
| — | 11-19 post links the 12-03 post; 11-19 is `parked` but built | Content A3, SEO | P0 | #11132 (new evidence) |
| — | 10-23 and 10-26 posts reuse the March OG card; the 11-04 card now reuses the 10-27 card | SEO | P2 | #11137 (new evidence) |
| — | Two posts may be backdated; stray `pillar` tag on 11-19 | Content A5, A6 | P3 | none (kept in report) |

### Carried (status this cycle)

| # | Finding | Priority | Issue | Status vs 10-26 |
|---|---|---|---|---|
| 1 | Future-dated posts live early; no publish gate, no scheduled deploy | **P0** | #11132 | **Worse** (furthest +31 days) |
| 2 | Homepage and pricing in developer register during hero test | **P0** | #11133 | Open; review is 2026-11-03 |
| 3 | Citation tracker never run (20 Mondays missed) | **P0** | #6084 | Open |
| 4 | No third-party Presence surface (14/25 for 6 cycles) | **P0** | #5610, #2601 | Open |
| 5 | `/vision/` describes unbuilt features in the present tense | **P0** | #6376 | Open |
| 6 | Cron containment blocks build, WebFetch, `git log` | **P0** (process) | #8467, #6088 | Open (17th run) |
| 7 | Arc titles target developer queries | P1 | #11134 | **Worse** (10-27, 10-29 now past date; 11-19 our-story title) |
| 8 | Arc posts cite no outside source | P1 | #11135 | **Worse** (11 of 13 recent posts) |
| 9 | Hero self-host button lands on a terminal manual | P1 | #2669 | **Worse** (6 install blocks, 7-column table) |
| 10 | Getting-started "Two Commands" vs "Nothing to install" | P1 | #9107 | **Worse** (true for 1 of 6 tools) |
| 11 | Blog index title/meta target developer queries | P1 | #9104 | Open |
| 12 | Founder posts filed as Engineering Deep Dives | P1 | #9105 | **Worse** |
| 13 | Competitor revenue stated as fact | P1 | #7179 | Open |
| 14 | "9 hats" vs 8 departments | P1 | #8462 | Open |
| 15 | Hero and meta lead with CaaS | P1 | #9112 | Open |
| 16 | `/skills/` title brand-only | P1 | #5601 | Open |
| 17 | FAQPage schema with no visible FAQ (5 posts; 11-04 empty heading, live in 2 days) | P1 | #9101 | Open |
| 18 | Founder `Person` `sameAs` conflict | P1 | #9102 | Open |
| 19 | CaaS pillar superlatives, "numbers" with no numbers | P1 | #6085 | Open |
| 20 | September posts cite no outside source | P1 | #9108 | Open |
| 21 | Arc hygiene: wrong series box (now 10 posts), repeated lesson, jargon | P2 | #11136 | **Worse** |
| 22 | `last_updated` bumped without fact review; now also the reverse (Antigravity added, date not moved) | P2 | #11138 | Open |
| 23 | Missing/reused OG images | P2 | #11137 | Partly fixed (no 404, but reused) |
| 24 | Model-support claims | P2 | #9500 | Partly fixed, new regressions (see N-a, N-d) |
| 25 | Pricing "ready to sign" / "autopilot" / "70%" | P2 | #9111 | Open |
| 26 | AI CMO three costs | P2 | #9499 | Open |
| 27 | CaaS origin claims | P2 | #9501 | Open |
| 28 | `/agents/` "trained" | P2 | #6378 | Open |
| 29 | `/community/` generic title | P2 | #6377 | Open |
| 30 | Sitemap `lastmod` ignores `updated:` (43% of URLs unreliable) | P2 | #9106 | Open, wider |
| 31 | Undated pages / page-freshness missing on pillars | P2 | #7180, #8468 | Open |
| 32 | Homepage `og:title`, generic `og:image:alt` (43 of 44), `llms.txt` gaps | P2 | #2674, #2557, #7181 | Open |
| 33 | Head-term cannibalisation, `pillars.js` routing | P2 | #8463, #8464 | Open |
| 34 | Inc.com "As seen in" | P1 | #9103 | **Looks fixed in source.** Close after a live check |

## Part 2 — Prioritised plan

**Constraint:** the hero button test review is 2026-11-03. Nothing below changes the button or its target. #11133 changes the copy *around* it, to undo drift that is already a revert trigger.

### P0 — this week

1. **Date gate (#11132), before the 11-03 and 11-04 posts appear.** In one PR:
   - an Eleventy filter that drops `/blog/` posts with `date > now` from collections, the sitemap and the feed
   - a daily `schedule:` on `deploy-docs.yml`
   - a `validate-seo.sh` check that fails on a future `<lastmod>`
   - render the 11-19 → 12-03 link only when the target is published, or re-date 12-03 before 11-19
   - decide what happens to `parked` posts (keep the 11-19 post out until it is un-parked)

   About 1 hour of work. SEO goes back to about 83 and AEO Authority gains 1.
2. **Developer-register drift on `/` and `/pricing/` (#11133). Today.** If it cannot ship before the review, note it on #9588 as a confound in the test.
3. **`/vision/` cards (#6376).** Put unbuilt features under a "Roadmap" H2, written in the future tense.
4. **Citation tracker (#6084).** Run once on 2 engines (Perplexity, Claude.ai), then schedule it. This is the only way to move Presence.
5. **Cron containment (#8467, #6088).** Allow the Eleventy build, `validate-seo.sh`, WebFetch to soleur.ai and read-only `git log`.

### P1 — one "AEO repair" PR, then four small PRs

| PR | Scope | Issues | Expected lift |
|---|---|---|---|
| **A. AEO repair bundle** | One data file for the supported-tool list (`_data/harnesses.js`), rendered in every template, FAQ and JSON-LD. Fix the vendor-lock-in meta ("any model"). Name what each "automated checks" number counts. Add an absolute date to the 11-19 soak-test sentence | N-a, N-c, N-d, #9500 | Entity clarity +1, Statistics +1 |
| **B. Arc citations and titles** | 1–2 primary sources per arc post (QuickCheck, Google Testing Blog on flaky tests, Osmani). Founder-problem titles for posts not yet dated past (11-03 onward); use the 12-03 post as the template | #11135, #11134, #11136 | Source citations +1–2 |
| **C. Schema and entity parity** | Visible FAQ on the 5 schema-only posts (11-04 first, it is dated in 2 days), one `Person` `sameAs`, unique OG cards for 10-23, 10-26, 11-04 | #9101, #9102, #11137 | — |
| **D. First-contact pages** | Getting-started: founder lede, one title that is true for all tools, collapse the 6 install blocks under "Self-hosted"; "8 jobs, 7 of them"; CaaS pillar superlatives | #2669, #9107, #8462, #6085, #9112 | Structure +1 |
| **E. Blog hub** | Founder-first `/blog/` title/meta; a founder-playbook category | #9104, #9105, #9108 | — |

**Expected scores if P0 and PR A–C land:** AEO about 79–80 (B+), 81–83 with the tracker run. SEO about 87–88; 90+ with D and E.

### P2 — trust and freshness (next 2–3 weeks)

- **Thin Antigravity post (N-b):** one-sentence definition linking Google's Antigravity docs, all 8 departments, 3 visible Q&As, a CTA, a founder-problem seoTitle.
- **Honest freshness (#11138, #7180, #8468, #9106):** guard on `last_updated`, sitemap `lastmod` from `updated:`, freshness block on pillars.
- **Accuracy copy:** #9111, #9499, #9501, #6378, #6377.
- **Social/AI metadata:** #2674, #2557, #7181.

### P3 — new content (after P1)

1. **Founder-problem gap pieces (#8466):** contracts without a lawyer, AI marketing for a solo founder, hire or delegate, self-hosted vs hosted (partly covered by the vendor-lock-in post; extend it rather than write a new one). 2 a month. Each needs a visible FAQ, matching schema and 2+ outside sources.
2. **First-party data:** a founder-register summary of the 102-check audit and the 1.88× measurement, pitched as a Show HN (#5610).
3. **Beta-checkpoint post with tester quotes (#2603)**, with consent.
4. **On hold:** new pillars, compare and use-case pages until #8463 and #8464 are resolved.

**Add 2 lines to the content-writer checklist:** "at least 2 outside sources" and "facts that appear on more than one page (tool list, agent count, department count) come from `_data/`, not typed in". This cycle's 4 new findings would not exist with these.

## Part 3 — Keyword note

Keyword research is still the 2026-05-25 set (161 days old). WebSearch is blocked in cron. Until head terms can be re-researched: **the title names the founder's problem; the mechanism appears only in the body.** The 12-03 post ("Your Alarm Passed Every Rehearsal…") is the first arc post that follows this rule in title, seoTitle and meta.
