# Content Plan — soleur.ai — 2026-10-19

Built from the three audits written in this cycle:

- [2026-10-19-content-audit.md](./2026-10-19-content-audit.md): 0 P0, 8 P1, 7 P2, 8 P3 (19 carried, 4 new)
- [2026-10-19-aeo-audit.md](./2026-10-19-aeo-audit.md): **76/100 (B+)**, 8-component 81
- [2026-10-19-seo-audit.md](./2026-10-19-seo-audit.md): **83/100 (B+)**

## Scores and trend

| Audit | 2026-05-25 | 2026-09-28 (#9100) | 2026-10-05 | 2026-10-12 | 2026-10-19 | Change vs 10-05 |
|---|---|---|---|---|---|---|
| AEO (SAP) | 73 (C) | 71 (C) | 76 (B+) | no run | **76 (B+)** | 0 |
| AEO (8-component) | 79 | 79 | 81 | no run | **81** | 0 |
| Technical SEO | 95 | 81 (B+) | 83 (B+) | no run | **83 (B+)** | 0 |
| Content issues (P1) | 12 | 26 (5) | 19 (7) | no run | **23 (8)** | +4 issues, +1 P1 |

**How to read this table:**

- **The 2026-10-12 run did not produce an audit.** It stopped with "Credit balance is too low" (#10077). This cycle is compared with 2026-10-05.
- **All three audits read the source files only.** For the 15th run in a row, cron containment blocked WebFetch, `curl`, `git log` and the Eleventy build (#8467, #6088). Because `git log` was blocked, the audits could not see which commits landed after 10-05. Changes were inferred from frontmatter dates and file contents.
- **The flat scores are honest.** Since 10-05, **no P1 or P2 issue from any of the three audits has been fixed.** Some things did get better: the Amodei quote is now sourced and dated (#9579), the homepage illustration is labelled as sample data (#9577), five core pages carry fresh dates, and the hosted and self-hosted messages now agree. One new defect cancelled those gains, as described below.

## Headline

The two-week diagnosis still holds. **The site needs its existing pages to agree with each other and with the facts.** This cycle adds a sharper version of that problem.

On 2026-10-06 the `last_updated` dates on `/vision/`, `/pricing/`, `/`, `/about/` and `/getting-started/` were moved forward, but the claims on those pages were not re-checked. `/vision/` now shows "Last updated October 6, 2026" above present-tense claims that multi-provider keys, GPT-4o routing and a CEO Dashboard already work. `/pricing/` shows the same date above "ready to sign" and an unsourced "70%". A fresh date tells readers and AI engines that someone re-checked the page. Here it vouches for claims that are false.

**Rule for this plan: do not change `last_updated` unless the page's facts were checked in the same PR.**

No blog posts have been published since 2026-09-26, a 23-day gap (#8466).

## Part 1 — Findings mapped to issues (one issue per defect, per #8469)

Every P0, P1 and P2 finding belongs to an issue that is already open. **No new issues were filed this cycle.** Cron containment does not allow `gh issue comment`, so the new evidence for each existing issue is written in the audit issue body (#10516).

| # | Finding | Source | Priority | Issue | Status vs 10-05 |
|---|---|---|---|---|---|
| 1 | Citation-monitoring tracker never run (32/32 cells TBD, about 18 weeks missed) | AEO | **P0** | #6084 | Open |
| 2 | Presence stuck at 14/25 for 4 audits; no third-party surface | AEO | **P0** | #5610, #2601 | Open |
| 3 | `/vision/` presents roadmap features as shipped, now under a 2026-10-06 "Last updated" date | AEO, Content N1 | **P0** | #6376 | Open, **worse** |
| 4 | Cron containment blocks the build, `validate-seo.sh`, WebFetch and `git log` | all three | **P0** (process) | #8467, #6088 | Open (15th run) |
| 5 | Getting-started reads like a terminal manual, and the homepage's main self-hosted button now sends visitors straight to it | Content F11 | **P1** (was P2) | #2669 | Open, **raised** |
| 6 | `/getting-started/` title says "Install… in Two Commands", the button is the waitlist, and the FAQ says "Nothing to install" | Content F3 | P1 | #9107 | Open |
| 7 | Blog index title and meta target "agentic engineering" | Content F1 | P1 | #9104 | Open |
| 8 | Founder posts filed under engineering categories | Content F2 | P1 | #9105 | Open |
| 9 | Competitor revenue stated as fact: $1B on 4 pages, but **$2B+** in the Cursor blog FAQ | Content F4 | P1 | #7179 | Open, **wider** |
| 10 | "9 hats / nine departments" vs 8, now also in `one-person-billion-dollar-company.md` | Content F5 | P1 | #8462 | Open, **wider** |
| 11 | Homepage meta and hero use "Company-as-a-Service" 4 times before stating the founder's problem | Content F7 | P1 | #9112 | Open |
| 12 | `/skills/` title is brand-only and the H1 is technical | Content F6 | P1 | #5601 | Open |
| 13 | Founder `Person` has company `sameAs` on `/about/` and personal accounts on blog posts | SEO | P1 | #9102 | Open |
| 14 | FAQPage JSON-LD with no visible FAQ: **4 posts** (the CaaS-platform post now shows its FAQ in `<details>`) | SEO, AEO | P1 | #9101 | Partly fixed (5 → 4) |
| 15 | CaaS pillar superlatives; "the numbers tell the story" with no numbers | AEO | P1 | #6085 | Open |
| 16 | September posts cite only their own PRs and repo, no outside sources | AEO | P1 | #9108 | Open |
| 17 | Publishing gap: none since 2026-09-26 (23 days) | AEO, Content | P1 (AEO) / P2 | #8466 | Open, **longer** |
| 18 | `/pricing/` "ready to sign"; "70%" means three things, two of them uncited, and could pick up the Osmani citation by mistake | Content F10, AEO | P2 | #9111 | Open, **wider** |
| 19 | Model-support claim differs per page. `page-freshness.njk` now adds "model-agnostic" to `/agents/`, `/skills/` and `/vision/` | Content F9, AEO | P2 | #9500 | Open, **wider** |
| 20 | `/ai-cmo/` cost: $240K title, $290K meta, ~$294K table | Content, SEO | P2 | #9499 | Open |
| 21 | Conflicting CaaS origin claims | AEO | P2 | #9501 | Open |
| 22 | `/agents/` says agents are "trained" | Content | P2 | #6378 | Open |
| 23 | `/community/` title and H1 are generic | Content | P2 | #6377 | Open |
| 24 | Sitemap `lastmod` ignores `updated:` (4 posts) | SEO | P2 | #9106 | Partly fixed |
| 25 | 21 pages have no `date:`; `/agents/`, `/skills/` and compare pages still dated June | SEO, AEO | P2 | #7180, #8468 | Partly fixed |
| 26 | Homepage `og:title` is just "Soleur" | SEO | P2 | #2674 | Open |
| 27 | 30/31 posts use generic `og:image:alt` | SEO | P2 | #2557 | Open |
| 28 | `llms.txt` leaves out pillars, glossary, compare pages and posts | SEO | P2 | #7181 | Open |
| 29 | No original data or customer voice | AEO | P2 | #2603 | Open |

**P3 items, no issues filed** (kept in the source reports):

- New: the "Agents Execute… autonomously" card contradicts the illustration on the same page (`index.njk:82`).
- New: the sitewide footer links to the developer page `known-external-tools`. That page has no `date:` and is not in `llms.txt`.
- New: the pricing waitlist heading says "Your AI organization is ready." while hosting is still coming soon.
- New: `skill-libraries-vs-workflow-plugins.md` has a visible FAQ but no FAQ schema, and the `validate-seo.sh` FAQ check only tests one direction.
- Carried: the P3s from 10-05.

## Part 2 — Prioritised plan

**Constraint:** the homepage hero button is under test until 2026-11-03 (#9588, #9605). No item below changes the button. Hero copy changes (#9112) must leave the button and its target alone until the test ends.

### P0 — stop misinformation and unblock measurement (this week)

1. **Fix `/vision/` in one PR (#6376, with #9500).** Move the multi-provider, GPT-4o and CEO Dashboard cards under a "Roadmap" H2 written in the future tense. State one model-support claim, and fix the "model-agnostic" line in `_includes/page-freshness.njk:26` in the same PR. This is the only item where the site currently makes false claims under a fresh date.
2. **Run the citation-monitoring baseline once (#6084).** 8 queries × 4 engines. If it slips a fourth time, schedule it with `soleur:schedule` so it no longer depends on someone remembering.
3. **Allow the Eleventy build, `validate-seo.sh`, WebFetch to soleur.ai and read-only `git log` in cron containment (#8467, #6088).** Without them every audit is source-only and cannot attribute changes to commits. Separately, the 10-12 credit failure (#10077) cost a full week of trend data.

### P1 — four small PRs, no new pages

| PR | Scope | Issues | Files |
|---|---|---|---|
| **A. Facts and counts** | Attribute competitor revenue inside the sentence and use one figure ($1B vs $2B+); make "8 jobs, 7 of them" the only count, including the billion-dollar post; one AI CMO figure; one CaaS origin line; give the "70%" claims sources or remove them | #7179, #8462, #9499, #9501, #9111 | `company-as-a-service.njk`, `ai-agents-for-solo-founders.njk`, `compare-soleur-vs-cursor.njk`, `index.njk`, `ai-cmo.njk`, `glossary`, `pricing.njk`, 3 posts |
| **B. Schema and entity parity** | Visible FAQ on the 4 posts; one `Person` `sameAs` set; make the FAQ check in `validate-seo.sh` test both directions | #9101, #9102 | 4 posts, `about.njk`, `_data`, `validate-seo.sh` |
| **C. Blog hub repositioning** | Founder-first `/blog/` title and meta; a founder-playbook category; refile the 2 September posts; add 2 outside sources to each | #9104, #9105, #9108 | `blog.njk`, 2 posts |
| **D. First-contact pages** | Getting-started: a founder-language lede and a title that matches the waitlist, with the CLI reference in a "Self-hosted" section (this is now urgent because the hero self-host button lands there); `/skills/` seoTitle; CaaS pillar superlatives; homepage meta (hero copy after 2026-11-03) | #2669, #9107, #5601, #6085, #9112 | `getting-started.njk`, `skills.njk`, `company-as-a-service.njk`, `index.njk` |

**Expected scores if P0 and P1 land:** AEO 82–84 (B), SEO 90+ (A−). This is the same projection as 10-05, because nothing from that plan has shipped yet.

### P2 — trust scaffolding and freshness (next 2–3 weeks)

- **Freshness, done honestly:** add dates to the 21 undated pages; make sitemap `lastmod` read `updated:`; re-check the facts on `/agents/`, `/skills/` and both compare pages **before** changing their dates (#7180, #8468, #9106).
- **Social and AI metadata:** homepage `og:title` (#2674), per-post `ogImageAlt` (#2557), and `llms.txt` coverage of the pillars, glossary and compare pages. Do not add `known-external-tools` to `llms.txt` (#7181).
- **Accuracy copy:** `/agents/` "trained" (#6378), `/community/` title (#6377), and the P3 "autonomously" and "is ready" lines if they fit in the same PR.

### P3 — new content (only after P1 lands)

1. **Restart publishing (#8466).** Publish 2 founder-problem posts a month under the Blog note rules in the brand guide. Each post needs a visible FAQ, matching FAQ schema, and at least 2 outside sources.
2. **Beta-checkpoint data post (#2603).** Publish aggregate cohort results and tester quotes, with consent. This is the strongest lever for Authority and Presence.
3. **Third-party surface (#2601, #5610).** Pick one of Show HN, Product Hunt or AlternativeTo/G2 after the nav rail (#8144) ships.
4. **On hold** until hub↔blog cannibalisation is resolved (#8463, #8464): new pillars, comparison pages and use-case pages. The compare-hub work in #9591 is part of this hold.

## Part 3 — Keyword note

Keyword research is still the 2026-05-25 set, now 147 days old, because WebSearch is blocked in cron. The Blog note in the brand guide already sets founder-problem search intent for posts. Re-check head terms in the first run that has network access.
