---
title: "ADR-259: DB-outage paging via Slack, and a bounded auto-restart on the proven Supabase hang signature"
status: Accepted
date: 2026-09-28
supersedes: []
amends: []
issue: 9168
related: [7884, 3960, 7529, 9184]
related_adrs: [ADR-222, ADR-248, ADR-079, ADR-249, ADR-169]
tags: [observability, better-stack, slack, supabase, auto-restart, prod-write-authorization, terraform]
brand_survival_threshold: single-user incident
---

# ADR-259: DB-outage paging via Slack, and a bounded auto-restart on the proven Supabase hang signature

## Status

Accepted — 2026-09-28. Delivers the decision record for #9168 / PR #9184.

## Context

On 2026-09-28 the prd Supabase project's Postgres halted a second time in 13
days with an identical signature (first: 2026-09-15; postmortems in
`knowledge-base/engineering/operations/post-mortems/`). The remediation that
followed the first incident (#7884, ADR-222) closed the **detection** gap: the
`app_health` keyword monitor opened a Better Stack incident 7 minutes after
onset. It did not close the **delivery** gap — the monitor's channels are
`email = true`, `call`/`sms`/`push = false`, and its escalation `policy_id`
is gated on `var.betterstack_paid_tier`, which is unset. The page sat in an
inbox while the app stayed down ~37 minutes, and recovery began only when an
agent happened to read `/health` while chasing an unrelated failed deploy. An
earlier same-day window (10:34Z–10:37Z) had fired and self-recovered
unnoticed.

So the incident decomposed into two distinct defects: **detection without
delivery**, and **recovery that requires a human who was never paged** — even
though the failure signature (Postgres logs stop mid-stream; `db`, `auth`,
`rest` UNHEALTHY while `pooler` stays ACTIVE_HEALTHY; only a Management API
project restart recovers) is crisp and has now been proven twice.

## Decision

### 1. Paging: Slack native integration over the Responder seat

Better Stack incidents reach the operator's phone through the **native
Better Stack → Slack integration** (dashboard OAuth, an operator credential-
consent step — there is no Terraform-managed Slack resource, and
`betteruptime_outgoing_webhook` payloads are not Slack-format-compatible),
plus a **measured `push = true` flip on `app_health`** alone (`#7798`
precedent: probe the vendor behavior at apply on one monitor; revert cleanly
if the plan refuses). Email stays enabled.

This discharges — by declining again — the `expenses.md` Responder deferral
(#3960), whose trigger was "first incident with user-visible latency from
email-only routing". That trigger fired on **09-28** (~16 min and effectively
~23 min until a responder engaged); the 09-15 outage (~89 min unnoticed)
demonstrated the same underlying risk class — a page that cannot reach a
human — though strictly it predated the keyword monitor's adoption and its
latency was missing *detection*, not email-only *delivery*. The operator
still declined the $29–34/mo seat: the free-tier Slack
path covers the failure mode. **Revisit condition:** if the Slack channel
proves insufficient (missed alerts, Slack-side outage on an incident), the
Responder seat is re-evaluated rather than assumed dead.

Escalation policies stay gated off (`var.betterstack_paid_tier` unset) —
they require the Responder tier that was not purchased. The unsigned Better
Stack DPA is flagged, not blocking: #7529.

### 2. Recovery: pre-authorized bounded auto-restart (a deviation, recorded)

A scheduled GitHub Actions watchdog
(`.github/workflows/scheduled-supabase-watchdog.yml`) may issue
`POST /v1/projects/{ref}/restart` on the prd project **without a per-occurrence
human ack**. This is an express, bounded deviation from
`hr-menu-option-ack-not-prod-write-auth`, in the ADR-079/ADR-249 authorization
posture (a prod write may be delegated to automation when the ADR records the
delegation, the trigger predicate, and the circuit breaker — the CLO condition
from the brainstorm). The justification: the signature is proven twice, a
project restart is the only known remedy, and the measured human-in-loop
latency this incident is ~37 minutes — a page-then-approve loop reproduces
exactly the gap it exists to close when the operator is asleep.

**Bounds** (all must hold for a restart to be issued; every failure fails
closed to detect-only):

- **Signature, exact:** `{db, auth, rest} UNHEALTHY ∧ pooler ACTIVE_HEALTHY`,
  sustained over **≥3 consecutive reads** (~60 s apart). `COMING_UP`,
  `UNREACHABLE`, missing keys, extra unhealthy services, or a
  pooler-also-unhealthy read yield `ambiguous`, never a restart.
- **Independent corroboration:** the app `/health` endpoint agrees
  (`supabase` non-`connected`) — the Management API is a single failure
  surface, satisfying ADR-169's independence criterion (the Management API is
  the control plane, independent of the data plane it probes).
- **Dark-launch arm:** the write path is gated on repo variable
  `vars.WATCHDOG_ARMED`; until the operator sets it
  (`gh variable set WATCHDOG_ARMED --body 1`), the workflow is detect-only
  (audit issue + Sentry check-in, zero restart POSTs) per
  `wg-dark-launch-deploy-gates`.
- **Cooldown:** ≥30 minutes between automated restarts, enforced by the last
  restart timestamp recorded on the audit issue.
- **Give-up:** attempts are counted (not successes); after the attempt budget
  is exhausted without recovery, the watchdog stops restarting and escalates
  (priority issue + alert).
- **Audit trail:** every detection and every restart writes or updates a
  GitHub issue labeled `supabase-auto-restart`; a sentinel comment
  (`<!-- watchdog:restart epoch=… -->`) is written **at** the restart POST —
  an absent or unparseable sentinel on a claimed-restart run fails closed.
- **Mutex:** runs serialize on `concurrency: supabase-watchdog` with
  `cancel-in-progress: false`, so the watchdog can never double-restart.
- **Substrate:** GHA workflow is the executor (the app container deliberately
  holds no Management API credential); primary dispatch is the **Inngest
  dispatch cron** `cron-supabase-watchdog-dispatch` firing `workflow_dispatch`
  every 5 min — `schedule:` alone drifts 2–7 h (ADR-248), so the workflow's own
  `*/5` cron is kept only as fallback. The dispatch path is DB-independent:
  the Inngest serve route authenticates on env-held signing keys and run-state
  lives on the dedicated host's Redis, not the Postgres this watchdog watches.
  Dispatch auth is a GitHub App token per `hr-github-app-auth-not-pat`. A
  Sentry cron monitor covers the watchdog itself, so a dead watchdog pages.
- **Worst false-positive cost:** ~6 minutes of restart downtime on a service
  already down — bounded and acceptable against the alternative.

This is compliance-positive under GDPR Art. 32(1)(c) (timely restoration of
availability), which is why the CLO signed off with the audit-trail and
circuit-breaker conditions above.

**Credential-custody residual (accepted, tracked).** The watchdog consumes
`SUPABASE_ACCESS_TOKEN`, an account-scoped Management PAT able to restart and
manage every Supabase project — an infra-write credential under ADR-241 D1,
held in Tier A (a repo Actions secret reachable by any workflow file on any
pushed branch, plus `prd_terraform`). This PR adds an automated prod-write
consumer of that credential and does not move it. Recorded here as the
accepted residual; a Tier-B move (e.g. a main-only environment secret) is a
candidate follow-up, gated on the deploy workflow's access needs.

### 3. Compute mitigation: Micro → Small, via the `supabase/supabase` provider

The prd project is imported into Terraform as `supabase_project.prd`
(`apps/web-platform/infra/supabase-project.tf`) **pinned to all live values,
including `instance_size = "micro"`** — a zero-diff import, so a failed read
can never masquerade as a resize diff. `database_password` carries a
never-applied placeholder under `lifecycle { ignore_changes = […] }` because
the provider's Update PATCHes a dedicated db-password endpoint on any diff —
without the pin the first apply would rotate the live DB password. The
`"small"` flip is a deliberately sequenced **follow-up apply** the operator
watches (~2 min resize downtime, +$5/mo net over the Pro credit). This is
mitigation, not diagnosis: if Supabase support names a fault class that
compute size cannot fix, Small stays as headroom and this paragraph records
why.

## Alternatives considered

- **Buy the Responder seat anyway.** Rejected by the operator — the free-tier
  Slack integration covers the paging need at $0; the seat is re-evaluated if
  Slack proves insufficient.
- **Inngest cron as the restart substrate.** Rejected — the app container
  deliberately holds no Management API PAT (`cron-supabase-disk-io.ts`
  comment); CI already calls the Management API, so the GHA workflow widens
  no credential surface.
- **`betteruptime_outgoing_webhook` → Slack.** Rejected — the raw webhook
  payload is not Slack-format-compatible; the native integration is the
  free-tier channel the vendor supports.
- **Page-then-approve (human stays in the restart loop).** Rejected for this
  signature — it waits on a human who may be unreachable, which is the exact
  37-minute gap this ADR exists to remove. The deviation is bounded to the
  proven signature only; everything else still requires
  `hr-menu-option-ack-not-prod-write-auth`.
- **Do nothing on compute until support answers.** Rejected — the import
  lands IaC coverage at zero diff now; the Small decision is decoupled from
  the ticket outcome by design.

## Consequences

- **Positive:** DB-readiness incidents reach the operator's phone in minutes;
  the proven hang signature self-remediates in ~10 minutes with no human;
  the Supabase project is IaC-managed; every automated prod write leaves an
  auditable trail (issue + sentinel + Sentry check-in).
- **Negative / accepted:** automation now holds delegated prod-write
  authority over one Supabase endpoint under a bounded predicate — the
  deviation is recorded expressly and the fail-closed protocol is tested
  (`supabase-watchdog-classify.test.sh` mutation matrix in the plan). A Slack
  outage would again degrade paging to email-only (the revisit condition
  above).
- **Cross-references:** ADR-222 (the readiness monitor this extends),
  ADR-248 (dispatch clock the watchdog rides), ADR-079 / ADR-249 (prod-write
  authorization posture this deviates from, with bounds), ADR-169
  (independence criterion — Management API = control plane). Postmortem:
  `post-mortems/prd-supabase-database-unreachable-2026-09-28-postmortem.md`.
  Ticket draft:
  `operations/ticket-drafts/supabase-postgres-hang-recurring-2026-09.md`.

## Diagram

`model.c4` gains a `slack` external system (`betterstack -> slack` incident
alerts, `slack -> founder` mobile push) and a `github -> supabase` edge for
the Management API health probe + bounded auto-restart
(`scheduled-supabase-watchdog.yml`, #9168); the `betterstack -> founder`
edge prose is amended to name Slack + push alongside email.
