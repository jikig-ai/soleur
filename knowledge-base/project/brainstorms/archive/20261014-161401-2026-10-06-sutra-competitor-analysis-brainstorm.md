---
date: 2026-10-06
topic: sutra-competitor-analysis
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Sutra vs Soleur: competitor entry and improvement backlog

## What We're Building

1. A **Tier 3 watch entry** for Sutra (`sankalpasawa/sutra`, Asawa Inc) in `knowledge-base/product/competitive-intelligence.md` (Overlap Matrix row, New Entrants #12, targeted-addition note). Done in this PR.
2. A **ranked backlog of Soleur improvements** drawn from Sutra's product and website UX. Each top item is filed as its own GitHub issue. No site or product change ships in this PR.

Sources (retrieved 2026-10-06; repo HEAD `37264736677f1ff555862ba29ea56762288ec06a`): the Sutra [site](https://sankalpasawa.github.io/sutra/) plus its `how-sutra-works` and `way` pages, and the [repo](https://github.com/sankalpasawa/sutra) (`README`, `VISION`, `CLARITY`, `CATALOG`, `PRODUCT-VISION`, `marketplace.json`, `sutra-ui` README, `hooks/` listing). Not read: `os/native`, the plugin's own hooks, the desktop app source.

Note on the cited URL: `index.html#canon` has no matching anchor. The footer "the canon" link goes to the repo's `os/native` folder.

## What Sutra is (observed)

| Surface | Observation |
|---|---|
| Product | Free macOS desktop app (Windows x64 preview) that drives the user's local `claude` CLI. UI shows departments with a lead and specialists working in parallel from one brief, with live status and a user-set acceptance check that stops failing work. |
| Plugin | Claude Code plugin `core` via marketplace, `curl \| bash` installer, hooks for per-turn routing, depth and blueprint gates. |
| Positioning | "Use AI, your work gets faster. Manage AI, you get better." / "Speed is fine. Everyone has it. Velocity is speed with a direction." Free, private, "yours". |
| Self-assessment (`CLARITY.md`) | ICP OPEN, pricing not set, revenue is client services, "content, integration, curation, not capability moat", Claude Code absorption risk PARTIAL. |
| Traction | 1 star, 0 forks, 11 contributors, created 2026-04-03, no license detected. Daily-ish desktop releases (not a traction signal). |

## Why This Approach

- **Tier 3 watch entry, internal-only.** CPO: "competitor" is the wrong frame. Conceptual overlap is high (departments, parallel specialists, compounding feedback), market threat is low (no ICP, no pricing, macOS-only, 1 star). Same class as the Omnigent and Openship watch entries; Multica-style donor treatment applies to specific mechanics.
- **No public comparison page.** CLO: naming a 1-star project in public copy carries Art. 4(c) verifiability risk and adds little SEO value. NG5 (non-affiliation disclaimer, #6837) is still open for any public comparison.
- **Ideas only.** No license means all rights reserved. No verbatim prose, prompts, code or structure; no vendoring; no `NOTICE` entry or "Inspired by" header in the plugin payload, which would imply a license that does not exist.

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| Tier / depth | Tier 3, watch entry | CPO |
| Public exposure | Internal-only, no compare page | CLO |
| Borrowing | Ideas only; claims tagged observed vs inferred | CLO |
| Improvements deliverable | Record + file one issue per top item; no site change in this PR | Operator |
| Productize candidate | None. One-off entry; recurrence is already covered by the monthly competitive-analysis cron | Phase 2.5 |
| Visual design | Not triggered (no UI built here; the homepage demo is a follow-up issue and will need a wireframe there) | Phase 3.55 |

## Soleur improvement backlog (ranked)

Verified against Soleur's own source by repo research and the CMO (`plugins/soleur/docs/index.njk`, `_data/site.json`, `_data/stats.js`, pricing, getting-started and compare pages).

| # | Improvement | Evidence | Owner lens |
|---|---|---|---|
| 1 | **Homepage demo: one brief fanning out to departments with realistic live status** (include a "stopped" and a "waiting on you" state). Soleur's homepage has 8 static cards, a 6-step grid and 3 stat tiles, no demo. Also supports the human-in-the-loop claim. | Sutra's hero demo; Soleur homepage has none | CMO + CPO |
| 2 | **Founder-defined acceptance check**: let the founder state "what proves this is done" in the brief and have an agent run it before work counts as done. Soleur's `review`, `qa` and `compound` checks are engineer-defined. | Sutra "names the check that will prove the result" | CPO; HOW to CTO (extend the plan-phase acceptance field, do not build a new engine; ADR-229 already covers the workflow FSM) |
| 3 | **Surface "runs on your Claude plan / no meter" near the hero.** Today it is buried in the FAQ and pricing page. Must stay accurate: hosted users pay Soleur plus Claude. | Sutra hero line; Tier 0 metered-pricing shift | CMO (accuracy check with CLO) |
| 4 | **Visible privacy line on the waitlist form.** The privacy text is `sr-only`, so sighted visitors never see it. Add a short trust row; do not claim "private" for the hosted tier until the CLO confirms. | `index.njk` | CMO + CLO |
| 5 | **Waitlist as the primary CTA is high friction for a product with a free self-host path.** Test promoting self-host install to primary and keeping the waitlist for hosted. | `index.njk` CTAs | CMO |
| 6 | **Fix stale and inconsistent figures**: hero and FAQ hardcode "60+ agents" while `stats.js` computes 67; `statsLastVerified` is 2026-04-22; the Dario Amodei attribution has no source beyond the Inc.com link and needs the fact-checker before reuse. | CMO source read | CMO + fact-checker |
| 7 | **"How it works" page with one worked example** (Sutra's six-layer page walks a single request through every layer). Soleur has no dedicated page. | Sutra `how-sutra-works.html` | CMO |
| 8 | **Community CTA on the homepage** (one Discord line after the FAQ). | Sutra ends on a community invite | CMO |
| 9 | **Hero link to the dedicated `/compare/` page** instead of the in-page anchor, and reframe as company vs coding tool. | `index.njk` | CMO |
| 10 | **Generated toggle ledger** of rules, hooks, skills and flags with their off-switches. Check against `flag-list` first to avoid duplication. | Sutra `CATALOG.md` Toggle column | CTO (small effort) |

Filed issues: #9577 (items 1, demo), #9578 (item 2, acceptance check), #9579 (items 3 to 6, 8, 9, homepage copy and trust fixes), #9580 (Anthropic terms check). Items 7 (how-it-works page) and 10 (toggle ledger) stay in this backlog until the CPO and CTO want them filed.

Parked for later: a hard-gate Stop hook for the few rules agents routinely violate (CTO, medium value; precedents ADR-157 and ADR-162); a parallel-department live view in the web platform (CPO: check what the Command Center already shows before filing).

Do not copy: Sutra's near-zero social proof (Soleur's quote and Inc.com strip are its trust assets), single-CTA purity (Soleur has two tiers), an unqualified "Free" (hosted plans start at $49/month), its paper palette (Soleur's dark gold identity is deliberate), per-turn routing hooks, the six-layer "OS" framing, `bypassPermissions` as a default, `npx -y` at spawn, and "nothing leaves your computer" as a blanket claim.

## User-Brand Impact

- **Artifact:** the Sutra row in `knowledge-base/product/competitive-intelligence.md` and the follow-up issues that quote it.
- **Vector:** an unverified or disparaging claim about a named third party reaching a published surface, or lifted unlicensed expression entering the plugin payload.
- **Threshold:** single-user incident.

Mitigations: every Sutra claim is tagged `[observed]` or `[inferred]` with a retrieval date and HEAD SHA; no ARR, user or intent claims; no public page; ideas-only.

## Open Questions

- **Anthropic terms (follow-up issue).** Sutra's "bills as your Claude subscription" pattern. CLO flags exposure only if Soleur ever authenticates customer or tenant runs with a user's own subscription (trigger in `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`). Re-fetch live Consumer Terms before any product work; do not copy the pattern meanwhile.
- **Does the Command Center already show parallel department status?** Check before filing the live-view item.
- **Dario Amodei attribution on the homepage** needs fact-checker verification (item 6).
- **Cascade (out of scope here).** `business-validation.md` is 78+ days past its review date; this targeted addition does not refresh it.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Watch entry in Tier 3. High conceptual overlap, low market threat. Lessons: founder-defined acceptance check, parallel-department visibility, local/no-meter positioning. Re-open on license, stated ICP/pricing, >500 stars, or Anthropic shipping a department UI.

### Marketing

**Summary:** Sutra wins on hero specificity and demo-as-proof; Soleur wins on credibility signals and funnel depth. Copy the concrete hero and demo, not the structure. Soleur-side defects found: sr-only privacy text, stale "60+ agents", unverified quote attribution.

### Engineering

**Summary:** Toggle ledger and a plan-phase acceptance field are worth adopting; a desktop wrapper conflicts with the PWA-first and BYOK ADRs and is low priority. Sutra defaults `bypassPermissions` and runs `npx -y` at spawn, both anti-patterns. `per-turn-hard-gate.sh` and `flow-stop-check.sh` were not located at the repo root and were not verified.

### Legal

**Summary:** Internal-only, tagged claims, ideas-only. Attribution does not cure missing permission, so no `NOTICE` or "Inspired by" header. Follow-up to verify live Anthropic terms.

## Capability Gaps

None reported by leaders.

## Session Errors

- The initial WebFetch summary of the Sutra homepage was model-condensed; the raw HTML was re-read for exact copy. The `#canon` anchor from the request does not exist on the page.
- The CTO could not find `per-turn-hard-gate.sh` and `flow-stop-check.sh` at the repo root; they are likely under `marketplace/plugin/` and remain unverified.
