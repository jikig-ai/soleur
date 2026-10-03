---
date: 2026-09-28
report_type: content-plan
scope: soleur.ai
inputs:
  - knowledge-base/marketing/audits/soleur-ai/2026-09-28-content-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-09-28-aeo-audit.md
  - knowledge-base/marketing/audits/soleur-ai/2026-09-28-seo-audit.md
prior_plan: knowledge-base/marketing/audits/soleur-ai/2026-05-25-content-plan.md
brand_guide: knowledge-base/marketing/brand-guide.md (last_updated 2026-09-25; Blog channel note: non-technical founder reader)
author: growth audit (scheduled)
---

# Soleur.ai Content Plan: 2026-09-28

## Executive summary

| Audit | Score | Grade | Delta (vs baseline the auditor used) |
|---|---|---|---|
| AEO (SAP) | **71/100** | **C** | −2 vs 2026-05-25 (73, C). 8-component: 79/100, flat |
| Technical SEO | **81/100** | **B+** | −14 vs 2026-05-25 (95 published, 98 computed) |
| Content | 26 issues: 0 P0, 5 P1, 12 P2, 9 P3 | n/a | 5 of 12 May issues resolved, 4 partly, 2 open, 1 reopened |

**The site does not need more pages. It needs its existing pages to agree with each other and with the facts.** Every P1 in this cycle falls into one of three types:

1. **Content that contradicts itself or the facts:**
   - Cursor revenue is stated two ways.
   - `/vision/` describes roadmap items as shipped.
   - The `/getting-started/` FAQ says "Nothing to install".
   - The workflow is described three different ways.
   - The homepage says 9 hats; the brand guide says 8 jobs.
   - "As seen in: Inc.com" links to an article that is not about Soleur.
2. **Markup that does not match the visible page:**
   - 5 posts have FAQ structured data but no visible FAQ.
   - The founder's profile ID carries two conflicting sets of social links.
3. **Pages competing for the same searches:**
   - Six hub pages from the May–June build target the same queries as their blog twins.
   - The `/blog/` index categorises posts wrongly and still targets the technical reader the 2026-09-25 brand guide dropped.

**Good news:**
- Publishing has restarted, with posts on 2026-09-25 and 2026-09-26.
- `parked-vs-forgotten-ideas` is a model post for the new founder-first blog rule.
- `/glossary/` is now the most extractable content on the site.
- `/pricing/` sources its $95K/month comparison.

### Baseline note: the score series is not continuous

Issue #8460 (the 2026-09-21 run) reported AEO SAP **78 (B+)** and SEO **90 (A−)**, both flat against 2026-09-14. **Neither run's report files ever reached the repository.** The newest files on disk before today were dated 2026-05-25, so today's auditors scored against May.

The 71 and 81 above should **not** be read as a 7-point and 9-point drop in one week:
- **SEO:** today's audit swept all ~62 source pages. May sampled 5 live URLs, and the SEO auditor states about half its drop is wider coverage, not regression.
- **AEO:** part of today's Presence change is a correction to May's score (the Inc.com credit).

Treat **71 / 81 as the new baseline.** Next cycle's delta is only meaningful if these four files are persisted.

### Method limits (same as the last 12 cycles)

`WebFetch` and `curl` were blocked by cron containment, and no `_site/` build exists. All three audits are **source reviews of `plugins/soleur/docs/` on `main`**. They did not observe production. They also did no fresh keyword research: `WebSearch` was unavailable, and the keyword clusters from 2026-05-25 are carried forward, now 126 days old. Tracked in #6088 and #8467.

---

## Part 1: Findings consolidated across the three audits

Each row is one **defect**. Where two or three audits reported the same defect, the rows are merged. The "Tracked" column is the dedup key used in Step 5.5.

| # | Defect | Sources | Priority | Tracked |
|---|---|---|---|---|
| F1 | FAQ structured data with no visible FAQ on 5 blog posts | SEO P1, AEO-02 P1, CA-14 P2 | **P1** | #9101 |
| F2 | Pillar/hub pages compete with blog twins for the same searches (6 pairs) | SEO P1 | **P1** | #8463 (+ #8464) |
| F3 | Founder `Person` `@id` has two conflicting `sameAs` sets; two company LinkedIn URLs | SEO P1 | **P1** | #9102 |
| F4 | Cursor revenue stated two ways ($1B on 4 pages, unattributed "$2B+" in FAQ) | AEO-01 P1 | **P1** | #7179 |
| F5 | "As seen in: Inc.com" presents a thesis citation as press coverage | AEO-04 P1, CA-05 P1 | **P1** | #9103 (related #2604, #2675) |
| F6 | Citation-monitoring tracker never run (0 of 32 cells, ~15 missed weeks) | AEO-03 P1 | **P1** | #6084 (+ #5613) |
| F7 | No independent third-party review or listing surface | AEO-05 P1 | **P1** | #5610 (+ #2601) |
| F8 | `/blog/` index title, meta, intro and categories target technical readers after the 2026-09-25 brand-guide change | CA-01 P1, CA-26 P3 | **P1** | #9104 (H1 overlap with #5617/#5603) |
| F9 | `/blog/` category filter keys on a `CaaS` tag that no post carries | CA-02 P1 | **P1** | #9105 |
| F10 | `/skills/` title is the brand only; H1 and FAQ are in technical register | CA-03 P1, CA-11 P2 | **P1** | #5601 |
| F11 | `/vision/` states roadmap as shipped; revenue copy contradicts pricing | CA-04 P1, CA-15 P2 | **P1** | #6376 |
| F12 | 8 pillar pages have no dates or freshness block | SEO P2 | P2 | #7180 + #8468 |
| F13 | Sitemap `lastmod` ignores `updated:`; getting-started's two dates disagree | SEO P2 | P2 | #9106 |
| F14 | Homepage `og:title` is the bare word "Soleur" | SEO P2 | P2 | #2674 |
| F15 | Generic `og:image:alt` on 30 of 31 posts and all pillars | SEO P2 | P2 | #2557 |
| F16 | CaaS pillar superlatives; "the numbers tell the story" with no numbers | AEO-06, AEO-07 P2 | P2 | #6085 |
| F17 | `/pricing/`: "on autopilot", legal document "ready to sign", uncited "70%", stale "420+ PRs" | CA-13, AEO-08 P2, CA-23 P3 | P2 | #9111 |
| F18 | `/getting-started/` FAQ "Nothing to install" contradicts the waitlist | AEO-09, CA-09 P2 | P2 | #9107 |
| F19 | `/getting-started/` body is mostly CLI reference | CA-08 P2 | P2 | #2669 |
| F20 | `beta-testers-went-quiet`: no call to action, no external citation, orphan `pillar:` key; the founder-ops posts have no pillar | CA-14, AEO-10, CA-16 P2, SEO P3 | P2 | #9108 |
| F21 | Workflow lifecycle described three ways (5 vs 6 stages, different order) | CA-10 P2 | P2 | #9109 |
| F22 | Homepage hero and meta lead with CaaS jargon; FAQ exposes `/soleur:go` | CA-06, CA-07 P2 | P2 | #9112 |
| F23 | `/agents/` overclaims ("trained", "most comprehensive", "within Claude Code") | CA-12 P2 | P2 | #6378 |
| F24 | Stat sourcing: Carta generic hub link, "$20/month total" omits the Claude plan, "more than 80" skills | CA-17, AEO-11 P2, AEO-14 P3 | P2 | #9110 |
| F25 | Hats/jobs mismatch in homepage FAQ and its structured data | AEO-15, CA-19 P3 | P3 (tracked at P1) | #8462 |
| F26 | `llms.txt` omits hub/compare/glossary pages | SEO P3 | P3 (tracked at P1) | #7181 |
| F27 | Publishing gap (resumed 2026-09-25) | AEO-12 P3 | P3 | #8466 (comment: resumed) |
| F28 | Overlong `seoTitle`s, reused OG images, unlinked JSON-LD graph, `/about/` profile polish, banned words, emoji icons, community/about titles, glossary links | SEO P3, CA-18 to CA-25 | P3 | not filed. Batch into the next P2 PR that touches the same files |

---

## Part 2: Prioritized plan

### P0: make the audit series measure something (no content work)

The 2026-09-21 plan prescribed these two items. Both are still open:

| Item | Why | Tracked |
|---|---|---|
| Persist the audit artefacts, and allowlist `npx @11ty/eleventy` + `validate-seo.sh` (and WebFetch to soleur.ai) in cron containment | Two consecutive runs' reports were lost, and 12 runs have not observed production. The score series is broken (see Baseline note). | #8467, #6088 |
| Run the citation-monitoring baseline once (8 queries × 4 engines, 30–45 min, manual) | Every Presence score since June has been an estimate | #6084 |

### P1: one "consistency" PR plus one markup PR (1–2 days total)

These are edits to existing pages. No new pages. Batching them into a small number of PRs is the point: #8146 records that one-line fixes have sat for 2–5 cycles because each became its own issue.

**PR A: facts and claims (content, general register).** F4, F5, F11, F18, F25 (+ F24 at the same time)
- Cursor: one attributed figure on all pages; remove the revenue figure from the Cursor FAQ question (AEO rewrite table). Folds into the #7179 sweep.
- Homepage press strip: relabel "As seen in" to "Why now" / "The thesis" (content audit R5).
- `/vision/`: add "On the roadmap." to the BYO-keys and multi-model cards; fix the "Low barrier" revenue card (content audit R4).
- `/getting-started/` FAQ: lead with today's true answer (AEO rewrite table, content audit R8).
- Homepage FAQ: "Solo founders doing 8 jobs who want help with 7 of them", in both the visible text and the JSON-LD.
- Stat sourcing: "Cursor Pro ($20/month) plus the Claude plan Soleur runs on"; a specific Carta report link or softened wording; "60+" skills.

**PR B: markup parity and entity.** F1, F3
- Add visible FAQ sections (same Q&A, word for word) to the 5 posts, or delete the orphan JSON-LD.
- Add a `validate-seo.sh` check that each FAQPage question name appears in the visible HTML.
- In `/about/`, set the `ProfilePage` Person `sameAs` to `site.author.sameAs` and add an image; choose one company LinkedIn URL.

**PR C: blog hub repositioning.** F8, F9
- `/blog/` title, meta, H1 and category labels per content audit R1 ("Solo Founder Blog: How to Run Every Part of Your Company Alone").
- Replace tag-inferred categories with an explicit `category:` frontmatter key (content audit R2). Minimum fix: `"CaaS"` → `"company-as-a-service"`.

**PR D: one title.** F10: `/skills/` `seoTitle` "AI Workflows for Solo Founders — 60+ Ready-to-Run Skills | Soleur" (content audit R3).

**Decision needed (not a content edit).** F2, keyword cannibalization. For each of the 6 hub↔post pairs, decide whether to consolidate (301 the post into the hub through `seo-bulk-redirects.tf`) or differentiate (retitle the post to a distinct long-tail). #8463 owns this. Recommended default: consolidate `/blog/ai-agents-for-solo-founders/` into the hub, since they share a slug, lead paragraph and OG image; differentiate the rest. Do this before publishing any new hub page.

**Presence (runs in parallel).** F7: launch one independent surface, Product Hunt (#2601), **after** the #8144 nav rail lands, so the traffic has a front door.

### P2: hygiene and register (2–3 weeks)

| Piece | Type | Defects | Tracked |
|---|---|---|---|
| Date hygiene: `date` = `last_updated` + `page-freshness.njk` on 8 pillars; sitemap and `WebPage.dateModified` read `updated`/`last_updated` first | Template + frontmatter | F12, F13 | #7180, #8468, #9106 |
| Social metadata: `seoTitle or title` in `og:title`/`twitter:title`; `ogImageAlt` on 30 posts + pillars | Template + frontmatter | F14, F15 | #2674, #2557 |
| `/pricing/` trust scaffolding: replace "on autopilot" and "ready to sign"; drop or source "70%"; drop "420+ PRs" | Copy | F17 | #9111 |
| Homepage hero pain-point rewrite; remove `/soleur:go` from the FAQ | Copy | F22 | #9112 |
| Canonical lifecycle (Brainstorm → Plan → Build → Review → Ship → Compound) on `/`, `/getting-started/`, `/skills/`, checked against the real skill chain first | Copy | F21 | #9109 |
| `/getting-started/` split: onboarding vs CLI reference | Copy/IA | F19 | #2669 |
| CaaS pillar de-circularization + superlatives | Copy | F16 | #6085 |
| `/agents/` accuracy | Copy | F23 | #6378 |
| `beta-testers-went-quiet`: add CTA, visible FAQ (via PR B), NN/g citation; resolve `pillar:` | Copy | F20 | #9108 |

### P3: new content, gated on P1 merging

The plan **commissions one new page**, and only after PR A–D merge and a citation baseline exists.

| Piece | Type | Target keywords (founder words, per 2026-09-25 Blog note) | Intent | Searchable / shareable | Outline |
|---|---|---|---|---|---|
| **"How to Run a Company Alone: The Solo Founder's Operating System"** (founder-operations pillar) | Pillar page | how to run a business alone, solo founder operations, running a startup by yourself | Informational | Searchable | 1. The problem in founder words: 8 jobs, one person. 2. What has to stay decided: link `parked-vs-forgotten-ideas`. 3. Knowing what customers think: link `beta-testers-went-quiet`. 4. Which jobs to hand off first, and what stays human (trust scaffolding). 5. Visible FAQ + FAQPage JSON-LD. 6. One CTA (waitlist). 7. Cluster members link back to it and to each other. |
| Next 2 blog posts (keep the 2/month cadence restarted on 09-25) | Blog | Founder problems, e.g. "how to write a privacy policy for my startup", "how to price my SaaS" | Informational | Searchable + shareable (LinkedIn Personal) | Follow the `parked-vs-forgotten-ideas` pattern: problem in the first two sentences, outcome before mechanism, one cited external source, visible FAQ, CTA, and `ogImageAlt` set. |

**Deferred again:**
- `/use-cases/*` clusters, `/case-studies/`, `/compare/soleur-vs-lovable/`, `/compare/soleur-vs-feature-dev/` (#5619), per-category blog pillars (#6087).
- Reason: the six existing hub↔post pairs (F2) show what happens when pages ship before their twins are reconciled. Adding more comparison or use-case pages now adds more cannibalization pairs.

---

## Part 3: Scoring matrix (P1–P3 pieces)

Scored 1–5 on customer impact, content-market fit, search/answer-engine potential, and resource cost (inverted: 5 = cheap).

| Piece | Impact | Fit | Search/AEO | Cost (inv.) | Total | Tier |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| PR A: facts and claims | 5 | 5 | 4 | 5 | **19** | P1 |
| PR B: FAQ parity + author entity | 4 | 5 | 5 | 4 | **18** | P1 |
| PR C: blog hub repositioning + filter | 4 | 5 | 4 | 4 | **17** | P1 |
| PR D: `/skills/` title | 3 | 5 | 4 | 5 | **17** | P1 |
| Cannibalization decision (#8463) | 4 | 4 | 5 | 3 | **16** | P1 (decision) |
| Date hygiene | 3 | 4 | 4 | 4 | 15 | P2 |
| Social metadata | 2 | 5 | 3 | 5 | 15 | P2 |
| `/pricing/` trust scaffolding | 4 | 5 | 2 | 5 | 16 | P2 |
| Homepage hero rewrite | 4 | 5 | 3 | 4 | 16 | P2 |
| Lifecycle canonicalization | 2 | 5 | 3 | 5 | 15 | P2 |
| Founder-operations pillar | 4 | 5 | 4 | 2 | 15 | P3 (gated) |

---

## Part 4: Projected next cycle

If P0 and P1 land:
- **AEO** about 76–80 (B+). Driven by Authority +2–3 (F4, F5, F16), Structure +1–2 (F1), and Presence becoming measurable (F6).
- **SEO** about 86–88 (B). Driven by Structured Data back to 5 (F1, F3), and Content Quality +1 once F2 is decided.
- **Content:** P1 count goes from 5 to 0.

These projections assume the four artefacts are persisted, so the next audit compares like with like.

---

## Brand-guide alignment

- **Blog channel note (2026-09-25):**
  - New blog content targets founder-typed queries.
  - Pre-09-25 posts receive facts-only refreshes. No title, slug, H1, meta or keyword changes, except where a rewrite in this plan is marked as needing operator sign-off.
- **Competitor-figure rule (2026-07-20, #6768):** F4 is a direct compliance gap, and it covers machine-read text such as FAQ answers.
- **Soft floors:** prose says "60+". Templates render `stats.*`.
- **Trust scaffolding:** F17 and F22 rewrites keep "you approve what ships" / "you make the calls".
- **Source-available, not open source:** the license is BSL 1.1. The prior "open-source" rewrite suggestion for `/community/` is withdrawn.
