---
title: Content Plan — soleur.ai — 2026-11-23
date: 2026-11-23
type: content-plan
site: https://soleur.ai
---

# Content Plan — soleur.ai — 2026-11-23

Built from the three audits written in this cycle:

- [2026-11-23-content-audit.md](./2026-11-23-content-audit.md): 46 active (2 P0, 12 P1, 17 P2, 15 P3). 0 of 45 prior findings fixed. 2 new (C1, C2), 1 escalated (F14, P2 → P1), 1 closed unfixed (N7, replaced by C1).
- [2026-11-23-aeo-audit.md](./2026-11-23-aeo-audit.md): **75/100 (B+)**, unchanged (8-component: 79, unchanged). 0 of 21 tracked findings fixed. 1 new (N15).
- [2026-11-23-seo-audit.md](./2026-11-23-seo-audit.md): **78/100 (B)**, unchanged for the fifth cycle in a row. 0 of 17 tracked findings fixed.

## Scores and trend

| Audit | 10-26 | 11-02 | 11-09 | 11-16 | **11-23** | Change |
|---|---|---|---|---|---|---|
| AEO (SAP) | 76 (B+) | 74 (C) | 75 (B+) | 75 (B+) | **75 (B+)** | 0 |
| AEO (8-component) | 82 | 78 | 79 | 79 | **79** | 0 |
| Technical SEO | 78 (B) | 78 (B) | 78 (B) | 78 (B) | **78 (B)** | 0 |
| Content findings (P0/P1) | 33 (2/9) | 40 (2/9) | 48 (2/11) | 45 (2/11) | **46 (2/12)** | +1 |

**How to read this:**

- **Source-only again.** Cron containment refused WebFetch, WebSearch, `curl`, `git log` and the Eleventy build (#8467, #6088). No finding is confirmed against production; "unchanged" means the source still matches the prior evidence.
- **Nothing shipped in seven days.** No P0 has shipped in seven cycles. The only movement is calendar-driven: future-dated posts fell from 3 to 1.
- **AEO sits on the B+/C boundary.** Pages keep aging; if nothing ships, the AEO audit expects 74 (C) next week.

## Headline

**The retitle window for the trusting-AI-work series has closed; the series now needs a new founder hub post, and that post is also the best way to restart publishing after 12-03.**

## Part 1 — Findings mapped to issues (one issue per defect, per #8469)

### New this cycle

| # | Finding | Source | Priority | Issue |
|---|---|---|---|---|
| C1 | All 9 series titles are now fixed in developer register; the series has no founder search entry. Fix is a new hub post (R-17) + series box (R-18) | Content C1 | P1 | **#13020** (new; supersedes #11134) |
| F14↑ | 21 days without a new post; nothing after 12-03; 0 of 4 gap pieces | Content F14 | P1 (was P2) | #8466 |
| C2 | 7 legal pages list 4 supported tools (no OpenCode, no Antigravity CLI) — a fourth tool count | Content C2 | P2 | **#13021** (new, legal) |
| F12 | `/agents/` says each agent "is trained" (body, FAQ, JSON-LD) and "within Claude Code" | Content F12 | P2 | **#13022** (new; carried without an issue since 11-02) |
| N15 | `/ai-cmo/` shows 4+ CMO cost figures ($240K / $290K / $225,908 / $293,575 / $220,000) | AEO N15, SEO-15 | P2 | #9499 (widened) |

### Carried (status this cycle)

| # | Finding | Priority | Issue | Status |
|---|---|---|---|---|
| 1 | No date gate; 12-03 post live 10 days early and tops `/blog/`; 11-19 links forward to it | **P0** | #11132 | Open (1 post, was 3) |
| 2 | Developer register on `/` and `/pricing/`; hero test review 20 days overdue, revert trigger met | **P0** | #11133, #9588 | **Worse** (overdue) |
| 3 | Citation tracker never run (23 Mondays missed) | **P0** | #6084 | Open |
| 4 | No third-party Presence surface (flat 8 cycles) | **P0** | #5610, #2601 | Open |
| 5 | `/vision/` unshipped features in present tense | **P0** | #6376 | Open |
| 6 | Cron containment blocks build, WebFetch, `git log`, issue comments | **P0** (process) | #8467, #6088 | Open |
| 7 | Arc spokes cite no outside source (now 10 spokes) | P1 | #11135 | Open (scope widened) |
| 8 | FAQPage schema with no visible FAQ (5 posts; 11-04 empty heading) | P1 | #9101 | Open |
| 9 | Founder `Person` `sameAs` conflict | P1 | #9102 | Open |
| 10 | Supported-tool list: 6 / 5 / 4 / Claude-only | P1 | #11833 (+ #13021 legal) | Open |
| 11 | Compare pages + 2 pillars end on Claude-only install command | P1 | #12794 | Open |
| 12 | Getting-started "Two Commands", install-first landing | P1 | #9107, #2669 | Open |
| 13 | Blog index title/meta; founder posts under Engineering | P1 | #9104, #9105 | Open |
| 14 | Competitor revenue stated as fact | P1 | #7179 | Open |
| 15 | "9 hats" vs 8 departments; CaaS-led meta; `/skills/` title | P1 | #8462, #9112, #5601 | Open |
| 16 | CaaS pillar superlatives; September posts unsourced | P1 | #6085, #9108 | Open |
| 17 | Devin compare row / April 2025 framing | P2 | #12795 | Open |
| 18 | Antigravity post: Gemini names, meta, CTA order | P2 | #12459 (#11834 closed; residuals fold here) | Open |
| 19 | MVP post: no outside source, Gitleaks unnamed | P2 | #12460 | Open |
| 20 | "Nearly 700" vs "102" checks; vendor-lock-in overclaims | P2 | #11835, #11836 | Open |
| 21 | Arc hygiene: wrong series box (R-18), jargon, empty FAQ | P2 | #11136 | Open |
| 22 | Reused OG cards; generic `og:image:alt`; homepage `og:title` | P2 | #11137, #2557, #2674 | Open |
| 23 | Sitemap `lastmod` ignores `updated:`; 22 undated pages; freshness without fact review | P2 | #9106, #7180, #8468, #11138 | Open |
| 24 | `llms.txt` covers 9 of 77 URLs | P2 | #7181 | Open |
| 25 | Head-term cannibalisation; `pillars.js` routing | P2 | #8463, #8464 | Open |
| 26 | Accuracy copy: pricing "70%", "autopilot"; CaaS origin; `/agents/` superlative; model claims | P2 | #9111, #9501, #6378, #9500 | Open |
| 27 | `/community/` generic title + H1 | P2 | #6083 / #5618 / #6377 | Open (3 duplicates — consolidate per #8147) |
| 28 | Inc.com "As seen in" | P1 | #9103 | Absent from source; close after live check |

## Part 2 — Prioritised plan

### P0 — this week (before 12-03)

1. **Date gate (#11132), before 12-03.** `blog.11tydata.js` excluding `date > now` from `collections.blog`, feed and sitemap; daily `schedule:` on `deploy-docs.yml`; future-date check in `validate-seo.sh`; forward links only to published posts. After 12-03 there is no future post left, so the next future-dated merge will slip through unless the gate lands first. **SEO back to ~83.**
2. **Record the hero CTA decision on #9588, then ship R-1a–R-1f (#11133, #8462, #9112) in one PR.** Clears both homepage P0/P1 items and stops the revert trigger firing. 20 days overdue.
3. **Run the citation tracker once (#6084)** on Perplexity and Claude.ai with the 8 tracked queries. Only lever on Presence.
4. **`/vision/` roadmap cards in future tense (#6376).**
5. **Cron containment allowlist (#8467, #6088):** Eleventy build into `/tmp`, `validate-seo.sh`, read-only WebFetch to soleur.ai, `git log`, and `gh issue comment` (this run could not post evidence on existing issues).

### P1 — content (new pieces)

| Slot | Piece | Target query | Issue |
|---|---|---|---|
| First date after 12-03 | **"Can You Trust What Your AI Team Says It Finished?"** — series hub (R-17): visible FAQ, 2+ outside sources, links to every series post, waitlist CTA | can I trust AI output / how to check AI work | #13020, #8466 |
| Same PR | Series box `trusting-ai-work` in `_data/pillars.js` pointing at the hub (R-18) | — | #11136 |
| +2 weeks | "Contracts as a solo founder" (founder gap piece 1 of 4) | contracts without a lawyer | #8466 |
| +4 weeks | "AI marketing for a solo founder" (gap piece 2 of 4) | AI marketing solo founder | #8466 |

Cadence: 2 posts a month, each with `date:` equal to its merge date.

### P1 — repair PRs

| PR | Scope | Issues | Expected lift |
|---|---|---|---|
| **A. Single source of facts** | `_data/harnesses.js` rendered everywhere incl. FAQ/JSON-LD (getting-started FAQs first); legal wording via CLO; `/agents/` "trained"; scope "nearly 700" | #11833, #13021, #13022, #11835, #9500 | AEO Entity +1 |
| **B. Commercial-page CTAs** | R-11 waitlist + getting-started link on 4 pages; Devin row; attribute or drop Cursor revenue | #12794, #12795, #7179 | Conversion; Structure +1 |
| **C. Schema parity** | Visible FAQ on 5 schema-only posts (11-04 first); one founder `sameAs`; unique OG cards | #9101, #9102, #11137 | SEO +2 |
| **D. First-contact pages** | Getting-started R-3; blog hub R-4 + founder category; `/skills/` R-5 | #9107, #2669, #9104, #9105, #5601 | Structure +1 |

**Expected if P0 + A–C land:** AEO ~79–80 (B+), 81–83 with a tracker run. SEO ~87–88.

### P2 — trust and freshness (next 2–3 weeks)

- **Arc citations (#11135):** 1–2 primary sources per spoke (QuickCheck, Google Testing Blog, McKeeman 1998).
- **Post fact checks:** #12459, #12460, #9108.
- **Numbers:** `/ai-cmo/` one sourced figure (#9499); "70%" sourced or removed (#9111); CaaS origin line (#9501).
- **Freshness:** #11138, #7180, #8468, #9106; re-verify `statsLastVerified` (48 days old).
- **Social/AI metadata:** #2674, #2557, #7181.

### P3 — hold

New pillars, compare and use-case pages stay on hold until #8463 / #8464 resolve. Beta-checkpoint post with tester quotes (#2603) when consent is in hand.

**Content-writer checklist (carried, still not added):** "2+ outside sources"; "cross-page facts come from `_data/`"; "`date:` is the merge date"; "no terminal commands on commercial-intent pages".

## Part 3 — Keyword note

Keyword research is still the 2026-05-25 set (182 days old); WebSearch is blocked in cron. The top unclaimed founder query this cycle is "can I trust AI output", targeted by #13020. Rule until re-research: **the title names the founder's problem; the mechanism appears only in the body.**
