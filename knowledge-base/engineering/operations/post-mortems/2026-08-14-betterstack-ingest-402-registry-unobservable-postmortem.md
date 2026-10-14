---
title: "Better Stack refused all ingest for two days while the read path stayed green"
date: 2026-08-17
incident_pr: 7573
incident_issue: 7569
incident_window: "2026-08-14 19:06:58Z → 2026-08-16 ~20:00Z (~49h)"
recovery_at: "2026-08-16 (account-level action by the operator; verified 202 + rows resuming)"
suspected_change: "none — cumulative ingest volume (~135k rows/day) exhausted the account's Logs quota"
brand_survival_threshold: none
status: resolved
triggers:
  - HTTP 402 {"error": "Quota exceeded"} on every ingest POST
  - all producers on source 2457081 stopped at the same instant
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/observability only. No personal-data exposure: the vendor REFUSED writes, so no data was disclosed, altered, or lost beyond telemetry that was never persisted. Egress strictly DECREASED for the duration."
---

## What happened

At **2026-08-14 19:06:58Z** Better Stack began refusing every ingest POST to source 2457081 with
`HTTP 402 {"error": "Quota exceeded"}`. The **read** path continued answering `200` throughout.

The registry host is the fleet's sole image-pull path (host→GHCR was removed earlier in 2026) and
has no SSH by policy, so this channel is its only off-box view. For ~49 hours a crash loop, a
filling disk, or an upload failure would have produced no signal at all.

Detected on 2026-08-16 by a reviewer filing #7569 off the back of the #7555 review — **not** by
any monitor.

## Why it was invisible for two days

Three guards were green the whole time, each for a different reason. That is the finding.

1. **`zot-restart-loop-alarm.sh` collapsed two states into one `||`.**
   `[[ "$control_rc" -ne 0 || -z "$CONTROL" ]]` → non-alarming `TRANSIENT`. A query that
   *failed* and a query that *answered and found the warehouse empty* are different epistemic
   states; only the first is a probe fault. The message it emitted named "Better Stack
   unreachable / creds unset" — two causes the run had just measured **false**, since `rc` was
   `0`.
2. **The workflow reported `completed/success` every 30 minutes** — because the detector *ran*.
   Green CI on a detector says the detector executed, never that its subject is well.
3. **`lint-diagnosis-claims.sh`, the AP-021 gate built to stop exactly (1)'s message, never
   counted it.** Measured: `OPERATOR_LINE` rejects the line first (it is a bare shell
   assignment, not an emission), so `CLAIM` is never consulted, and `MEASURED` would exempt it
   anyway. The gate was not bypassed — it was looking at the wrong lines.

## 5 Whys

1. *Why was the registry unobservable?* Its only off-box channel stopped delivering.
2. *Why did it stop?* Better Stack refused all writes with 402 — an account-level quota
   exhaustion, not a producer fault.
3. *Why was the quota exhausted?* Sustained ~135,316 rows/day against a 3 GB/month allowance.
   The dominant producer is the `soleur-web-platform` container at ~101,000 rows/day (75%),
   because pretty-printed multi-line object logs bill **one row per physical line**.
4. *Why did no alarm fire?* The one detector watching that source conflated "the read failed"
   with "the read answered and found nothing", and reported the non-alarming verdict.
5. *Why was there no quota monitor?* The 2026-06-10 near-miss named exactly this gap and filed
   **#5103** for it (with **#5134** as a deferred increment). **Neither was built.** This
   recurrence is the predicted one.

## What was fixed

`scripts/lib/betterstack-absence.sh` splits an empty read into three states — `TRANSPORT_FAIL`
(we learned nothing), `INGEST_DARK` (the source is taking no writes), `LIVE` — with the rc branch
and the emptiness branch as deliberately separate `if`s. Exit 4 files a deduped
`[ci/betterstack-ingest-dark]` issue on a channel independent of the monitored vendor.
`scripts/betterstack-ingest-probe.sh` annotates the refusal code (402 quota vs 401 auth) with no
veto, and posts an **empty batch** so it never writes a row that would satisfy the alarm's own
control forever.

Also closed: F15, an unanchored `--grep` that let a row merely *quoting* the marker suppress the
alarm indefinitely.

**Verified in both directions against production, same day, no code change between:**

| | dark (2026-08-16 morning) | restored (2026-08-16 evening) |
|---|---|---|
| ingest probe | `INGEST_REFUSED_QUOTA http=402`, exit 4 | `INGEST_ACCEPTING http=202`, exit 0 |
| alarm, zot leg | `INGEST_DARK`, exit 4 | `GREEN`, exit 0 |
| alarm, NIC leg | `INGEST_DARK` | `GREEN` |

## What is NOT fixed

**The volume that caused this is unchanged.** The account is accepting writes again at
approximately the rate that exhausted it, so recurrence is a matter of time rather than of
chance. The detector shortens time-to-detection from ~49 hours to ~30 minutes; it does not
prevent the outage.

The 3 GB/month allowance is an **unverified inherited premise** — the Telemetry API exposes no
usage endpoint (`/sources/<id>/usage`, `/usage`, `/billing` all 404 against a working token), so
neither the allowance nor current consumption can be pulled programmatically.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7577 | Cut ingest volume at the Vector chokepoint (single-line structured logging for the web container; `reduce`/`throttle` ahead of the sink; per-emitter ceilings denominated in GB/month) and sweep the ~24 absence-asserting consumers so they return unresolved rather than passed | engineering |
| #7578 | The AP-021 gate never sees operator text assembled in a shell variable — `OPERATOR_LINE` rejects it before `CLAIM` is consulted | engineering |
| #5103 | `vendor-quota-watch` — the 5-Why #5 action item from the 2026-06-10 near-miss, never built. Re-scoped: denominate in GB/month, and note no usage API exists (must self-calibrate from an observed 402 or track cumulative bytes locally) | engineering |
| #5134 | Deferred increment of #5103 (scheduled vendor-quota poll cron) | engineering |

## Related

- `betterstack-quota-near-miss-postmortem.md` — predicted this on 2026-06-10; carries a dated
  `RECURRED` back-link to this document
- ADR-192 — the invariants (three states; no marker predicate satisfiable by an attacker-influenced row)
- `knowledge-base/project/learnings/2026-08-17-an-empty-read-is-three-states-and-my-guard-shipped-two-fail-opens.md`
