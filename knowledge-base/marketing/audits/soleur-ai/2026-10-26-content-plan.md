# Content Plan — soleur.ai — 2026-10-26

Built from the three audits written in this cycle:

- [2026-10-26-content-audit.md](./2026-10-26-content-audit.md): 2 P0, 9 P1, 11 P2, 11 P3. 23 findings are carried from last cycle and 10 are new.
- [2026-10-26-aeo-audit.md](./2026-10-26-aeo-audit.md): **76/100 (B+)** on SAP and **82** on the 8-component check.
- [2026-10-26-seo-audit.md](./2026-10-26-seo-audit.md): **78/100 (B)**, down from 83.

## Scores and trend

| Audit | 2026-10-05 | 2026-10-12 | 2026-10-19 | 2026-10-26 | Change vs 10-19 |
|---|---|---|---|---|---|
| AEO (SAP) | 76 (B+) | no run | 76 (B+) | **76 (B+)** | 0 |
| AEO (8-component) | 81 | no run | 81 | **82** | +1 |
| Technical SEO | 83 (B+) | no run | 83 (B+) | **78 (B)** | **−5** |
| Content findings (P0/P1) | 19 (0/7) | no run | 23 (0/8) | **33 (2/9)** | +10 findings, +2 P0 |

**How to read this table:**

- **All three audits read the source files only, for the 16th run in a row.** Cron containment blocked WebFetch, `git log` and the Eleventy build (#8467, #6088). Findings about live behaviour come from the build config. The key one: the future-dated posts are live.
- **The SEO drop has one cause:** the future-dated posts (#11132). Fixing that alone takes SEO back to 83. If the rest of the 10-19 plan also lands, SEO reaches about 93.
- **The flat AEO score hides real movement in both directions:**
  - **Gains:** one model and tool sentence used across 7+ pages, publishing has restarted after a month, and the site has its first original dataset (the 102-guardrails audit).
  - **Losses:** 8 of 9 new posts cite no outside source, posts carry future dates, and `/vision/` was re-dated a second time without fixing its claims.

## Headline

**The site has started publishing again, but each post goes live the moment it is committed.**

The 9-post agentic-verification arc gives the site its first original data and its most specific numbers. Because nothing in the build holds back future-dated posts, all 8 scheduled posts appear to be live already, with dates from 2026-10-27 to 2026-11-17. That one gap:

- costs 5 SEO points
- puts a "November 17, 2026" card at the top of `/blog/`
- takes away the planned staggered launch
- blocks the cheapest fix for the arc's developer-query titles, which is to retitle the posts *before* they publish

At the same time, the 2026-10-22 multi-tool copy update made the homepage hero more developer-oriented. The brand guide names that as a revert trigger for the hero CTA test, which is reviewed on 2026-11-03.

**Last cycle's rule still stands, and it was broken again this week:** do not change `last_updated` unless the page's facts were checked in the same PR (#11138).

## Part 1 — Findings mapped to issues (one issue per defect, per #8469)

Seven new issues were filed this cycle (#11132 to #11138). Every other P0, P1 or P2 finding maps to an issue that is already open. Cron containment does not allow `gh issue comment`, so new evidence for existing issues is in the audit issue body.

### New this cycle

| # | Finding | Source | Priority | Issue |
|---|---|---|---|---|
| N-a | 8 future-dated posts are live before their dates: no publish gate, no scheduled deploy | SEO, Content N6, AEO N5 | **P0** | #11132 |
| N-b | Homepage and pricing drifted to developer register ("coding harness", "ships as a plugin", `/soleur:go`) during the hero test | Content N5 | **P0** | #11133 |
| N-c | Verification-arc titles and metas target developer queries | Content N7 | P1 | #11134 |
| N-d | 8 of 9 new posts cite no outside source | AEO N6 | P1 | #11135 |
| N-e | Arc hygiene: wrong series box, the same lesson repeated in 6 posts, undefined jargon | Content N8, N10, N11 | P2 | #11136 |
| N-f | The 11-04 post's OG image file is missing (404) | SEO | P2 | #11137 |
| N-g | `last_updated` bumped on 7 pages without a fact review, for the second time | Content N1, AEO, SEO P3 | P2 | #11138 |

### Carried

| # | Finding | Source | Priority | Issue | Status vs 10-19 |
|---|---|---|---|---|---|
| 1 | Citation tracker never run: 32 of 32 cells TBD, 19 Mondays missed | AEO | **P0** | #6084 | Open |
| 2 | No third-party Presence surface; Presence has been 14/25 for 5 cycles | AEO | **P0** | #5610, #2601 | Open |
| 3 | `/vision/` cards describe GPT-4o routing and the CEO Dashboard as shipped, and the page was re-dated again | AEO, Content F9 | **P0** | #6376 | Partly fixed (FAQ), cards still wrong |
| 4 | Cron containment blocks the build, WebFetch and `git log` | all three | **P0** (process) | #8467, #6088 | Open (16th run) |
| 5 | The hero self-host button lands on a terminal manual: 5 install blocks and a 6-column command table | Content F11 | P1 | #2669 | **Worse** |
| 6 | Getting-started title says "Two Commands"; the FAQ says "Nothing to install" | Content F3 | P1 | #9107 | Open |
| 7 | Blog index title and meta target developer queries | Content F1 | P1 | #9104 | Open |
| 8 | Founder posts filed as Engineering Deep Dives, now 9 more | Content F2 | P1 | #9105 | Open, wider |
| 9 | Competitor revenue stated as fact; compare-cursor re-dated with it unchanged | Content F4 | P1 | #7179 | Open |
| 10 | "9 hats" vs 8 departments | Content F5 | P1 | #8462 | Open |
| 11 | Homepage hero and meta lead with CaaS | Content F7 | P1 | #9112 | Open |
| 12 | `/skills/` title is brand-only and the H1 is technical | Content F6 | P1 | #5601 | Open |
| 13 | Founder `Person` `sameAs` conflict | SEO | P1 | #9102 | Open |
| 14 | FAQPage schema with no visible FAQ, now **5 posts** (adds the 11-04 post, which has an empty heading) | SEO, AEO | P1 | #9101 | **Worse** |
| 15 | CaaS pillar superlatives; "the numbers tell the story" with no numbers | AEO | P1 | #6085 | Open |
| 16 | September posts cite no outside sources | AEO | P1 | #9108 | Open |
| 17 | `/pricing/` says "ready to sign"; the "70%" has three meanings | Content F10, AEO | P2 | #9111 | Open |
| 18 | Model-support claims | Content F9 | P2 | #9500 | **Mostly fixed** (only the vision cards remain, under #6376) |
| 19 | `/ai-cmo/` gives three costs ($240K, $290K, ~$294K) | Content F8 | P2 | #9499 | Open |
| 20 | Conflicting CaaS origin claims | AEO, Content | P2 | #9501 | Open |
| 21 | `/agents/` says agents are "trained", and still says Claude Code only | Content F12 | P2 | #6378 | Open |
| 22 | `/community/` title and H1 are generic | Content F13 | P2 | #6377 | Open |
| 23 | Sitemap `lastmod` ignores `updated:` | SEO | P2 | #9106 | Open |
| 24 | 21 undated pages show the build time; `/agents/` and `/skills/` are still June | SEO, AEO | P2 | #7180, #8468 | Partly fixed (compare pages re-dated) |
| 25 | Homepage `og:title` is just "Soleur" | SEO | P2 | #2674 | Open |
| 26 | Generic `og:image:alt` on 39 of 40 posts | SEO | P2 | #2557 | Open, wider |
| 27 | `llms.txt` coverage gap | SEO | P2 | #7181 | Open |
| 28 | No customer or tester voice | AEO | P2 | #2603 | Partly fixed (first-party data shipped) |
| 29 | Publishing gap | AEO, Content | — | #8466 | **Fixed for cadence** (9 posts). The founder-problem gap pieces are still unpublished. Close #8466 once the date gate (#11132) makes the cadence real |

**P3 items, no issues filed** (kept in the source reports):

- `validate-seo.sh` gate gaps. 3 of the 4 new defects this week would have failed a better gate: future dates, missing OG file, and a FAQ heading with nothing under it. The fixes are listed inside #11132, #11137 and #9101.
- `statsLastVerified` 2026-10-06 sits behind `last_updated` 2026-10-22. This is folded into #11138.
- Carried P3s: "This Is the Way" label, "running autonomously" (now also on `/vision/:135`), footer link to `known-external-tools`, "Your AI organization is ready." on pricing, and About filler.

## Part 2 — Prioritised plan

**Constraint (unchanged):** the hero button is under test until 2026-11-03 (#9588, #9605). Nothing below changes the button or its target. #11133 changes copy *around* the button **to undo** drift that is already a revert trigger. Ship it before 11-03 and note it on #9588.

### P0 — this week (before 2026-10-27, when the next post is dated)

1. **Date gate for scheduled posts (#11132).** In one PR:
   - an Eleventy preprocessor that drops `/blog/` inputs with `date > now`
   - a daily `schedule:` on `deploy-docs.yml`
   - a `validate-seo.sh` check that fails on a future `<lastmod>` or `published_time`

   This restores the staggered launch, gets the 5 SEO points back, and makes P1 item C possible. It is about 1 hour of work.
2. **Undo the developer-register drift on `/` and `/pricing/` (#11133).** Change the hero sub-line, "ships as a plugin", `/soleur:go` in the FAQ, and "harness" in the pricing FAQ. Update the JSON-LD text to match. Note the change on #9588.
3. **Fix the `/vision/` cards (#6376).** Move the GPT-4o routing, multi-provider keys and CEO Dashboard cards under a "Roadmap" H2, in the future tense. The page's FAQ already says the right thing. Do not re-date the page in this PR unless all the facts on it are checked (#11138).
4. **Run the citation-monitoring baseline (#6084)**, 8 queries × 4 engines. It is now 19 weeks overdue. Schedule it with `soleur:schedule` so it no longer depends on someone remembering.
5. **Cron containment (#8467, #6088).** Allow the Eleventy build, `validate-seo.sh`, WebFetch to soleur.ai and read-only `git log`. Without them, the date-gate regression could only be inferred, not confirmed.

### P1 — five small PRs, no new pages

| PR | Scope | Issues | Files |
|---|---|---|---|
| **A. Facts and counts** | Attribute competitor revenue in the sentence; use "8 jobs, 7 of them" as the only count; one AI CMO figure; one CaaS origin line; source the "70%" figures or remove them | #7179, #8462, #9499, #9501, #9111 | `index.njk`, `pricing.njk`, `ai-cmo.njk`, `company-as-a-service.njk`, `compare-soleur-vs-cursor.njk`, `glossary`, 4 posts |
| **B. Schema and entity parity** | Visible FAQ on the **5** schema-only posts (including the 11-04 empty heading); one `Person` `sameAs`; a reverse FAQ check in `validate-seo.sh`; the missing OG image (#11137) | #9101, #9102, #11137 | 5 posts, `about.njk`, `validate-seo.sh`, `images/blog/` |
| **C. Verification arc, before each spoke publishes** | Founder-problem titles and metas (keep the slugs); 2+ outside sources per spoke plus a link back to Osmani; a series entry in `pillars.js`; state the lesson once in the hub; define or replace the jargon | #11134, #11135, #11136 | 8 arc posts, `_data/pillars.js` |
| **D. Blog hub repositioning** | Founder-first `/blog/` title and meta; a founder-playbook category so the 9 new posts stop landing in "Engineering Deep Dives"; outside sources for the September posts | #9104, #9105, #9108 | `blog.njk`, posts |
| **E. First-contact pages** | Getting-started: founder lede, a waitlist-consistent title, and the 5-tool CLI reference collapsed under "Self-hosted" (urgent, because the hero self-host button lands here); `/skills/` seoTitle; CaaS pillar superlatives; homepage meta (hero copy after 2026-11-03) | #2669, #9107, #5601, #6085, #9112 | `getting-started.njk`, `skills.njk`, `company-as-a-service.njk`, `index.njk` |

**Sequencing note:** PR C depends on P0 item 1. If the date gate lands first, the 7 unpublished spokes can be retitled freely. If it does not, treat them as published: fix facts and citations only, and apply the title rule to the next series. **This is a decision for the CMO; it is recorded on #11134.**

**Expected scores if P0 and P1 land:** AEO 81–83 (B), SEO 90+ (A−).

### P2 — trust scaffolding and freshness (next 2–3 weeks)

- **Honest freshness (#11138, #7180, #8468, #9106):**
  - add a guard so `last_updated` cannot move without a facts-reviewed marker
  - roll back or re-check the 7 pages dated 2026-10-22
  - date the 21 undated pages
  - make the sitemap `lastmod` use `updated:`
  - re-check `/agents/` and `/skills/` before dating them
- **Social and AI metadata:** homepage `og:title` (#2674), per-post `ogImageAlt` (#2557, now 39 posts), and `llms.txt` coverage of the pillars, glossary and compare pages (#7181).
- **Accuracy copy:** `/agents/` says "trained" and Claude-only (#6378); `/community/` title (#6377). Also fix the P3 lines "running autonomously" and "is ready" in the same PR.

### P3 — new content (after P1 lands)

1. **Turn the restarted cadence into founder-problem content (#8466).** The 11-04 recurring-job post is the template: founder problem first, mechanism second, a usable checklist, a plain call to action. Next up are the planned gap pieces: contracts without a lawyer, AI marketing for a solo founder, hire or delegate, self-hosted vs hosted. Aim for 2 a month. Each needs a visible FAQ, matching schema, and at least 2 outside sources.
2. **Build on the first-party data.** The 102-guardrails audit table is the most citable asset on the site. Write a founder-register summary ("What 102 automated checks taught us about trusting AI work"), and pitch the dataset as a third-party Presence surface (#5610) via Show HN or a newsletter.
3. **Beta-checkpoint data post (#2603):** aggregate cohort results and tester quotes, with consent.
4. **Third-party surface (#2601, #5610):** pick one of Show HN, Product Hunt or AlternativeTo/G2 once the nav rail (#8144) ships.
5. **On hold** until hub↔blog cannibalisation is resolved (#8463, #8464): new pillars, comparison pages and use-case pages (including #9591).

## Part 3 — Keyword note

Keyword research is still the 2026-05-25 set, now 154 days old, because WebSearch is blocked in cron.

The new arc shows what happens without an up-to-date founder keyword list. Writers fall back to the mechanism's name ("property test", "flaky test"), which is a developer query. Until head terms can be re-researched, use this rule from the Blog note: **the title names the founder's problem, and the mechanism appears in the body only.** Re-check head terms in the first run that has network access.
