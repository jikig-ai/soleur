# Growth Audit Report — 2026-04-06

**Site:** Soleur | **URL:** <https://soleur.ai>
**Date:** 2026-04-06 | **Auditor:** Automated (Claude Sonnet 4.6)
**Previous audit:** 2026-03-30 | **Audit type:** Weekly growth audit

---

## Executive Summary

Seven days of execution since the 2026-03-30 audit. The two P0 brand compliance issues (homepage and Getting Started meta descriptions containing "plugin") were fixed on 2026-04-01, ending a 13-day persistent violation. SEO Refresh Queue Priority 1 items are fully complete: FAQ JSON-LD added to all major pages, Vision H1 rewritten, "synthetic labor" replaced, external citation added to Vision, keyword gaps addressed on Agents/Skills pages.

Four distribution pieces are now scheduled for the coming week: Vibe Coding vs. Agentic Engineering (Apr 7), PWA Installability (Apr 10), Soleur vs. Paperclip (Apr 15), and Repo Connection Launch (Apr 17). The pipeline is the fullest it has been in the audit history.

One new brand compliance issue: the Soleur vs. Paperclip distribution content (all seven channel posts) uses "9 departments" instead of the brand-correct "8 departments." This must be fixed before the April 15 publish date.

Analytics remain stale — no data since Week 2 (2026-03-23). With the Vibe Coding article distributing tomorrow and three more pieces in the pipeline, analytics recovery is urgent to measure whether the content is driving traffic.

The About/Founder page (Gap 11) is now overdue. It was a Month 1 deliverable; the month ended April 6. Every week without it is a compounding E-E-A-T deficit.

AEO score is estimated at 80–82/100, crossing the 80 threshold for the first time due to FAQ JSON-LD now present on all major pages.

---

## 1. Resolved Issues Since 2026-03-30

| Issue | Status at 2026-03-30 | Resolved |
|-------|---------------------|---------|
| Homepage meta description: "A Claude Code plugin..." | Unfixed — 13 days | **Fixed 2026-04-01** |
| Getting Started meta: "Install the Soleur Claude Code plugin..." | Unfixed — 13 days | **Fixed 2026-04-01** |
| Vision H1: bare "Vision" — zero keyword value | Unfixed | **Fixed 2026-04-01** — now "The Soleur Vision: Company-as-a-Service for the Solo Founder" |
| Vision: "synthetic labor" / "soloentrepreneurs" not in brand vocabulary | Unfixed | **Fixed 2026-04-01** — "synthetic labor" replaced with "AI agent swarms" |
| Vision: zero external citations | Unfixed | **Fixed 2026-04-01** — Dario Amodei citation added |
| FAQ JSON-LD absent on Agents page | Unfixed | **Fixed 2026-04-01** |
| FAQ JSON-LD absent on Skills page | Unfixed | **Fixed 2026-04-01** |
| FAQ JSON-LD absent on Vision page | Unfixed | **Fixed 2026-04-01** |
| FAQ JSON-LD absent on Getting Started page | Unfixed | **Fixed 2026-04-01** |
| "Why Tools Plateau" FAQ missing JSON-LD | Unfixed | **Fixed 2026-04-01** — converted to details/summary + FAQPage JSON-LD |
| Blog post `dateModified` signals broken | Unfixed | **Fixed 2026-04-01** — `updated` frontmatter + conditional display in template |
| "Open source" keyword absent on Agents page | Unfixed | **Fixed 2026-04-01** |
| "AI workflow automation" keyword absent on Skills page | Unfixed | **Fixed 2026-04-01** |
| Agent count in March 29 distribution content (61 agents, stale) | In draft — pre-publication | **Moot** — publication rescheduled; content already uses 63 agents |
| PWA distribution content in draft (from 2026-03-29) | Draft, unpublished | **Rescheduled** — scheduled for 2026-04-10 |
| Repo connection distribution content in draft (from 2026-03-29) | Draft, unpublished | **Rescheduled** — scheduled for 2026-04-17 |

---

## 2. New Content Since Last Audit (2026-03-30 → 2026-04-06)

### Distribution Content Created

| Date | Piece | Type | Channels | Status |
|------|-------|------|----------|--------|
| ~2026-04-03 | Vibe Coding vs. Agentic Engineering (distribution) | Pillar distribution | Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN | `scheduled` — 2026-04-07 (tomorrow) |
| ~2026-04-03 | Soleur vs. Paperclip comparison | Comparison distribution | Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN | `scheduled` — 2026-04-15 |
| ~2026-04-03 | PWA Installability Milestone (updated from draft) | Milestone announcement | Discord, X, Bluesky, LinkedIn ×2 | `scheduled` — 2026-04-10 |
| ~2026-04-03 | Repo Connection Launch (updated from draft) | Feature launch | Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN | `scheduled` — 2026-04-17 |

### Blog Posts / Web Content

| Piece | Status | Notes |
|-------|--------|-------|
| Vibe Coding vs. Agentic Engineering (article) | **Unknown** — distribution references `/blog/vibe-coding-vs-agentic-engineering/` | Must confirm published before Apr 7 distribution |
| From Department Offices to Command Center (Gap 13) | **Unknown** — scheduled Apr 3–6 | Today (Apr 6) is last day of scheduled window. No artifact found. |
| Soleur vs. Paperclip blog post | **Unknown** — distribution references `/blog/soleur-vs-paperclip/` | Must confirm published before Apr 15 distribution |
| Repo Connection blog post | **Unknown** — distribution references `/blog/your-ai-team-works-from-your-actual-codebase/` | Must confirm published before Apr 17 distribution |

**Critical observation:** Three distribution pieces are scheduled for the next 11 days, all referencing blog URLs. None of those blog post URLs have been confirmed live. Publishing distribution content before the blog posts are live creates broken links in Discord, X, IndieHackers, Reddit, and Hacker News posts.

---

## 3. Brand Compliance Issues

| Priority | Issue | Status | Days Until Publish |
|----------|-------|--------|-------------------|
| **CRITICAL** | Soleur vs. Paperclip distribution content: "9 departments" used across all 7 channel posts. Brand guide: 8 departments. | **Unfixed** | **9 days** (April 15 publish) |

### Detail: "9 departments" in Soleur vs. Paperclip content

All seven channel posts in `distribution-content/2026-04-15-soleur-vs-paperclip.md` contain either "63 agents across 9 departments" or "63 agents, 62 skills, 9 departments." The correct figure across all brand materials (brand guide, X banner, PWA milestone, repo connection, previous audit findings) is **8 departments**.

Publishing this with "9 departments" on April 15 creates a visible discrepancy: anyone reading the comparison who visits soleur.ai will see "8 departments" on the site, while the comparison post says "9." This is the same category of error as the previous "61 agents" stale count issue.

**Action required before April 15:** Replace all instances of "9 departments" with "8 departments" in `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`.

---

## 4. Content Calendar Status (Week of 2026-04-06)

| Date | Task | Status |
|------|------|--------|
| Apr 3–6 | Write "From Department Offices to Command Center" (Gap 13) | **Unknown** — no artifact found in distribution-content/ or blog |
| Apr 7 (tomorrow) | Distribute "Vibe Coding vs. Agentic Engineering" across all channels | **Scheduled** — confirm blog post is live first |
| Apr 10 | Distribute PWA Installability Milestone (5 channels) | **Scheduled** |
| Apr 14–20 | External citations on catalog pages (Gap 12) | **Not started** — per seo-refresh-queue.md |
| Apr 15 | Distribute Soleur vs. Paperclip comparison (7 channels) | **Scheduled** — fix "9 departments" before publish |
| Apr 17 | Distribute Repo Connection Launch (8 channels) | **Scheduled** — confirm blog post is live first |
| Apr 21–27 | Write About/Founder page (Gap 11) | **Overdue** — was Month 1; calendar shifted it to Apr 21 but it should have shipped by now |

**Assessment:** The content pipeline is well-loaded. Execution risk is front-end: blog posts must exist before distribution posts go out. The calendar assumes blog post publication is handled separately; no evidence this has been tracked as a prerequisite gate.

---

## 5. Distribution Gap Analysis

### What is scheduled

| Piece | Publish Date | Channels | HN / Reddit / IndieHackers |
|-------|-------------|----------|---------------------------|
| Vibe Coding vs. Agentic Engineering | 2026-04-07 | Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN | Yes |
| PWA Installability | 2026-04-10 | Discord, X, Bluesky, LinkedIn ×2 | No |
| Soleur vs. Paperclip | 2026-04-15 | Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN | Yes |
| Repo Connection Launch | 2026-04-17 | Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN | Yes |

### Channel coverage after this week

With the Vibe Coding and Repo Connection posts, Soleur will have submitted to Hacker News and Reddit for the first time. This is the largest single distribution expansion in the audit history. Combined HN + Reddit potential for the Repo Connection "Show HN" post (git credential helper isolation, GitHub App token architecture) remains high — technically substantive, under-covered topic, open-source framing.

### Still missing: Product Hunt

Zero Product Hunt launches detected across all audits. Every week this remains unlaunched is a missed backlink and discovery event. High-effort (4–8 hrs) but the highest single-action backlink generator available.

---

## 6. Keyword Alignment Analysis

### Summary

All Priority 1 on-page SEO fixes from the content audit are now complete (per seo-refresh-queue.md, updated 2026-04-01). No new keyword alignment issues were detected in the four new distribution content pieces reviewed. The Vibe Coding article targets "vibe coding vs agentic engineering" — the P2-1 keyword scored 18/20 in the 2026-03-17 audit.

### Remaining keyword gaps

| Gap | Current State |
|-----|--------------|
| "knowledge compounding AI" | No dedicated article. Gap 1 still open. |
| "one person billion dollar company" | No article. Month 2 piece. |
| "AI agents for solo founders" | No dedicated guide. P1 piece in draft (no publish date set). |
| "about / founder" page | No page. E-E-A-T gap continues. |

### Distribution content keyword check

| Piece | Primary Keyword Targeted | Assessment |
|-------|--------------------------|------------|
| Vibe Coding vs. Agentic Engineering | "vibe coding vs agentic engineering" | Strong. Hook tweet leads with the contrast, not a question. LinkedIn version correct length. |
| PWA Installability | Feature announcement (not SEO) | Not keyword-targeted. Social distribution only. |
| Soleur vs. Paperclip | "soleur vs paperclip", "AI company orchestration" | Good complementary positioning. "9 departments" error must be fixed. |
| Repo Connection Launch | "git credential helper isolation" (HN angle) | Technically specific. Correct HN framing. Blog URL uses template literal — verify renders at build time. |

---

## 7. Content Gap Tracker Update

| Gap | Status | Change Since 2026-03-30 |
|-----|--------|--------------------------|
| Gap 1: Knowledge Compounding Narrative | Open | No change |
| Gap 2: CaaS Category Definition | **COMPLETED** | No change |
| Gap 3: Agent Platform vs. AI Organization | Partial | No change |
| Gap 4: Engineering-in-Context Value Prop | Partial | **Vibe Coding article distributing 2026-04-07; Repo Connection distributing 2026-04-17** |
| Gap 5: Autopilot vs. Decision-Maker / Polsia | Partial | No change — "Autopilot vs. Decision-Maker" position paper still unwritten |
| Gap 6: Cursor Positioning | **COMPLETED** | No change |
| Gap 7: Cowork + Microsoft | Partial | No change |
| Gap 8: Paperclip | **Partial** | **Comparison distribution content created, scheduled Apr 15** |
| Gap 9: Price Justification | Open | No change |
| Gap 10: Listicle Presence | Open | No change — HN/Reddit submissions incoming this week (first ever) |
| Gap 11: About/Founder Page | Open | **Overdue — Month 1 ended Apr 6. Now deferred to Apr 21–27.** |
| Gap 12: External Citations on Non-Blog Pages | Open | Scheduled Apr 14–20. Not confirmed started. |
| Gap 13: Command Center Launch Narrative | Partial | **"From Department Offices to Command Center" blog post: status unknown (scheduled Apr 3–6, today is Apr 6)** |

---

## 8. Analytics Status

| Week | Visitors | WoW % | Notes |
|------|----------|-------|-------|
| Week 1 (2026-03-16) | 28 | +133% | Comparison pages driving referrals |
| Week 2 (2026-03-23) | 10 | -64% | Drop attributed to no new content |
| Week 3 (2026-03-30) | **Missing** | — | Analytics workflow not captured |
| Week 4 (2026-04-06) | **Missing** | — | Analytics workflow not captured |

Analytics are now 2 weeks stale. With the Vibe Coding article distributing tomorrow across 7 channels including HN, Reddit, and IndieHackers, Week 4 data (ending ~2026-04-13) will be the first real traffic measurement of whether content-channel distribution moves the needle. Capturing this data promptly is critical for the next audit cycle.

---

## 9. AEO Score Projection

| Metric | 2026-03-17 | 2026-03-23 | 2026-03-25 | 2026-03-30 | **2026-04-06** |
|--------|:----------:|:----------:|:----------:|:----------:|:--------------:|
| AEO Score | 68/100 | 74/100 | 74–76/100 | 76–78/100 | **80–82/100** |
| Blog SAP avg | ~4.5 | 4.7 | ~4.8 | ~4.8 | ~4.8 (no new blog posts) |
| Non-blog SAP avg | ~2.0 | 2.8 | 2.8 | 2.8 | **3.5** (FAQ JSON-LD now on all major pages + Vision citation) |
| Pages with external citations | ~6 | ~8 | ~8 | ~8 | ~8 (no new catalog citations) |
| Pages with FAQ JSON-LD | 3 | 8 | ~8 | ~9 | **~14** (all major pages done) |

Crossing 80 on this audit is attributable to the FAQ JSON-LD sweep across Agents, Skills, Vision, and Getting Started pages on 2026-04-01. Reaching 85+ requires completing Gap 12 (external citations on catalog pages, scheduled Apr 14–20).

---

## 10. Priority Action Items — Week of 2026-04-06

| Priority | Action | Deadline | Impact | Effort |
|----------|--------|----------|--------|--------|
| **P0** | Fix "9 departments" → "8 departments" in all 7 channel posts in `distribution-content/2026-04-15-soleur-vs-paperclip.md` | **Apr 14** (day before publish) | CRITICAL — brand compliance; prevents visible count discrepancy | 15 min |
| **P0** | Confirm "Vibe Coding vs. Agentic Engineering" article is live at `/blog/vibe-coding-vs-agentic-engineering/` before distribution goes out (Apr 7) | **Apr 6–7** | CRITICAL — 7-channel distribution links to this URL | 5 min |
| **P0** | Confirm "From Department Offices to Command Center" blog post status — was scheduled Apr 3–6, today is the last day | **Apr 6** | HIGH — Gap 13 hero content; overdue if not shipped | 30 min (write) or 5 min (confirm) |
| **P1** | Confirm Soleur vs. Paperclip blog post at `/blog/soleur-vs-paperclip/` is live before Apr 15 distribution | **Apr 14** | HIGH — prevents broken links across 7 channels | 5 min to verify |
| **P1** | Confirm Repo Connection blog post at `/blog/your-ai-team-works-from-your-actual-codebase/` is live before Apr 17 distribution | **Apr 16** | HIGH — prevents broken links across 8 channels | 5 min to verify |
| **P1** | Capture Week 3 and Week 4 analytics (2026-03-30 + 2026-04-06) in `analytics/` — 2 weeks of data missing | **Apr 7** | HIGH — can't measure Vibe Coding article impact without baseline | 30 min |
| **P2** | Start About/Founder page (Gap 11) — Month 1 ended today | **Apr 13** (before Apr 14–20 external citations week) | HIGH — E-E-A-T blocker. Easiest page to ship (500–800 words, structured) | 2–3 hrs |
| **P2** | Begin external citations on catalog pages (Gap 12) — scheduled Apr 14–20 | **Apr 14** | HIGH — AEO score jump from 80 to 85+ | 4–6 hrs |
| **P3** | Product Hunt launch planning — no launch detected in 7 weeks of audits | **May** | HIGH backlink potential; low urgency vs. this week's pipeline | 4–8 hrs |

---

## 11. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Vibe Coding article not published before Apr 7 distribution | Medium | HIGH — broken links across 7 channels on day one | Verify today; delay distribution if necessary |
| "9 departments" published in Paperclip comparison | Low (if actioned) | MEDIUM — brand discrepancy visible to comparison readers | Fix file before Apr 15 |
| Analytics workflow not captured before Vibe Coding distribution | High | MEDIUM — no measurement for first HN/Reddit submissions | Pull Plausible Week 3 data this week |
| About/Founder page misses another week | High | MEDIUM — E-E-A-T compounds; author schema blocker | Treat as P2 this week; no longer P3 |

---

_Generated: 2026-04-06. Sources: analytics/trend-summary.md, audits/soleur-ai/2026-03-30-growth-audit.md, brand-guide.md (2026-03-26), content-strategy.md (2026-04-03), seo-refresh-queue.md (2026-04-01), campaign-calendar.md (2026-04-03), distribution-content/2026-04-07-vibe-coding-vs-agentic-engineering.md, distribution-content/2026-04-10-pwa-installability-milestone.md, distribution-content/2026-04-15-soleur-vs-paperclip.md, distribution-content/2026-04-17-repo-connection-launch.md._
