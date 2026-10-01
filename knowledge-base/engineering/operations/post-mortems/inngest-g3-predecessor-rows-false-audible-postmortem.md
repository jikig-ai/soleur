---
title: "op=resume G3 reported a replaced inngest host audible on its destroyed predecessor's rows, and wrote the flag"
date: 2026-09-24
incident_pr: 8759
incident_window: "2026-09-24 14:29 UTC — one op=resume dispatch (run 36013051602) wrote INNGEST_CUTOVER_FLIP=flushed while no current server was shipping"
recovery_at: "2026-09-24 19:03 UTC — a later op=resume (run 36045234529) passed G3 on the current server's own rows; flushed-resume-no-reflush landed"
suspected_change: "No regression. G3's host filter (host + host_name) has never distinguished server generations; the 2026-09-24 host replace was the first time a predecessor's rows sat inside the 15-minute window when op=resume ran."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data involved; a gate misread its own telemetry"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

During the 2026-09-24 recovery of the dedicated Inngest host, `op=resume`'s G3 host-audibility
gate counted 45 `inngest-cutover-flip` rows as proof the host could act on the write. All 45 came
from the server that had just been destroyed: `host` and `host_name` are identical across a
replace (AP-027, ADR-149), and G3 filtered on nothing else. G3 passed and `INNGEST_CUTOVER_FLIP`
was written to `flushed` at a moment when no current server was shipping rows at all.

## Status

resolved — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

## Symptom

G3's success notice ("host is audible (45 inngest-cutover-flip row(s) … within 15m)") contradicted
Better Stack, where the last `soleur-inngest` row before the dispatch was 14:25:05 and the next
was 18:59:58 — a window in which no server of that name shipped anything.

## Incident Timeline

- **Start time (detected):** 2026-09-24 ~19:10 UTC (while reconciling the recovery runs)
- **End time (recovered):** 2026-09-24 19:03 UTC
- **Duration (MTTR):** ~4 h 34 min from the false-audible write to the first write that the current server itself evidenced; the write itself caused no action (see Impact).

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column). The three op=resume runs were `workflow_dispatch`es recorded under the operator's own GitHub account; the API does not record whether the dispatch was typed by hand or issued by an agent session on the operator's credentials, so they are attributed `human` here.

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 14:25:05 | Old server's last `inngest-cutover-flip` row. |
| human | 14:29:02 | op=resume (run 36013051602) G3 counts 45 of the old server's rows as audible and writes `flushed` at 14:29:03. |
| system | 18:57:33 | Current server `soleur-inngest` (id 167310350) created. |
| system | 18:59:58 | First row from the current server. |
| human | 19:00:05 | op=resume (run 36045048975) G3 correctly refuses: 0 rows. |
| human | 19:02:27 | op=resume (run 36045234529) G3 passes on 15 rows from the current server. |
| system | 19:03:12 | `flushed-resume-no-reflush` row from the current server. |
| agent | ~19:10 | Discrepancy between the 14:29 notice and the telemetry noticed during reconciliation; fix follows in PR #8759. |

## Participants and Systems Involved

The cutover workflow (`.github/workflows/cutover-inngest.yml` → `scripts/cutover-inngest.sh`),
Better Stack Logs source 2457081, the Hetzner Cloud API, Doppler `soleur-inngest/prd`.

## Detection (+ MTTD)

- **How detected:** manual — the agent reconciling the recovery runs compared G3's notice against the rows in Better Stack.
- **MTTD (mean time to detect):** ~4 h 40 min (14:29 → ~19:10).

## Triggered by

system — a host replace left the predecessor's rows inside G3's 15-minute window.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| G3's host filter cannot tell server generations apart | `host`/`host_name` identical on both servers; the 45 rows all predate the current server's `created` | none | confirmed |
| A second live server shipped the rows | — | Hetzner names are unique per project; no row from any `soleur-inngest` machine between 14:25 and 18:59 | rejected |

## Resolution

PR #8759 floors every write-gating liveness count at the Hetzner API `created` of the one
server named `soleur-inngest`: a row counts only when its journald event time AND its Better Stack
ingest `dt` are both at or after that instant. An unreadable anchor fails closed.

## Recovery verification

A read-only replay of the new filter over 18 h of real rows: floor 0 → `3677 3677 0 0 0`,
floor = `created` → `254 3677 3423 0 0` (counted host_pair pre_floor malformed skew_suspect).
The predecessor's 3,423 rows are excluded; `malformed` and `skew_suspect` are 0.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did G3 pass? It counted 45 host-pair rows within 15 minutes.
2. Why were those rows host-pair? `host` is the Hetzner server name and `host_name` a rendered literal, both identical on the replacement.
3. Why did nothing else distinguish them? The reader had no notion of server generation; identity was the only filter.
4. Why was that not caught earlier? No earlier op=resume had run inside 15 minutes of a replace, and the runbook asserted a freshly replaced host "is not audible until Vector is up".
5. Why did the claim go unmeasured? The gate's success message stated a conclusion ("the on-host FSM can act on this write") that its predicate did not establish — the AP-027 class.

## Versions of Components

- **Version(s) that triggered the outage:** `scripts/cutover-inngest.sh` as of `main` before PR #8759.
- **Version(s) that restored the service:** PR #8759.

## Impact details

### Services Impacted

None materially. `flushed` is acted on only by the on-host timer of whichever host runs next, so
the premature write recovered nothing and broke nothing; by 19:00 the flag read `done` again.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none from this defect. (The host-dark window itself, 14:25–18:59, had a separate cause — the Vector download stall fixed in PR #8741.)
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

A misleading success notice during an active recovery; a later dispatch had to establish the real state.

## Lessons Learned

### Where we got lucky

The flag's consumer is the on-host timer, so a write that lands with no current host does nothing.
Had G3 gated a write with an immediate effect, the predecessor's rows would have authorised it.

### What went well

The next two dispatches behaved correctly (a refusal at 19:00, a pass on the current server's own
rows at 19:02), and the telemetry kept enough fields to reconstruct the timeline exactly.

### What went wrong

A gate reported a measured-sounding fact ("host is audible") that its predicate could not
establish, and the runbook repeated the same false assurance.

## Action Items & Follow-ups

No action items — incident fully resolved in the source PR with no residual work.
