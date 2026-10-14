---
title: "The registry liveness heartbeat flapped for a week and the feeder recorded no cause"
date: 2026-09-28
incident_pr: 9174
incident_issue: 7270
incident_window: "2026-08-03T18:22:54Z → 2026-08-10T22:18:10Z (124 missed-heartbeat incidents)"
recovery_at: "2026-08-10T22:18:10Z (last incident outside a registry replace; 5 later incidents each coincide with a replace)"
suspected_change: "undetermined — the liveness feeder withheld beats without recording why, so the cause cannot be reconstructed after the fact"
brand_survival_threshold: none
status: unresolved but ended
triggers:
  - Better Stack `soleur-registry-prd` heartbeat (period 60 s, grace 30 s) recorded missed-heartbeat incidents
  - web zot consumer probe logged `unexpected code 000000` for every private-network failure (#7262)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — observability of an internal registry host only. No personal data is stored on or passes through the zot registry; no data was disclosed, altered or lost."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

The `soleur-registry-prd` Better Stack heartbeat, fed by the registry host's
`zot-liveness-heartbeat` timer, recorded 124 missed-heartbeat incidents between
2026-08-03T18:22:54Z and 2026-08-10T22:18:10Z, with zero in the preceding two weeks. The monitor
read `up` between incidents, so this was flapping rather than a sustained loss of the registry.
The feeder withholds a beat when zot does not answer its local probe, and it recorded nothing
about why a beat was withheld or late. So the week cannot be explained after the fact.

In the same period the web host's consumer probe could not name a private-network failure. It
logged every one as `unexpected code 000000` (curl's `000` plus the `|| echo 000` fallback), so
its `000 UNREACHABLE` arm never fired (#7262).

## Status

unresolved but ended. The flapping stopped on 2026-08-10. The 5 incidents since (08-16, 09-18,
09-20, 09-22, 09-28) each coincide with a registry host replace. The cause of the 08-03 → 08-10
week is not known.

## Symptom

Repeated `Missed heartbeat` incidents on `soleur-registry-prd`. The first 18 (#7270's original
measurement) clustered at two durations: 0.15–1.3 s, a beat landing just past the 90 s deadline,
and 45–60 s, a feeder cycle producing no beat at all.

## Incident Timeline

- **Start time (detected):** 2026-08-03T18:22:54Z (first incident, recorded by the monitor)
- **End time (recovered):** 2026-08-10T22:18:10Z (last incident outside a replace)
- **Duration (MTTR):** ~7.2 days of intermittent flapping

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-08-04 | #7270 filed from the Uptime API: 18 incidents, feeder records nothing that could tell a cause. |
| agent | 2026-09-28 | Re-measured from the Uptime API: 129 incidents in total, 124 inside the window above. Correction posted on #7270. |
| agent | 2026-09-28 | PR #9174: feeder counters on `SOLEUR_ZOT_DISK`, probe names `000`. |

## Participants and Systems Involved

Registry host (zot, `zot-liveness-heartbeat.{service,timer}`, `zot-disk-heartbeat`), web-1's
`web-zot-consumer-probe`, Better Stack Uptime and Telemetry.

## Detection (+ MTTD)

- **How detected:** monitoring system (Better Stack heartbeat), triaged from the Uptime API.
- **MTTD (mean time to detect):** immediate for each incident. The week-long pattern was triaged
  the next day (#7270).

## Triggered by

system — cause undetermined.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Timer lateness (beat just past the 90 s deadline) | 0.15–1.3 s cluster in the first 18 | None recorded | Unresolvable: no lateness counter existed |
| zot not answering the feeder's local probe | 45–60 s cluster (whole cycles missing) | None recorded | Unresolvable: the miss code was not recorded |
| Better Stack ping failure | none | none | Unresolvable: ping failures were not counted |

## Resolution

The flapping ended without an intervention attributable to it. PR #9174 adds the instrument that
was missing: per-boot `liveness_miss_cum`, `liveness_ping_fail_cum`, `liveness_ok_cum`,
`liveness_late_ok_cum` and `liveness_last_miss_code` on the 5-minute `SOLEUR_ZOT_DISK` row. It
also adds the runbook section "A zot heartbeat paged" in `betterstack-log-query.md`, whose
decision table separates the three hypotheses above.

## Recovery verification

Uptime API: zero `soleur-registry-prd` incidents after 2026-08-10T22:18:10Z other than the 5 that
fall inside registry replace windows.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why can the week not be explained? The feeder withheld beats without writing a reason anywhere.
2. Why no reason? It was written as a pure gate (ping on success, silence otherwise). The only
   record of a withheld beat was the heartbeat's absence, which alarms but does not explain.
3. Why did the web probe not help? Its `000` verdict never fired (#7262), so a private-network
   failure between web and registry read as an unclassified code.
4. The underlying cause of the flapping itself is not known. That is the finding.

## Versions of Components

- **Version(s) that triggered the outage:** unknown.
- **Version(s) that restored the service:** n/a (self-ended).

## Impact details

### Services Impacted

Registry liveness paging (noise, and an unexplained signal). Image-pull impact during the window
was not measured by this investigation.

### Customer Impact (by role)

- Prospect: none. The registry is an internal image-pull path.
- Authenticated app user: none measured.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

A week of pages that could not be acted on, and an issue (#7270) whose initial figures ("18x",
"stopped 08-05") were superseded by re-measurement.

## Lessons Learned

### Where we got lucky

The flapping ended by itself, and the monitor never went into a sustained down state.

### What went well

The triage pulled every figure from the Uptime API and the log warehouse rather than a dashboard.

### What went wrong

A heartbeat feeder that only gates cannot explain its own silence. A counter for lateness also
has to reset on every competing cause, or every recovery beat reads as late. This was caught in
review of #9174 and is recorded in
`knowledge-base/project/learnings/2026-09-28-a-counter-named-for-a-cause-measured-a-gap-that-every-outage-produced.md`.

## Action Items & Follow-ups

No action items — incident fully resolved in the source PR with no residual work. The cause of the week is unrecoverable; PR #9174's counters and runbook decision table are what answer a recurrence.
