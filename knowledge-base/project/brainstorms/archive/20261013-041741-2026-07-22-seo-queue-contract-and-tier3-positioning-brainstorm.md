---
date: 2026-07-22
topic: seo-refresh-queue producer/consumer contract + Tier-3 positioning substantiation
issue: 6827
branch: feat-6827-seo-queue-consumer-tier3-positioning
pr: 6830
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# SEO Refresh Queue Contract + Tier-3 Positioning Substantiation

Brainstorm for issue #6827, a `deferred-scope-out` tracker bundling three follow-ups to the
comparison-page figure correction merged 2026-07-20.

## What We're Building

The issue asked for three things. Premise verification falsified or materially re-shaped all
three, and surfaced a fourth defect the issue does not mention. The agreed scope is:

1. **Correct the paperclip distribution twin** and sweep every `distribution-content/` file
   against its `plugins/soleur/docs/blog/` twin for figure drift.
2. **Fix the queue's producer/consumer contract** (Bug A + Bug B below) with two prompt edits
   made in lockstep.
3. **Add an artifact-delta observability signal** so a silently non-draining queue self-reports.
4. **Bind the existing substantiation rule** to the diffs that currently bypass it.
5. **Annotate `competitive-intelligence.md` takeaway #7** to separate verified from
   unsubstantiated Cofounder convergence claims.

Explicitly **not** in scope this cycle: the `soleur-vs-cofounder` page, and the Tier-3
positioning rewrite on published pages.

## Why This Approach

The issue's framing — *"the undrained queue is the root cause; give the queue a consumer"* — is
wrong in a specific and load-bearing way. The queue has **two** consumers. It does not drain
because the producer and consumer disagree about where rows live and what "needs work" means.

### Bug A — section mismatch (CONFIRMED)

The producer `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts:166`
appends dated `## Stale Comparison Pages Flagged for Regeneration (YYYY-MM-DD)` blocks, which
land at `knowledge-base/marketing/seo-refresh-queue.md:201` and `:219` — *below*
`## Refresh Schedule` (`:191`).

The consumer `apps/web-platform/server/inngest/functions/cron-content-generator.ts:103` reads
only "Priority 1 first, then Priority 2 pillar, then Priority 2 comparison" (§1.x / §2.2 / §2.1).

Every flagged-stale row is structurally unreachable by the only cron that acts on the queue.

### Bug B — predicate mismatch (CONFIRMED, worse than the issue implies)

The consumer selects "the highest-priority item **without** a `generated_date` annotation".
Sections §1.1–§1.7 (`:25`–`:90`) are prose subsections with no `generated_date` field at all,
and they are ordered *first*. A literal read makes §1.1 Homepage eligible on every fire,
forever.

The pipeline is **mis-targeted, not stalled**. "Stale" (what the queue tracks) and "never
generated" (what the cron acts on) are different predicates, and a published-but-stale page
always has a `generated_date`, so it can never be re-selected.

### Bug C — dark producer, live consumer (CONFIRMED, with a correction)

Per `knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md:151-153`:
`cron-competitive-analysis` last self-authored 2026-04-21 (~90d, 3 missed monthly fires) and
`cron-growth-execution` 2026-04-01 (~110d). The 2026-06-08 flagged block came from a **human**
PR (#5039, commit `8313d7610`), not the cascade.

**Correction to an assertion made mid-session:** `cron-content-generator` is *not* dark. It
fires twice weekly and #6818 (`[Scheduled] Content Generator - 2026-07-21`) is open. The
producer is dark; the consumer is live. This is why fixing Bug A + Bug B changes observed
behavior immediately.

Dark-producer remediation is already tracked by **#4375** (open, `action-required`, since
2026-05-24). Nothing new is filed for it.

### The fourth defect — an incomplete correction

`knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md` carries
`status: published`, `channels: discord, x, bluesky, linkedin-company`, and says
**"14.6k GitHub stars" in six places** (`:13`, `:25`, `:45`, `:76`, `:98`, `:136`). Its blog
twin `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md:15,17` was corrected on
2026-07-20 to "74,000+". The true count is 74,282 — the stale figure is off by roughly 5x.

The 2026-07-20 correction swept one write-site. This is the failure mode
`hr-write-boundary-sentinel-sweep-all-write-sites` exists to prevent, and it is the same defect
class #6827 was filed to follow up on.

**Severity, stated precisely.** `distribution-content/` is *not* compiled by Eleventy
(`eleventy.config.js:3` sets `INPUT = "plugins/soleur/docs"`), so this copy was never live on
soleur.ai. It is read by `cron-content-publisher.ts` and, being `status: published`, already
went out to social channels with the wrong figure. `status: published` files are not re-sent,
so the remaining exposure is record accuracy and reuse — not a live-page incident. An earlier
characterization of this as "live, shipped, wrong copy" overstated it and is corrected here.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Fix live copy + close the contract gap; defer content drain | Operator selection. Fixes the mechanism that produced both the 2026-07-20 correction and its residue. |
| 2 | Reject "one GitHub issue per flagged page" | Relocates a write-mostly backlog into an `action-required` queue already 28 deep (audit `:261-264`), against ~880 open `Post-MVP / Later` items. CPO and CTO independently concurred. |
| 3 | Reject the `product-roadmap validate` bolt-on | `roadmap-reconcile.sh` is a read-only roadmap↔milestone reconciler with a fixed verdict vocabulary (`STALE_STATUS`/`MISSING_ISSUE`/`EMPTY_MILESTONE`). An SEO-queue check shares no input, verdict, or remediation route. Scope creep into an unrelated skill. |
| 4 | Fix Bug A + Bug B as two prompt edits in lockstep | Both prompts are verbatim-mirrored from `.github/workflows/*.yml` and anchor-tested (`cron-content-generator.test.ts:79`, `cron-competitive-analysis.test.ts:148`). Editing one side breaks the parity test. |
| 5 | Consumer predicate becomes **positive** | Change from "absence of `generated_date`" to "Status contains `Stale`/`Create` **and** no `generated_date`". Absence-of-a-field-most-rows-lack is what makes §1.1 permanently eligible. |
| 6 | Observability must be an **artifact-delta** signal | `cron-content-generator.ts:200,232,277` posts a Sentry heartbeat gated on *issue existence*, so it is GREEN at zero rows drained. Signal must key on queue-row `generated_date` count changing. Cites `hr-observability-as-plan-quality-gate`, `hr-no-dashboard-eyeball-pull-data-yourself`. |
| 7 | Do **not** publish `soleur-vs-cofounder` | Operator selection, CMO position. Zero existing search demand; publishing ranks their brand, borrows USV credibility, and documents that they neutralized three stated Soleur differentiators. CPO dissent recorded below. |
| 8 | Annotate takeaway #7; defer the page rewrite | Operator selection. Fixes the upstream source of truth first per `2026-03-12-competitive-analysis-cascade-data-reconciliation.md`, and prevents a thesis rewrite inheriting unverified claims. |
| 9 | Bind the existing substantiation rule rather than invent one | CLO: the rule already shipped 2026-07-20 in `knowledge-base/marketing/brand-guide.md` (Never-do list) and `plugins/soleur/skills/review/SKILL.md`. Neither is mechanically enforced, and `fact-checker` only runs via `content-writer` Phase 2.5 — so hand-edited blog refreshes bypass it. That is how the distribution twin survived. |
| 10 | Non-affiliation disclaimer is a prerequisite for any future competitor page | CLO found none on any comparison page or shared layout. Blocks the deferred Cofounder page, not this cycle's work. |

**Productize Candidate:** `distribution-twin-drift` check — assert every
`distribution-content/*.md` agrees with its `docs/blog/` twin on numeric competitor claims.
Recurring by construction (every comparison-page correction creates the same twin-drift risk).

## Open Questions

1. Should the canonical queue shape be the existing §2.1/§2.2 tables, or a single new
   machine-readable section both crons name? The plan should decide; the brainstorm's position
   is "reuse §2.1/§2.2" (smaller diff, no migration of historical blocks).
2. Does the fix need to backfill the two historical flagged blocks (2026-03-12, 2026-06-08)
   into the canonical section, or is forward-only acceptable? Forward-only leaves 7 rows
   permanently invisible.
3. `cron-growth-execution` reads "Priority 1 stale pages" (`:126`) — a third predicate. Does it
   need the same reconciliation, or is it out of scope given it is dark at ~110d?
4. CMO reports the Tier-3 thesis also appears in
   `plugins/soleur/docs/blog/2026-05-12-company-as-a-service-platform.md` (L58, L128, L172
   JSON-LD); repo-research surveyed only the 8 comparison pages and found "founder-in-the-loop"
   solely in the polsia and paperclip pages. Reconcile the exact page set at plan time before
   any rewrite.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** All three producer/queue/consumer layers are stale, so pipeline fixes buy nothing
until liveness is addressed; content ships independently of the pipeline, as the human PR that
drained Polsia and Paperclip demonstrates. Recommended cutting items 1 and 3 and shipping only
the Cofounder page. Note: the CPO's claim that `cron-content-generator` is dark was corrected
by CTO — the consumer is live, which is why the operator-selected pipeline fix does change
behavior immediately.

### Engineering

**Summary:** Confirmed Bug A and Bug C by direct file read; corrected Bug B's conclusion from
"nothing is eligible" to "the wrong things are permanently eligible" (§1.1 Homepage every
fire). Minimal correct fix is reconciling the producer's write target with a positive consumer
predicate; issue-fanout and the `product-roadmap` bolt-on are both rejected. Flagged that no
observability signal fires today — the heartbeat is issue-gated, not artifact-gated.

### Marketing

**Summary:** Ranked the 7 undrained rows: Notion (paywall/ICP-eviction) and Cursor (Composer
2.5, dead pricing table) are worth doing; NanoCorp, OpenAI Codex, Tanka, and CrewAI should be
closed won't-do. Recommended against publishing `soleur-vs-cofounder`. Drafted an honest
replacement contrast built on ownership and auditability rather than git mechanics, noting
`knowledge-base/product/business-validation.md` (L48, L141, L143) records that most interviewed
founders do not use Claude Code and want a browser UI — making "git-tracked + local-first" an
engineer's differentiator, not a buyer's.

### Legal

**Summary:** No outside-counsel threshold is met; none of the five thresholds in
`knowledge-base/legal/recommended-tools.md` match. The binding standard is EU 2006/114/EC
Art. 4 (objective, verifiable, material, non-denigrating, substantiation held *before*
publishing), which subsumes Lanham §43(a). Attribution defeats a falsity claim about Soleur's
own statement but not the Art. 4(c) verifiability bar for an unaudited self-report. Competitor
financial figures must not appear in JSON-LD unless the hedge travels in the same string.
Nominative fair use covers the Cofounder mark, but the no-sponsorship prong is unmet: there is
no non-affiliation disclaimer anywhere on the site.

## Capability Gaps

1. **No mechanical enforcement of the competitor-claim substantiation rule.** The rule exists in
   `knowledge-base/marketing/brand-guide.md` and `plugins/soleur/skills/review/SKILL.md` but has
   no test under `plugins/soleur/test/`. Evidence: CLO grep of both paths plus
   `plugins/soleur/agents/marketing/fact-checker.md`, which is invoked only from
   `content-writer` Phase 2.5. Domain: Legal + Engineering.
2. **No distribution-twin drift detection.** Evidence: `grep -rnE "[0-9,.]+k? (GitHub )?stars"`
   across `knowledge-base/marketing/distribution-content/` and `plugins/soleur/docs/blog/`
   returns a 5x disagreement on Paperclip's star count that survived a dedicated correction PR.
   Domain: Marketing + Engineering.
3. **No artifact-delta observability on queue drain.** Evidence: `cron-content-generator.ts:200,
   232,277` heartbeat is gated on the issue-based predicate; `_cron-shared.ts:578` shows the
   only Better Stack markers on this path are `SOLEUR_CLAUDE_COST*`. Domain: Engineering.
4. **No non-affiliation disclaimer on comparison pages or shared layouts.** Evidence: CLO search
   of comparison pages and `plugins/soleur/docs/_includes/`. Domain: Legal + Marketing.

## User-Brand Impact

- **Artifact:** the published Tier-3 comparison pages under `plugins/soleur/docs/blog/`, their
  social twins under `knowledge-base/marketing/distribution-content/`, and
  `knowledge-base/marketing/seo-refresh-queue.md` as their freshness producer.
- **Vector:** a stale, unattributed, or unsupportable factual claim about a named competitor
  reaching a published or distributed surface under Soleur's byline — the exact failure the
  2026-07-20 correction addressed, whose residue this cycle closes.
- **Threshold:** `single-user incident`.

## Session Errors

1. **Mid-session severity overstatement.** The paperclip distribution twin was characterized as
   "live, shipped, wrong copy". `distribution-content/` is never compiled by Eleventy, so the
   copy was never on soleur.ai. Corrected in-session before any artifact was written. The
   correct characterization is record-accuracy and reuse exposure plus already-sent social
   posts.
2. **Consumer/producer liveness inverted.** An initial read asserted `cron-content-generator`
   was dark; it fires twice weekly (#6818 open). The dark cron is the producer,
   `cron-competitive-analysis` (#4375). Corrected by CTO before scope was set.
3. **Roadmap drift left unreconciled.** `roadmap-reconcile.sh validate` reports
   `STALE_STATUS|phase 4|roadmap=43o/160c|milestone=56o/178c`. Not hand-edited: the script
   directs remediation through the `cron/roadmap-review` manual trigger, which opens a reviewed
   PR. Immaterial to this brainstorm's decisions; recorded so it is not lost.
