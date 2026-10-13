---
title: Sentry cron/uptime monitor spend — raise the cap, fix the delete path
date: 2026-07-17
issue: 6589
pr: 6582
branch: feat-sentry-monitor-spend
lane: cross-domain
brand_survival_threshold: single-user incident
status: decision-captured
---

# Sentry cron/uptime monitor spend

## What We're Building

Triggered by a Sentry budget alert (org `jikigai-eu`): cron + uptime monitors have
consumed **$42.22 of a $50.00/month pay-as-you-go budget (84%)**. The operator asked:
raise the budget, or optimize spend?

The investigation refuted three of the four premises in the question. The deliverable
is four things, in this order:

1. **Raise the PAYG cap $50 → $75.** Costs **$0** — PAYG bills usage, not the ceiling.
   This is the only action that removes the cliff.
2. **Correct `knowledge-base/operations/expenses.md:37`** — Sentry is recorded at
   `$40.00`; actual is **$71.22/mo** ($29 base + $42.22 PAYG). Understated by
   **$31.22/mo (~$375/yr)**.
3. **Destroy 4 dead monitors** (2 orphans + 2 never-checked-in) using the *correct*
   destroy procedure — **$3.34/mo**.
4. **Close the leak, both halves:** add live→IaC drift detection (Class D orphan) to
   `sentry-monitors-audit.sh`, **and** fix the `-target=` allowlist footgun in
   `apply-sentry-infra.yml` that makes resource deletion a silent no-op.

## Why This Approach

### The bill is fixed, not a burn — but the cliff is real and worse than the alert says

`49 × $0.78 + 4 × $1.00 = $42.22` **exactly**. Confirmed three independent ways: this
arithmetic, the ledger row (`expenses.md:37`, "~$0.78/monitor beyond plan allotment"),
and `knowledge-base/project/learnings/2026-05-15-sentry-iac-billing-and-quirks.md`
§Gotcha 3. It is a **fixed per-monitor monthly seat charge**, already fully booked for
the cycle. "84% with 30 days left" is not a trajectory — time cannot consume it. Only
*adding monitors* reaches $50.

The cliff is at **renewal**, and it is **all-or-nothing**:

> "All monitors are automatically deactivated at the start of a new billing period if
> there's not enough on-demand spend to cover all active monitors."
> — [Sentry crons troubleshooting](https://docs.sentry.io/product/monitors-and-alerts/monitors/crons/troubleshooting/)

The 10th new monitor ($50.02) silently kills **all 53**, not just itself. Headroom is
**9 monitors** and `cron-monitors.tf` was last modified **yesterday**.

This is precedented, not theoretical: **#3958** (CLOSED) recorded 7 of 8 monitors going
`status: disabled` with `400 {"status":["You don't have enough pay-as-you-go available
to create a new seat"]}`. Workflows kept running; only alerting died. **Silent blindness.**

**Pruning cannot avert it.** A monitor active at any point in a period bills for that
period — there is no in-cycle refund. Raising the cap is the only lever that works, and
it is free.

### Two of the four options the operator asked me to compare do not exist

| Option | Verdict |
|---|---|
| (a) Raise PAYG budget | **The answer.** Costs $0. Removes the all-or-nothing cliff. |
| (b) Buy reserved volume | **Does not exist.** No purchasable reserved volume for monitors ([getsentry/sentry#73359](https://github.com/getsentry/sentry/issues/73359), closed unshipped). Every plan includes exactly 1 free cron + 1 free uptime; all others are PAYG-only at $0.78/$1.00. There is no cheaper unit rate to buy. |
| (c) Prune to load-bearing set | **Marginal, and narrower than it looks.** ADR-031 deliberately chose monitor-per-cron to close real detection gaps. Defensible cut ≈ 4–8 monitors (~$3–6/mo). |
| (d) Move to Better Stack | **Costs more.** Better Stack free tier is a shared 10-unit pool at **6/10** used. Beyond it: **$2.00/heartbeat = 2.5× Sentry's $0.78**. Migrating 49 crons ≈ $100/mo vs $38.22. Sentry is the *cheap* venue. |

### The real finding: the IaC delete path is a silent no-op

Monitor count went **8 (2026-05-15) → 49 (2026-07-17)**, monotonically, **never once
decreasing**. That is not because nobody retires monitors — it is because **retiring one
does not work**.

Root cause, traced end-to-end:

- PR **#6034** (`774c9007e`, 2026-07-05) added `resource "sentry_cron_monitor"
  "scheduled_ghcr_token_minter"` → Terraform created it live.
- PR **#6074** (`0323ac43c`, same day) removed the resource block. Its replacement
  comment reads verbatim: *"the scheduled-ghcr-token-minter monitor was REMOVED"*.
- **It was not.** `apply-sentry-infra.yml:196+` runs `terraform plan` scoped to a
  hand-maintained `-target=` allowlist. Terraform never touches what it is not targeted
  at, so the resource was **orphaned, not destroyed**. It is live today, billing
  $0.78/mo, and has carried an **unresolved incident for 12 days** — alarming about a
  cron that was deliberately retired.

Deleting a Sentry resource actually requires **three** steps: remove the block, **keep**
the `-target=` line, and put `[ack-destroy]` in the merge commit. #6074 did only the first.

This leak class is **already documented in the workflow's own comment** and has fired at
least twice:

> `kb_tenant_mint_silent_fallback` is deliberately ABSENT from the -target list below.
> The resource left issue-alerts.tf in #4929 (superseded by kb_db_error) but was never
> destroy-applied, so an orphan remains in STATE and the live Sentry rule is inert.
> — `apply-sentry-infra.yml:186-192`

The safety mechanism designed to prevent accidental destruction has made **intentional
destruction silently impossible**. That is the durable bug; the $42 bill is just the
first instrument that read it.

### Nothing can currently detect this

- `sentry-monitor-iac-parity.test.ts:13-15` is **explicitly one-way**: *"Direction is
  one-way (code → IaC)"*.
- `sentry-monitors-audit.sh:274-281` orphan classes A/B/C are all *monitor↔alert-rule*
  joins. **None compares live↔IaC.**

So an orphan is invisible to every existing check, forever.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Raise PAYG cap $50 → $75 first, unconditionally.** | Costs $0 (usage-billed). Only lever that averts the all-or-nothing renewal blackout. Pruning yields no in-cycle refund, so it cannot substitute. COO + CFO + CPO converged. |
| 2 | **Correct `expenses.md:37` to $71.22.** | Ledger understates Sentry by $31.22/mo (~$375/yr). Required by `wg-record-recurring-vendor-expense-before-ready`. Sentry is now the **largest single product-COGS line (~29% of ~$247/mo)**. |
| 3 | **Reserved volume is NOT a lever — do not pursue.** | No purchasable reserved volume for monitors exists. $0.78/$1.00 PAYG are the only rates. Refutes the alert's own suggestion. |
| 4 | **Do NOT migrate crons to Better Stack.** | 2.5× the unit cost ($2.00 vs $0.78) and only ~4 free slots remain (6/10 pool used). The overlap thesis inverts. |
| 5 | **Narrow prune only: 2 orphans + 2 never-checked-in (~$3.34/mo).** | ADR-031 deliberately chose monitor-per-cron to close real single-user detection gaps. A deep prune reverses an accepted ADR. Dollars were never the case. |
| 6 | **`scheduled_github_app_drift_guard` MUST NOT be pruned at any cost tier.** | CLO: `article-30-register.md:303` cites it by name as an **"Art. 33 latency primitive"**. Silencing it collapses the Art. 33 awareness argument AND falsifies the register (Art. 5(2)). |
| 7 | **Ship BOTH the Class D detector and the `-target=` footgun fix in one PR.** | Operator decision. Detection alone leaves the footgun armed; the footgun fix alone leaves existing orphans unfound. |
| 8 | **The `-target=` allowlist is the disease, not the safety.** | It converts intentional destroys into silent no-ops. Replace with full-root apply gated by `[ack-destroy]`. |
| 9 | **Deep prune + ADR-031 amendment rejected for now.** | CTO proposed dropping ~33 monitors (~$26/mo); rejected — see Research Reconciliation. Re-open only if monitor spend exceeds burn-rate tolerance. |

## Research Reconciliation — where leaders disagreed

The **CTO** recommended pruning to ~16 crons + 3 uptime (~$26/mo saved). The **CPO**
found only **4** defensibly droppable. I sided with the CPO; the CTO's list has two
verifiable defects:

1. **Drop `soleur_www`** — refuted by the file's own comment. `uptime-monitors.tf:78-85`:
   *"This monitor now guards redirect-HEALTH… NOT a duplicate of soleur_apex… The url
   stays www on purpose — that is the host under guard."* Dropping it re-opens the #4577
   canonicalization regression.
2. **"Drop the 12-monitor CLAUDE-EVAL cohort"** — conflates the **4 Tier-2 dormant**
   crons (`cron-monitors.tf:756-759`, confirmed via `deferIfTier2Cron` at
   `cron-campaign-calendar.ts:154`) with live workers that do real work.

The CTO's central *framing* — "monitor only where silence is undetectable" — is sound
and is captured as a deferred ADR question, not actioned now.

**The CTO also refuted one of my own premises**, correctly: I hypothesised
`scheduled_inngest_cron_watchdog` could serve as a cheap meta-detector replacing N
monitors. It cannot — #4682 retired it to a liveness-only beacon
(`cron-inngest-cron-watchdog.ts:281-300`). The 49 monitors **are** the missed-run layer.

**A research agent's initial claim that all 50 monitors had never checked in was a
false negative** (`lastCheckIn` is not a field on the list endpoint; liveness lives in
`environments[].lastCheckIn`). Self-corrected. True never-checked-in count: **2**.

## Open Questions

1. **Does full-root apply surface latent state destroys?** `kb_tenant_mint_silent_fallback`
   is a known state orphan (`apply-sentry-infra.yml:186-192`). The first non-targeted plan
   will surface it and any siblings. Needs a reconciliation pass **before** the allowlist
   is removed — this is the main risk in Decision 7.
2. **Exact creation mechanism of the 5th uptime monitor** (`Uptime Monitoring for
   https://app.soleur.ai`, id `1422253`). Has no `environment` set, unlike the 4 IaC
   monitors — shape of a Sentry auto-detected monitor. Not traced to a PR.
3. **Does budget-deactivation inherit pause's alert-suppression?** Sentry's docs never
   confirm it. #3958 is our only evidence that disabled monitors silently drop check-ins.
4. **`scheduled-ux-audit` and `scheduled-architecture-diagram-sync` have never received a
   single check-in** despite being IaC-declared. Are their producers dead, or never wired?
   Destroying the monitor may be treating the symptom.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Refuted the "84% with 30 days left" deadline framing — it is a fixed
subscription, not a burn; headroom is 9 monitors. Confirmed **no** per-env/per-host
double-counting (all 53 `name` fields are static literals; live data shows 48 monitors ×
exactly 1 `production` environment). Confirmed **no blast radius**: no alert rule binds
`monitor_ids`, so deleting a monitor breaks no rule, dashboard, or cron. Recommended a
deep prune to ~16 crons — partially rejected (see Research Reconciliation).

### Finance (CFO)

**Summary:** The ledger understates Sentry by **$31.22/mo (~$375/yr)** — recorded $40.00,
actual $71.22. Recomputed true burn ≈ **$657/mo**, product COGS ≈ **$247/mo**; Sentry is
now the **largest single COGS line (~29%)**, and the monitor PAYG alone is **2.7× the
Hetzner CX33 it monitors**. Verdict: "$0.78/monitor is fine. Spending 2.7× your production
server on watching it is not." The dollars were never the case — prune for alerting
hygiene, raise the cap today regardless.

### Operations (COO)

**Summary:** Better Stack overlap thesis **inverts** — free tier is a shared 10-unit pool
at 6/10 used; beyond it $2.00/heartbeat = 2.5× Sentry. Sentry is the cheap venue; do not
migrate. Located the cliff precisely at **renewal**, all-or-nothing. Confirmed no reserved
volume exists. Confirmed neither existing tool can detect live↔IaC drift.

### Product (CPO)

**Summary:** Reframed the question: "raise budget or prune?" is a false trade — pruning
cannot clear the cliff (no in-cycle refund), so they are different tickets. The honest
prune is narrow: the 4 Tier-2 dormant crons mean *"you are paying $37/yr to be alerted if
four switched-off features fail to successfully report being switched off."* Identified
the lifecycle gap as **structural and one-way by design**. Sequencing: raise cap → add
drift detection → prune, or it re-accretes.

### Legal (CLO)

**Summary:** No legal exposure; this is an ops cost decision — no outside-counsel
threshold. **One** binding exception: `scheduled_github_app_drift_guard` is cited by name
at `article-30-register.md:303` as an **"Art. 33 latency primitive"** and must not be
pruned at any cost tier. The other six security-adjacent candidates are **not**
register-cited (grepped in both underscore and hyphen form; zero hits). EU residency is
not a factor — monitors already run on `de.sentry.io`; destroy/recreate stays intra-cluster.

## Capability Gaps

1. **No live→IaC drift detection for Sentry resources.** Evidence: `grep -nE
   'orphan|Class A|Class B|Class C' apps/web-platform/scripts/sentry-monitors-audit.sh`
   → classes A/B/C are all monitor↔alert-rule joins (`:274-281`); zero live↔IaC compare.
   `sentry-monitor-iac-parity.test.ts:13-15` is explicitly one-way. Owner: Engineering.
2. **No working destroy path for Sentry IaC resources.** Evidence: `grep -c
   'ghcr_token_minter' .github/workflows/apply-sentry-infra.yml` → `0`, while the monitor
   is live in Sentry. Removing a block from `.tf` is a silent no-op under `-target=`
   scoping. Owner: Engineering.
3. **No monitor-value telemetry.** No prior audit records which monitors have ever caught
   a real miss. `learnings-researcher` found no such analysis. This is why the
   CTO/CPO prune disagreement could not be settled on data. Owner: Engineering/Product.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident`.

**Artifact:** the Sentry cron + uptime monitor set for Soleur production (49 cron
monitors in `apps/web-platform/infra/sentry/cron-monitors.tf`, 4 uptime monitors in
`uptime-monitors.tf`).

**Vector:** silent, total loss of missed-run detection. At the next renewal, if PAYG
cannot cover all active monitors, **every monitor deactivates at once** and check-ins are
silently dropped — workflows keep running while alerting dies, with no error surfaced.
The operator would believe monitoring is healthy while it is entirely absent.

**Monitors whose silence is a single-user incident** (CPO + CLO converged):

| Monitor | Incident story |
|---|---|
| `soleur_acme_probe` (`uptime-monitors.tf:173`) | Cert renewal fails → apex 526s for ~24h. This is the 2026-05-18 outage verbatim. |
| `soleur_apex` (`:53`) | The site is down. |
| `scheduled_inngest_health` (`cron-monitors.tf:613`) | Inngest crash-loop. Its own header records a P1 that ran **~14h unseen** (#5542) *because this monitor did not exist*. |
| `scheduled_oauth_probe` (`:119`) | A user cannot log in. |
| `scheduled_membership_health` (`:856`) | A user is locked out of their org. |
| `cron_email_ingress_probe` (`:694`) | A user's inbound email is silently dropped. |
| `cron_egress_resolve` (`:706`) | Dead timer → progressive total container egress loss; only alarm on the hang path. |
| `scheduled_github_app_drift_guard` (`:183`) | **Art. 33 latency primitive** — unauthorized GitHub App permission grant goes undetected; statutory 72h clock never starts. |

The all-or-nothing deactivation means these are not lost individually — they are lost
**together, silently**, on a billing boundary. That is why Decision 1 is unconditional
and ships first.

## Session Errors

1. **Roadmap drift detected and not fixed in this session.** `roadmap-reconcile.sh
   validate` reported `STALE_STATUS|phase 4|roadmap=43o/160c|milestone=57o/169c`. Phase-4
   counts do not bear on a vendor-spend assessment, and the tool's prescribed fix is the
   roadmap-review cron (which opens its own reviewed PR), so reconciling inline was out of
   scope. Flagged rather than silently skipped.
2. **My initial meta-watchdog hypothesis was wrong** and was caught by the CTO, not by my
   own pre-spawn probe. I should have grepped `cron-inngest-cron-watchdog.ts` before
   threading the hypothesis into a leader prompt (`hr-verify-repo-capability-claim-before-assert`).
   Cost: one leader-prompt round premised on a retired capability.
</content>
</invoke>
