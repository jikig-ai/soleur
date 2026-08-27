---
title: "App-originated Inngest dispatch has been failing continuously against the braked dedicated host"
date: 2026-08-25
incident_pr: 7692
incident_window: "at least 2026-08-20T00:52Z -> ongoing (bounded below by the host's unchanged boot_id)"
recovery_at: "not recovered"
suspected_change: "the INNGEST_CUTOVER_FLIP=rolled-back brake stopping inngest-server on soleur-inngest-prd, while web-1's dispatch target stayed 10.0.1.40:8288"
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - availability
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`app/api/inngest/route.js` on web-1 dispatches events to the dedicated Inngest host at
`10.0.1.40:8288`. That host's `inngest-server` unit is stopped — deliberately, by the flip FSM's
`rollback` arm — so every one of those dispatches is refused at the TCP layer with
`ECONNREFUSED 10.0.1.40:8288`. This has been continuous, not intermittent.

The incident is **not** the host being stopped. The host being stopped is a known, deliberate
state. The incident is that a live production dispatch path was pointed at it the whole time and
nobody was told, because the only thing being watched — scheduled crons, which run on web-1's
co-located scheduler — stayed green throughout.

This PR does not fix it. It is filed as **#7698** and remains open.

## Status

`ongoing` — the dispatch path is still failing as of 2026-08-25. Nothing in PR #7692 changes the
runtime; PR #7692 ships the detection that would have surfaced it.

## Symptom

`ECONNREFUSED 10.0.1.40:8288`, emitted from `.next/server/app/api/inngest/route.js` on web-1.

Measured 2026-08-25 over a 6h window, and the saturation check matters because a `--limit`-bound
count under-reports a saturating channel: the window returned **4,674 rows at limit 5000 and 4,674
at limit 10000** — identical, so the read is complete and not clipped. Of those, **2,864–2,872**
carry the `10.0.1.40:8288` target (the spread is the window sliding between two calls).

That is **~478/hour, ~11,500/day**.

An earlier reading in the same session, recorded on #7698 and in the runbook, was ~621/hour
(~14,900/day) from a different window. Both are the same order and both describe a continuously
failing path; the per-hour figure tracks app traffic and should be re-measured rather than quoted.
The earlier figure is left in place on #7698 as the dated record it is, with this one appended.

## Incident Timeline

- **Start time (detected):** 2026-08-25 (measured); the failing condition predates detection.
- **End time (recovered):** not recovered.
- **Duration (MTTR):** open.

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-08-20T00:52Z | Dedicated host replaced and rebooted. `boot_id=cb4e3bb0-b625-45d4-8da1-dde39e4a7dbe`. This is the lower bound on the window: the same `boot_id` and an `inactive` unit were still being reported 5.4 days later, so the unit has not served since. |
| agent | 2026-08-25 (session start +10min) | Pulled Better Stack and measured `ECONNREFUSED 10.0.1.40:8288` from web-1. Wrote it into #7674 as "correction #2 to the handoff". |
| agent | 2026-08-25 (same document) | Wrote a section headed `## No outage` three sections below that measurement, in the same issue body. Repeated the claim in the runbook and to the operator. |
| agent | 2026-08-25 (review) | An architecture review agent asked whether the "no outage" premise held. Re-measured; it did not. |
| agent | 2026-08-25 | Filed #7698. Corrected #7674 and the runbook with a measured split table. |
| agent | 2026-08-25 (ship) | Re-measured for this PIR: ~478/hour over 6h, non-saturating at two limits. |

## Participants and Systems Involved

web-1 (`app/api/inngest/route.js`, the dispatch caller); `soleur-inngest-prd` / `10.0.1.40`
(`inngest-server`, stopped); the `INNGEST_CUTOVER_FLIP` FSM (`rolled-back`, terminal);
`scheduled-inngest-health.yml` (was watching only web-1); Better Stack / ClickHouse (the only
surface on which any of this was visible).

## Detection (+ MTTD)

- **How detected:** manual — an agent-run Better Stack query, not a monitor. No alert existed for
  this path. `scheduled-inngest-health.yml` polled the web host, which was genuinely healthy, and
  reported green throughout.
- **MTTD:** unbounded in the meaningful sense. The evidence was produced on demand within ten
  minutes of someone looking; no automated surface would have produced it at all.

## Triggered by

system.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The dedicated host is broken / mid-restart-loop | Unit `inactive`, `http_code=000`, `bind=[]` | One unchanged `boot_id` across 5.4 days; `vector` and `redis` both `active` on the same host | rejected |
| The host was deliberately stopped and left stopped | Every probe row carries `cutover_flag=rolled-back`; `inngest-cutover-flip.sh` `rollback` arm stops the unit and parks at a terminal state that no restart releases | — | confirmed |
| Dispatch failures are incidental / low volume | — | 2,864+ refused dispatches in 6h, continuous | rejected |

## Resolution

Unresolved. The dispatch path recovers only when the dedicated host serves again, which is
reachable only inside a cutover window (the brake is terminal by design — see ADR-100). #7698
carries the fix decision, which is a genuine fork: repoint web-1's dispatch at the co-located
scheduler, or complete the cutover.

## Recovery verification

Not yet available. Two probes will assert it when it happens, and both ship in PR #7692:

- `scripts/followthroughs/inngest-host-not-serving-7674.sh` — POSITIVE assertion only: a
  `SOLEUR_INNGEST_SERVER_PROBE` row from this host carrying **both** `server_active=active` and
  `http_code=200`. It cannot pass on absence.
- the `*/15` dedicated-host arm added to `.github/workflows/scheduled-inngest-health.yml`, which
  classifies `stopped-by-brake` distinctly from `not-serving` so a deliberate stop is never read as
  a fault and a fault is never read as the brake.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why are app-originated events failing?** web-1 dispatches to `10.0.1.40:8288` and the listener
   is not there.
2. **Why is the listener not there?** `inngest-server` is stopped on the dedicated host.
3. **Why is it stopped?** `INNGEST_CUTOVER_FLIP=rolled-back`. The flip FSM's `rollback` arm stops
   the unit and writes a terminal state; every 30s tick since has been a `noop-rolled-back`.
4. **Why did that leave a production caller pointed at a dead address?** The brake was designed to
   protect the *scheduler* cutover. Nothing in the rollback path reconsiders the *dispatch* target,
   and nothing asserts that the two agree.
5. **Why did nobody notice for days?** The only Inngest health monitor watched the web host, which
   was healthy. `SOLEUR_INNGEST_SERVER_PROBE` had been emitting the dedicated host's `inactive`
   state hourly since #6617a and **had no consumer at all**. Symptom and cause were in the same log
   line, unread, roughly 130 times.

Root cause: a rollback that is safe for the component it was written for, plus a monitor whose
scope was narrower than the system it was named after.

## Versions of Components

- **Version(s) that triggered the outage:** the `rollback` arm of `inngest-cutover-flip.sh` as of
  the 2026-07-23 flip; host replaced 2026-08-20.
- **Version(s) that restored the service:** none — unresolved.

## Impact details

### Services Impacted

App-originated Inngest event dispatch from web-1. **Not** impacted: scheduled crons, which run on
web-1's co-located scheduler and were firing normally throughout — which is precisely why this
looked fine.

### Customer Impact (by role)

- Prospect: none observed — the dispatch path is not on any unauthenticated marketing surface.
- Authenticated app user: any product behaviour that depends on an app-fired background event does
  not happen. Not enumerated per-feature here; #7698 owns that enumeration, because it needs the
  caller inventory rather than the log rate.
- Legal-document signer: not assessed; no signing flow is known to dispatch through this path.
- Admin via Access: none.
- Billing customer: none observed.
- OAuth installation owner: none observed.

Stated as measured, not as reassurance: the log tells us the dispatches were refused, not which
user-visible behaviours silently did not occur.

### Revenue Impact

None measured. No billing or checkout path is known to dispatch through this route.

### Team Impact

One session's diagnosis re-run, one issue filed, one false "no outage" claim propagated into an
issue body, a runbook, and a report to the operator before being caught.

## Lessons Learned

### Where we got lucky

The co-located scheduler on web-1 was already carrying production crons. Had the cutover completed
far enough for the dedicated host to be the sole scheduler before the brake engaged, this would
have been a total scheduling outage rather than a dispatch-only one.

### What went well

The evidence existed and was cheap to obtain — one Better Stack query, ten minutes in. The
`SOLEUR_INNGEST_SERVER_PROBE` marker was already emitting exactly the right fields, including the
`cutover_flag` that explains the stop. Nothing had to be instrumented to diagnose this.

### What went wrong

Two failures, and the second is the one worth keeping.

1. **A monitor named for a system watched one host of it.** An hourly probe with no consumer is
   indistinguishable from no probe. Fixed in PR #7692.
2. **The evidence was measured, written down, and then contradicted in the same document.** The
   `ECONNREFUSED` measurement was recorded in #7674 as a correction, and a section headed
   `## No outage` was written three sections below it in the same body — then repeated in the
   runbook and to the operator. It survived a plan phase, a CTO consult, and my own writing, and was
   caught only because a review agent asked whether the premise held. "Crons are firing" was taken
   to mean "nothing is broken". A half-true summary is worse than a missing one, because it
   terminates the inquiry that would have found the rest. Proximity in one artifact is not
   integration: writing a fact down does not make the conclusion drawn later in the same document
   consistent with it. Recorded at
   `knowledge-base/project/learnings/2026-08-25-i-wrote-the-evidence-down-and-then-concluded-the-opposite.md`.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #7698 | Decide and implement the fix for app-originated dispatch — repoint web-1 at the co-located scheduler, or complete the cutover. Includes enumerating which callers, and therefore which user-visible behaviours, are affected. | open |
| #6616 | Cross-cutting sweep: `host_name` telemetry can be forged by a web host, so the eight other Better Stack readers that key on it alone share this incident's mis-attribution risk. | open |
