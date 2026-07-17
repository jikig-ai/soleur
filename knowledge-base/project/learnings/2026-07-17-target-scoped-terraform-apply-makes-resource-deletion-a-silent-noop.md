---
title: A -target=-scoped terraform apply makes resource DELETION a silent no-op
date: 2026-07-17
category: infrastructure
module: apps/web-platform/infra/sentry
tags: [terraform, iac, sentry, vendor-cost, drift, delete-path, observability]
issue: 6589
pr: 6582
---

# Learning: a `-target=`-scoped terraform apply makes deletion a silent no-op

## Problem

A Sentry budget alert said cron + uptime monitors had consumed **$42.22 / $50.00 (84%)**
of the monthly PAYG budget, and suggested increasing *reserved volume* or the *budget*.
The framing invited a cost question. The real finding was a broken delete path.

## Root Cause

`apply-sentry-infra.yml:196+` runs `terraform plan` scoped to a **hand-maintained
`-target=` allowlist**. Terraform only touches resources it is targeted at — so **removing
a resource block from `cron-monitors.tf` never destroys the live resource.**

Traced end-to-end:

- PR **#6034** (`774c9007e`, 2026-07-05) added `sentry_cron_monitor.scheduled_ghcr_token_minter`
  → Terraform created it live.
- PR **#6074** (`0323ac43c`, same day) removed the block. Its replacement comment reads
  verbatim: *"the scheduled-ghcr-token-minter monitor was REMOVED"*.
- **It was not.** The monitor is live today, billing $0.78/mo, carrying an **unresolved
  incident for 12 days** about a cron that was deliberately retired.

Deleting a Sentry IaC resource actually requires **three** steps:

1. Remove the resource block, **and**
2. **Keep** (or re-add) its `-target=` line so the plan can see it, **and**
3. Put `[ack-destroy]` on its own line in the merge commit.

#6074 did step 1 only — which is what every author intuitively believes is sufficient.

The leak class was **already documented in the workflow's own comment** and has fired at
least twice:

> `kb_tenant_mint_silent_fallback` is deliberately ABSENT from the -target list below.
> The resource left issue-alerts.tf in #4929 (superseded by kb_db_error) but was never
> destroy-applied, so an orphan remains in STATE and the live Sentry rule is inert.
> — `apply-sentry-infra.yml:186-192`

**The guard designed to prevent accidental destruction made intentional destruction
silently impossible.**

## Key Insight

**A monotonically-increasing resource count is evidence the DELETE PATH is broken — not
that nobody deletes.**

Sentry monitors went **8 (2026-05-15) → 49 (2026-07-17)**, never once decreasing across
~60 commits. The intuitive reading ("we accrete monitors and nobody cleans up") is a
*people/discipline* story and it is wrong. The true reading was *mechanical*: down was
unreachable.

The probe that surfaced it is cheap and general:

```bash
for c in $(git log --format=%H --follow -- <iac-file> | tac); do
  echo "$(git show -s --format=%cd --date=short "$c")  $(git show "$c":<iac-file> | grep -cE '^resource ')"
done | uniq -f1
```

**Generalizes:** when a count only ever goes up, check whether "down" is even *reachable*
before concluding it is a hygiene problem. Ask "what happens when someone deletes one?"
and verify the answer against the pipeline, not against the author's comment.

## Secondary Findings

### A vendor's own suggested remedy may not exist

The alert said *"consider increasing your Reserved volume for cron monitors and uptime
monitors."* There **is no purchasable reserved volume for monitors**
([getsentry/sentry#73359](https://github.com/getsentry/sentry/issues/73359), closed
unshipped). Every plan includes exactly **1 free cron + 1 free uptime**; all others are
PAYG-only at $0.78/$1.00. Two of the four options the operator asked to compare (reserved
volume; migrate to Better Stack) did not survive verification. **Verify vendor-suggested
remedies against live pricing docs before scoping them as options.**

### Exact-arithmetic reconciliation confirms a pricing model in seconds

`49 × $0.78 + 4 × $1.00 = $42.22` matched the alert **to the cent**, confirming both the
per-unit rates *and* the billable-count model (reserved = 1) before any API call. Later
independently confirmed three ways (ledger row, prior learning, live docs). When a bill
and a countable resource set are both visible, try the arithmetic first — a to-the-cent
match is near-conclusive and costs nothing.

### "84% of budget with 30 days left" is not necessarily a burn

It was a **fixed per-monitor monthly seat charge**, already fully booked; time could not
consume it. But the cliff was real and **mis-located**: it fires at **renewal** and is
**all-or-nothing** — *"All monitors are automatically deactivated at the start of a new
billing period if there's not enough on-demand spend to cover all active monitors"*
([Sentry docs](https://docs.sentry.io/product/monitors-and-alerts/monitors/crons/troubleshooting/)).
Precedent: **#3958**, 7/8 monitors `status: disabled`, workflows fine, alerting dead.

Two consequences that invert the intuitive plan:
- **Pruning cannot avert it** — a monitor active at any point in a period bills for that
  period; there is no in-cycle refund.
- **Raising the cap costs $0** — PAYG bills usage, not the ceiling.

### A stale ledger row hid 2.5× cost growth

`expenses.md:37` recorded Sentry at `$40.00`, estimated at 40 monitors ("~$11 expected
PAYG… **verify actual draw on the 2026-06-17 invoice**" — a TODO never closed). Actual:
**$71.22/mo**. Sentry silently became the **largest product-COGS line (~29%)**. The model
error was assuming a generous "plan allotment" when reserved volume is **1**. An unclosed
"verify on the next invoice" TODO in a ledger note is a live liability.

### In-file rationale comments beat leader reasoning about that file

Two domain leaders disagreed on prune depth (CTO: drop ~33; CPO: drop 4). The CTO's list
was refuted **by the files' own comments**:
- `uptime-monitors.tf:78-85` — *"This monitor now guards redirect-HEALTH… **NOT a
  duplicate of soleur_apex**… The url stays www on purpose — that is the host under
  guard."* The proposed "apex covers www" drop would re-open the #4577 regression.
- `cron-monitors.tf:756-759` — the "12-monitor claude-eval cohort" drop conflated **4
  Tier-2 dormant** crons (confirmed via `deferIfTier2Cron` at `cron-campaign-calendar.ts:154`)
  with live workers.

When leaders disagree about a specific file, read that file's rationale comments before
averaging their opinions.

## Prevention

1. **Ship a live→IaC drift detector.** `sentry-monitor-iac-parity.test.ts:13-15` is
   explicitly *one-way (code → IaC)*; `sentry-monitors-audit.sh:274-281` orphan classes
   A/B/C are all monitor↔alert-rule joins. **Neither compares live↔IaC**, so an orphan is
   invisible forever. Tracked as FR5 in #6589.
2. **Fix the delete path** — replace the `-target=` allowlist with a full-root apply gated
   by `[ack-destroy]`, so removing a block destroys the resource. Tracked as FR3 in #6589.
3. **Test the delete path itself.** A test asserting "removing a resource block produces a
   `destroy` in the plan" would have failed at #6074 (AC3 in #6589). A pipeline whose
   delete path is never exercised will silently not have one.

## Session Errors

1. **I threaded an unverified capability claim into domain-leader prompts.** I hypothesized
   `scheduled_inngest_cron_watchdog` could serve as a cheap meta-detector replacing N
   per-cron monitors, and wrote it into the CTO prompt as a framing question. The CTO
   refuted it: #4682 retired it to a liveness-only beacon
   (`cron-inngest-cron-watchdog.ts:281-300`); the 49 monitors **are** the missed-run layer.
   Cost: one leader round premised on a retired capability.
   **Prevention:** `hr-verify-repo-capability-claim-before-assert` already covers this and
   brainstorm SKILL.md already mandates grepping cited symbols before leader spawn — this
   was a compliance miss, not a missing rule. Grep the symbol *before* threading a
   "cheaper alternative" hypothesis into a prompt; a hypothesis in a prompt is an
   assertion to the subagent.

2. **Subagent false-negative reading Sentry's monitor list endpoint.** The research agent
   initially reported "50 monitors have never checked in" from `lastCheckIn: null`.
   `lastCheckIn` **is not a field on the list endpoint**; real liveness lives in
   `environments[].lastCheckIn`. True never-checked-in count: **2**. The agent
   self-corrected and flagged it.
   **Prevention:** captured as **TR3** in `specs/feat-sentry-monitor-spend/spec.md` so the
   Class D implementation cannot repeat it. When a field reads uniformly null across every
   record, suspect the field does not exist rather than that every record is empty.

3. **Roadmap drift detected and not reconciled.** `roadmap-reconcile.sh validate` reported
   `STALE_STATUS|phase 4|roadmap=43o/160c|milestone=57o/169c`.
   **Prevention:** none needed — the tool's prescribed fix is the roadmap-review cron,
   which opens its own reviewed PR. Phase-4 counts do not bear on vendor-spend analysis.
   Flagged rather than silently skipped. One-off.

4. **Foreground `sleep` blocked by guardrails** while waiting for background agents.
   **Prevention:** use `Monitor` with an until-loop or `run_in_background`, not a
   foreground sleep. One-off; corrected immediately.

5. **ToolSearch mis-selection** — loaded `TaskList`/`TaskGet` expecting background-agent
   status; those tools drive the todo system.
   **Prevention:** background agents notify on completion; there is no status-poll tool to
   fetch. One-off; no cost.

## Related

- Issue: #6589 (this work) · Deferred: #6590 (deep prune / ADR-031 amendment), #6591 (monitor-value telemetry)
- Brainstorm: `knowledge-base/project/brainstorms/2026-07-17-sentry-monitor-spend-brainstorm.md`
- Prior art: `knowledge-base/project/learnings/2026-05-15-sentry-iac-billing-and-quirks.md` (§Gotcha 3 — per-seat billing)
- Precedent incident: #3958 (7/8 monitors disabled at PAYG exhaustion)
- Governing ADR: `ADR-031-sentry-as-iac.md` (monitor-per-cron, deliberate)
- Adjacent decision: #4296 (60-day observability re-decide, 2026-07-21)
</content>
