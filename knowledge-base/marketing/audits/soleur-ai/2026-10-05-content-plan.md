# Content Plan — soleur.ai — 2026-10-05

Synthesised from the three audits written in this cycle:

- [2026-10-05-content-audit.md](./2026-10-05-content-audit.md) — 0 P0, 7 P1, 7 P2, 5 P3
- [2026-10-05-aeo-audit.md](./2026-10-05-aeo-audit.md) — **76/100 (B+)**
- [2026-10-05-seo-audit.md](./2026-10-05-seo-audit.md) — **83/100 (B+)**

## Scores and trend

| Audit | 2026-05-25 (on disk) | 2026-09-28 (#9100, not on disk) | 2026-10-05 | Δ vs 09-28 |
|---|---|---|---|---|
| AEO (SAP) | 73 (C) | 71 (C) | **76 (B+)** | +5 |
| AEO (8-component) | 79 | 79 | 81 | +2 |
| Technical SEO | 95 (B+/A published) | 81 (B+) | **83 (B+)** | +2 |
| Content issues | 12 | 26 (5 P1) | 19 (7 P1) | — |

**Read the deltas with care:**

- **The 09-28 report files never landed in the repo.** The 09-14 and 09-21 files are missing too, so the newest audits on disk are from 2026-05-25. The subagents compared against May; this plan reconciles against the #9100 issue body.
- **All three audits are source-only.** Cron containment blocked WebFetch, `curl` and the Eleventy build (14th consecutive run; #8467, #6088). No production rendering was observed.
- **The AEO gain is real but small.** It comes from `/getting-started/` (definition plus 3 citations), `/glossary/`, and the comparison section on the homepage. The main constraint, Presence at 14/25, hasn't moved in three cycles.

## Headline

Last week's diagnosis still holds: **the site does not need more pages. It needs its existing pages to agree with each other and with the facts.** No P1 from #9100 shipped this week. Every P0 and P1 below except the citation-monitoring run is a copy or template change of under an hour.

## Part 1 — Findings mapped to issues (deduped by defect, per #8469)

| # | Finding | Source | Priority | Issue |
|---|---|---|---|---|
| 1 | Citation-monitoring tracker never run (32/32 cells TBD, ~16 missed weeks) | AEO F2 | **P0** | #6084 |
| 2 | Presence flat at 14/25 for three cycles; no third-party surface | AEO F1 | **P0** | #5610, #2601 |
| 3 | `/vision/` presents multi-provider keys / GPT-4o routing as shipped | AEO F3, Content F16 | **P0** (AEO) / P1 | #6376 |
| 4 | Cron containment blocks build, `validate-seo.sh`, WebFetch | all three | **P0** (process) | #8467, #6088 |
| 5 | Blog index title and meta target developer queries | Content F1 | P1 | #9104 |
| 6 | Founder posts misfiled; no founder-playbook category | Content F2 | P1 | #9105 |
| 7 | `/getting-started/` title says "Install… in Two Commands", CTA is the waitlist, FAQ says "Nothing to install" | Content F3 | P1 | #9107 (now also covers the title) |
| 8 | Cursor $1B / Lovable $200M ARR stated as fact on 3 hubs and 3 posts | Content F4 | P1 | #7179 |
| 9 | "9 hats… hand off 8" vs 8 departments / "8 jobs, 7 of them" (also Tanka and Devin posts) | Content F5 | P1 | #8462 |
| 10 | `/skills/` title brand-only, H1 technical | Content F6 | P1 | #5601 |
| 11 | Homepage hero and meta lead with CaaS | Content F7 | P1 | #9112 |
| 12 | Founder `Person` `@id` has company `sameAs` on `/about/`, personal on posts | SEO P1 | P1 | #9102 |
| 13 | FAQPage JSON-LD with no visible FAQ on 5 posts | AEO F6 | P1 | #9101 |
| 14 | `/company-as-a-service/` superlatives; "the numbers tell the story" with no numbers | AEO F4, F5 | P1 | #6085 |
| 15 | New September posts carry 0–1 external citations | AEO F7 | P1 | #9108 (extends to `parked-vs-forgotten-ideas`) |
| 16 | **`/ai-cmo/` cost: $240K title, $290K meta, ~$294K table** | Content F8 | P2 | **#9499** (new) |
| 17 | **Claude-only claims (homepage, pricing) vs Grok Build docs (getting-started) vs "model-agnostic" (vision)** | Content F9 | P2 | **#9500** (new) |
| 18 | **Conflicting CaaS origin claims ("Soleur coined" / "not one company's term" / "a leading" / "one of the first"); weak a16z citation on glossary entry** | AEO F9, F10 | P2 | **#9501** (new) |
| 19 | `/pricing/` "ready to sign" autonomy overclaim; unsourced 70% (also on `/compare/soleur-vs-cursor/`) | Content F10, F17; AEO F8 | P2 | #9111 |
| 20 | Getting-started is a terminal manual | Content F11 | P2 | #2669 |
| 21 | `/agents/` says agents are "trained" | Content F12 | P2 | #6378 |
| 22 | `/community/` title and H1 generic | Content F13 | P2 | #6377 (dups #6083, #5618, #5604 — see #8146) |
| 23 | Publishing gap 2026-06-15 → 2026-09-25 | Content F14 | P2 | #8466 |
| 24 | Sitemap `lastmod` ignores `updated:`/`last_updated:` | SEO P2 | P2 | #9106 |
| 25 | 22 undated pages; pillar pages show no freshness block | SEO P2 | P2 | #7180, #8468 |
| 26 | Homepage `og:title` = "Soleur" | SEO P2 | P2 | #2674 |
| 27 | 30/31 posts use generic `og:image:alt` | SEO P2 | P2 | #2557 |
| 28 | `llms.txt` omits pillars, glossary, compare, posts | SEO P2 | P2 | #7181 |
| 29 | Core pages' `last_updated` is 2026-06-01 (4 months) | AEO F11, Content F19 | P2 | #7180 (same freshness class) |
| 30 | No original data or customer voice | AEO F12 | P2 | #2603 |

P3 items (section labels, Claude Code doc URL drift, vision hero summary, About title, `og:type` on About, `twitter:creator`, Atom author, CWV unmeasured, reused OG images) stay in the source reports and get no issues.

## Part 2 — Prioritised plan

### P0 — unblock measurement (this week)

1. **Run the citation-monitoring baseline once** (#6084): 8 queries × 4 engines. Until it runs, Presence can't be measured, so it can't be managed. If it slips again, schedule it with `soleur:schedule`.
2. **Fix `/vision/` present-tense roadmap claims** (#6376). Move the multi-provider and GPT-4o cards under a "Roadmap" H2 written in the future tense. Resolve finding 17 (model-support claim, #9500) in the same PR so every page makes one claim.
3. **Allowlist the Eleventy build, `validate-seo.sh` and WebFetch to soleur.ai in cron containment** (#8467, #6088). Also find out why the 09-14, 09-21 and 09-28 audit files never persisted. Both are needed before this series can show a trend.

### P1 — four small PRs, no new pages

| PR | Scope | Issues | Files |
|---|---|---|---|
| **A. Facts and counts** | Attribute competitor revenue in-sentence; make "8 jobs, 7 of them" the only count; one AI CMO figure ($290K title/meta, ~$294K table); one CaaS origin line | #7179, #8462, #9499, #9501 | hubs, `index.njk`, `ai-cmo`, `glossary`, 5 posts |
| **B. Schema and entity parity** | Visible FAQ blocks on 5 posts; one `Person` `sameAs` set | #9101, #9102 | 5 posts, `about.njk`, `_data` |
| **C. Blog hub repositioning** | Founder-first `/blog/` title/meta; add a founder-playbook category; refile the 2 newest posts; add 1–2 citations to each | #9104, #9105, #9108 | `blog.njk`, 2 posts |
| **D. First-contact pages** | Homepage hero and meta in pain-point register; getting-started title matching the waitlist; `/skills/` seoTitle; CaaS-pillar superlatives | #9112, #9107, #5601, #6085 | `index.njk`, `getting-started.njk`, `skills.njk`, `company-as-a-service` |

**Projected if P0 and P1 land:** AEO 82–84 (B), SEO 90+ (A−).

### P2 — trust scaffolding and freshness (next 2–3 weeks)

- **Freshness:** date the 22 undated pages, include `page-freshness.njk` on pillar pages, have sitemap `lastmod` read `updated:`, and re-review the facts on core pages before bumping `last_updated` (#7180, #8468, #9106).
- **Social and AI metadata:** homepage `og:title` (#2674), per-post `ogImageAlt` (#2557), and `llms.txt` coverage of pillars, glossary and compare pages (#7181).
- **Autonomy and accuracy copy:** `/pricing/` "ready to sign" and 70% (#9111), `/agents/` "trained" (#6378), `/community/` title (#6377).
- **Getting-started split** (#2669): a founder-register body, with CLI reference behind a "self-hosted" section.

### P3 — new content (gated on P1 landing)

1. **Beta-checkpoint data post** (#2603). Publish aggregate results from the founding cohort (activation, departments used) with tester quotes, given consent. This is the strongest Authority and Presence lever available, and it is original data.
2. **Cadence:** 2 founder-problem posts a month under the 2026-09-25 Blog note rules (#8466). Every post gets a visible FAQ and at least 2 external sources.
3. **Third-party surface:** one of Show HN, Product Hunt (#2601), or AlternativeTo/G2 (#5610), after the nav rail (#8144) ships.
4. **Deferred** until hub↔blog cannibalization (#8463, #8464) is resolved: new pillars, comparison pages, use-case pages.

## Part 3 — Keyword note

Keyword research is carried forward from 2026-05-25 (133 days old) because WebSearch is blocked in cron. The 2026-09-25 brand guide Blog note already dictates founder-problem search intent for posts. Revalidate head terms when a networked run is possible.
