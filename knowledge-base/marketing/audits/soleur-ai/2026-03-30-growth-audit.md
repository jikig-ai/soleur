# Growth Audit Report — 2026-03-30

**Site:** Soleur | **URL:** <https://soleur.ai>
**Date:** 2026-03-30 | **Auditor:** Automated (Claude Sonnet 4.6)
**Previous audit:** 2026-03-25 | **Audit type:** Weekly growth audit

---

## Executive Summary

Two major features shipped between the last audit (2026-03-25) and today: PWA installability (PR #1256) and GitHub repo connection (PR #1257). Distribution content for both was drafted on 2026-03-29 but remains in `status: draft` — not yet published to any channel. This is the most urgent finding: Soleur shipped its two biggest platform milestones to date and the market has not been told.

The Soleur vs. Polsia comparison page was published on 2026-03-26, completing a long-standing P1 gap and strengthening the competitive positioning cluster.

The "plugin" brand compliance violation in homepage and Getting Started meta descriptions remains unfixed for 13 days across three consecutive audits (2026-03-17, 2026-03-23, 2026-03-25, now 2026-03-30). This is a persistent workflow failure, not a forgotten task.

Analytics data is stale (last reading: 10 visitors week of 2026-03-23, -64% WoW). No Week 3 analytics are available to assess whether the Vibe Coding vs Agentic Engineering article (published 2026-03-24) drove search traffic recovery. Publishing the March 29 distribution content and generating Week 3 analytics should both happen this week.

AEO score is estimated at 76–78/100 (Soleur vs. Polsia adds a fifth FAQ-complete comparison page; no catalog page citations have been added yet).

---

## 1. New Content Since Last Audit (2026-03-25 → 2026-03-30)

### Published

| Date | Piece | Type | Status |
|------|-------|------|--------|
| 2026-03-26 | Soleur vs. Polsia | Comparison page | **PUBLISHED** — FAQ JSON-LD present |

### Drafted / Not Yet Published

| Date | Piece | Channels | Status |
|------|-------|----------|--------|
| 2026-03-29 | PWA Installability Milestone | Discord, X, Bluesky, LinkedIn Personal, LinkedIn Company | `draft` |
| 2026-03-29 | Repo Connection Launch ("Your AI Team Now Works From Your Actual Codebase") | Discord, X, Bluesky, LinkedIn Personal, LinkedIn Company, IndieHackers, Reddit, Hacker News | `draft` |

**Critical gap:** Both distribution pieces are high-distribution-priority events (8-channel + 5-channel). The repo connection post includes a blog URL (`/blog/your-ai-team-works-from-your-actual-codebase/`) that must exist before posting. Confirm whether this blog post was published to production.

---

## 2. Keyword Alignment Analysis

### Pillar 1: Category Definition

| Piece | Primary Keyword | Status |
|-------|-----------------|--------|
| What Is Company-as-a-Service? | "company as a service" | **PUBLISHED** — SAP 5.0/5.0. No competitor has published on this term. Window remains open. |

**Remaining gap:** "One-Person Billion-Dollar Company" article (Month 2) not started. "Autopilot vs. Decision-Maker: Two Models for AI Company Operation" (Month 2) not started.

### Pillar 2: Methodology

| Piece | Primary Keyword | Status |
|-------|-----------------|--------|
| Why Most Agentic Engineering Tools Plateau | "agentic engineering" | **PUBLISHED** — SAP 4.8/5.0 |
| Vibe Coding vs Agentic Engineering | "vibe coding vs agentic engineering" | **PUBLISHED** 2026-03-24 — indexed status unknown, no analytics yet |
| How We Used AI-Generated Personas... | methodology, interview research | Calendar Week 1 (Mar 27–Apr 2) — status unknown |

**New coverage:** Repo connection feature partially addresses Gap 4 (Engineering-in-Context). Blog post referenced in distribution content at `/blog/your-ai-team-works-from-your-actual-codebase/` and technical deep-dive at `/blog/credential-helper-isolation-sandboxed-environments/`. Confirm published status.

**Remaining gap:** "Knowledge Compounding in AI Development" (Gap 1) still missing. Tanka claims "memory compounding" as moat. This is the highest-risk unaddressed narrative gap.

### Pillar 3: Competitive Positioning

| Piece | Primary Keyword | Status |
|-------|-----------------|--------|
| Soleur vs. Anthropic Cowork | "soleur vs cowork" | **PUBLISHED** 2026-03-16 |
| Soleur vs. Cursor (2026) | "soleur vs cursor" | **PUBLISHED** 2026-03-19 |
| Soleur vs. Notion Custom Agents | "soleur vs notion ai" | **PUBLISHED** 2026-03-17 |
| Soleur vs. Polsia | "soleur vs polsia" | **PUBLISHED** 2026-03-26 — completes P1 gap |

**Progress:** All four P1 comparison pages are now live. Soleur has comprehensive coverage of the primary competitor set.

**Remaining gaps:**

- "Soleur vs. Paperclip" (P2) — Paperclip at 14.6k GitHub stars. Complementary positioning. Not started.
- "Agent Platform vs. AI Organization" position paper (P2) — Not started.
- Notion comparison update needed before May 3 (post-beta pricing start).

### Pillar 4: Proof and Tutorials

| Piece | Status |
|-------|--------|
| 5 case studies | **PUBLISHED** — FAQ sections added. Missing external citations for market-rate claims. |
| About/Founder page | **MISSING** — Gap 11. E-E-A-T blocker. 13 days since first flagged. |
| From Department Offices to Command Center | **NOT STARTED** — Gap 13. Scheduled Apr 3–6. |
| Repo connection blog post | Status unknown — referenced in distribution content |

---

## 3. Content Calendar Status (Week of 2026-03-25)

| Week | Task | Status | Notes |
|------|------|--------|-------|
| Mar 20–26 | P1 technical fixes: FAQ JSON-LD, Vision H1, dateModified | **Partial** | Case study FAQs done. "Plugin" in meta: unfixed 13 days. Vision H1: unconfirmed. |
| Mar 27–Apr 2 | "How We Used AI-Generated Personas" methodology article (issue #1176) | **Unknown** | No confirmation of draft or publication |
| Mar 27–Apr 2 | Distribute Vibe Coding vs Agentic Engineering | **Unknown** | Distribution content exists (2026-03-24). Confirm whether it was posted |
| Apr 3–6 | "From Department Offices to Command Center" narrative (Gap 13) | **Not started** | Upcoming |
| Apr 7–9 | "One Chat, 8 Departments" technical deep-dive (Gap 13) | **Not started** | Upcoming |
| Apr 10–13 | External citations on 5+ catalog pages (Gap 12) | **Not started** | Upcoming |

**Unplanned work shipped this week:** Two major features (PWA, repo connection) were built and distribution content drafted. These are not in the original calendar — they represent capacity used on reactive product content rather than planned content calendar items.

---

## 4. Distribution Gap Analysis

### High-Priority Undistributed Content

| Piece | Created | Channels Ready | Published to Channels |
|-------|---------|----------------|-----------------------|
| PWA Installability announcement | 2026-03-29 | 5 (Discord, X, Bluesky, LinkedIn ×2) | **No** |
| Repo Connection launch | 2026-03-29 | 8 (Discord, X, Bluesky, LinkedIn ×2, IndieHackers, Reddit, HN) | **No** |
| Vibe Coding vs Agentic Engineering social | 2026-03-24 | 4 (Discord, X, IndieHackers, HN) | **Unknown** |

**Assessment:** The repo connection distribution piece includes a HN "Show HN" post and Reddit writeup — the two highest-ROI channels for developer tool launches — both ready to publish. This is the most immediately actionable organic discovery opportunity in the entire audit history.

### Channel Coverage Gaps

| Channel | Last Activity | Gap |
|---------|---------------|-----|
| Hacker News | Not tracked | Repo connection HN post ready to submit |
| Reddit | Not tracked | Repo connection Reddit writeup ready |
| IndieHackers | Not tracked | Repo connection + Vibe Coding posts ready |
| Product Hunt | Never | Zero launches detected — highest-ROI single action for backlink generation |

---

## 5. Brand Compliance Issues

| Priority | Issue | Status | Days Unfixed |
|----------|-------|--------|-------------|
| **CRITICAL** | Homepage meta description: "A Claude Code plugin..." | Unfixed | **13 days** (flagged 2026-03-17, 2026-03-23, 2026-03-25, now 2026-03-30) |
| **CRITICAL** | Getting Started meta: "Install the Soleur Claude Code plugin..." | Unfixed | **13 days** |
| HIGH | Brand guide agent count: "61 agents, 59 skills" vs. site showing "63 AI Agents" | Unfixed | Unknown |
| MEDIUM | PWA distribution content uses "61 agents" (same stale count) | In draft | Pre-publication — fix before publishing |
| MEDIUM | Repo connection distribution content uses "61 agents" across multiple channels | In draft | Pre-publication — fix before publishing |

**Recommendation:** Before publishing any March 29 distribution content, update the agent count to the current value shown on the site (63 agents). All five channel posts in the PWA announcement and all eight posts in the repo connection announcement reference "61 agents" — publishing with this stale count creates a discrepancy visible to anyone who visits the site after clicking through.

---

## 6. Organic Discovery Gap

**Current state:** ~1 organic visitor/week from Google (from Week 2 analytics). No new analytics data since 2026-03-23.

### Off-Page Situation (Unchanged)

1. **Zero backlinks** — No third-party sites link to soleur.ai. This has been the case since the first audit.
2. **Zero listicle presence** — Soleur appears on no external lists.
3. **Zero Product Hunt launches** — No launch detected across any audit.
4. **Meta tags in production** — P0 bug flagged in 2026-03-23 SEO audit (OG tags absent in fetched HTML). Status: unresolved in this audit's scope.

### New Distribution Opportunities (This Week)

The repo connection launch is the highest-quality distribution event since the CaaS article. The HN "Show HN" writeup is technically substantive (credential helper isolation, GitHub App token architecture, shallow clone + merge strategy) — exactly what HN rewards. This should be submitted before the technical details age.

| Action | Channel | Estimated Impact | Effort |
|--------|---------|-----------------|--------|
| Submit "Show HN: Git credential helper isolation for sandboxed AI agents" | Hacker News | 50–500 visitors if front page; 3–20 backlinks | 5 min |
| Post repo connection on Reddit (r/selfhosted, r/MachineLearning, r/SideProject) | Reddit | 20–200 visitors | 10 min |
| Post both pieces to IndieHackers | IndieHackers | 20–100 visitors + community feedback | 10 min |
| Product Hunt launch (separate planning required) | Product Hunt | 500–2,000 visitors; 50–200 backlinks | 4–8 hrs |

---

## 7. Content Gap Tracker Update

| Gap | Status | Change Since 2026-03-25 |
|-----|--------|--------------------------|
| Gap 1: Knowledge Compounding Narrative | Open | No change |
| Gap 2: CaaS Category Definition | COMPLETED | No change |
| Gap 3: Agent Platform vs AI Organization position paper | Partial | No change |
| Gap 4: Engineering-in-Context Value Prop | Partial | **Repo connection blog post + tech deep-dive drafted (2026-03-29)** |
| Gap 5: Autopilot vs. Decision-Maker / Polsia | Partial | **Soleur vs. Polsia comparison PUBLISHED (2026-03-26)** |
| Gap 6: Cursor Positioning | COMPLETED | No change |
| Gap 7: Cowork + Microsoft | Partial | No change |
| Gap 8: Paperclip | Open | No change |
| Gap 9: Price Justification | Open | No change |
| Gap 10: Listicle Presence | Open | No change |
| Gap 11: About/Founder Page | Open | **Overdue — was Month 1 item** |
| Gap 12: External Citations on Non-Blog Pages | Open | Scheduled Apr 14–20 |
| Gap 13: Command Center Launch Narrative | Open | Blog posts not started; distribution content for PWA + repo drafted |

---

## 8. AEO Score Projection

| Metric | 2026-03-17 | 2026-03-23 | 2026-03-25 (est.) | 2026-03-30 (est.) |
|--------|:----------:|:----------:|:-----------------:|:-----------------:|
| AEO Score | 68/100 | 74/100 | 74–76/100 | **76–78/100** |
| Blog SAP avg | ~4.5 | 4.7 | ~4.8 | ~4.8 |
| Non-blog SAP avg | ~2.0 | 2.8 | 2.8 | 2.8 (no changes) |
| Pages with external citations | ~6 | ~8 | ~8 | ~8 (no new pages) |
| Pages with FAQ JSON-LD | 3 | 8 | ~8 | ~9 (Soleur vs. Polsia adds 1) |

Reaching 80+ requires completing Gap 12 (external citations on catalog pages, scheduled Apr 14–20) and adding FAQ sections to Vision and Skills pages.

---

## 9. Priority Action Items — Week of 2026-03-30

| Priority | Action | Impact | Effort |
|----------|--------|--------|--------|
| **P0** | Fix "plugin" in homepage and Getting Started meta descriptions — 13 days unfixed across 4 audits | CRITICAL — brand compliance + highest-impression text | 30 min |
| **P0** | Update agent count to 63 in all March 29 distribution content before publishing | CRITICAL — prevents count discrepancy across all channels | 15 min |
| **P1** | Publish repo connection distribution content (8 channels) — HN "Show HN" post especially | HIGH — technically substantive HN post; IndieHackers + Reddit posts ready | 30 min |
| **P1** | Publish PWA installability distribution content (5 channels) | HIGH — major product milestone undistributed | 20 min |
| **P1** | Update brand guide agent count from 61 to 63 | HIGH — brand guide is the source of truth; site is correct, guide is stale | 15 min |
| **P1** | Confirm blog post `/blog/your-ai-team-works-from-your-actual-codebase/` is live before posting distribution content | CRITICAL for correctness | 5 min |
| **P1** | Confirm "Vibe Coding vs Agentic Engineering" distribution was posted to Discord, X, IndieHackers, HN | MEDIUM — ensure the highest-scored Month 1 article was actually distributed | 10 min |
| **P2** | Write "From Department Offices to Command Center" blog post (Gap 13, scheduled Apr 3–6) | HIGH — hero content for command center launch; social distribution target | 6–8 hrs |
| **P2** | Begin About/Founder page (Gap 11) — overdue from Month 1 | HIGH — E-E-A-T blocker affecting all content authority | 2–3 hrs |
| **P3** | Add external citations to Agents, Skills, Vision, Getting Started pages (Gap 12) | HIGH AEO impact once scheduled week arrives | 4–6 hrs |

---

_Generated: 2026-03-30. Sources: analytics/2026-03-23-weekly-analytics.md, analytics/trend-summary.md, audits/soleur-ai/2026-03-25-growth-audit.md, audits/soleur-ai/2026-03-25-content-audit.md, content-strategy.md (2026-03-29), brand-guide.md (2026-03-26), seo-refresh-queue.md (2026-03-20), distribution-content/2026-03-29-pwa-installability-milestone.md, distribution-content/2026-03-29-repo-connection-launch.md._
