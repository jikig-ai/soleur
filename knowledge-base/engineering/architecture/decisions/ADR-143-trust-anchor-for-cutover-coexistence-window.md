---
title: Trust anchor for the Inngest cutover coexistence window
status: accepted
date: 2026-07-24
related: [6178, 6919, 6258]
related_adrs: [ADR-106-inngest-cutover-preflight-scan-bounding-and-in-surface-marker, ADR-100, ADR-138]
amends: ADR-106
brand_survival_threshold: single-user incident
---

# ADR-143: Trust anchor for the Inngest cutover coexistence window

## Status

accepted — **amends [ADR-106](./ADR-106-inngest-cutover-preflight-scan-bounding-and-in-surface-marker.md)**
`## Decision` item 4.

This is recorded as its own ADR rather than folded into ADR-106 because it is a
**source-of-truth change**, not a restatement of one. ADR-106 is scoped to scan bounding,
abandon-safety, and in-surface markers. Moving the safety bound from an operator-typed repo
variable to an on-host observability row introduces a new **trust boundary** and a new
**failure mode** (retention miss); grafting trust-anchor semantics into item 4 would make
ADR-106 canonical for two unrelated concerns.

## Context

`op=verify` step 2.6 is the last open gate on the #6178 dedicated-host cutover, and across
eleven dispatches it **never produced a verdict**.

The scan window opened at `cutover − 200 d`. Measurement (Phase 0, run `30121678305`,
2026-07-24) established the density that had never been measured:

| Quantity | Measured |
|---|---|
| Runs in a **1-day** window | **728** |
| Scan wall-clock for that window | **34 s**, no deadline abort |
| Implied page rate | ~**4.2 s/page** at `PAGE_SIZE=100` |
| Implied 200-day total | ~**145,600** runs ≈ **1,456 pages** |
| Affordable within the 90 s budget | ~18 pages ≈ **~1,800 runs ≈ ~2.5 days** |

The probe is **fail-loud on non-exhaustion** — `_pf_abort` exits 1 and emits *nothing* — so a
window it cannot exhaust yields no verdict at all, at any run count. The deadline lever is
dead: the SUM bound `DEADLINE + PAGE_MIN ≤ outer_curl` caps `PREFLIGHT_DEADLINE_S` at 112 s,
buying ~14 pages against the ~1,456 needed. **The operative variables are window width vs.
budget.**

That forces the window to narrow, which immediately raises the question this ADR exists to
answer: *narrow it relative to what instant, and why should that instant be trusted?*

Two candidate anchors were rejected on evidence:

- **A workflow-run timestamp.** `op=arm` run `30021969276` concluded `failure` **while the host
  was in fact armed** — G5 wrote `INNGEST_CUTOVER_FLIP=armed` and the G6 poll timed out at
  600 s, with Better Stack showing `flag:"done" reason:"noop-done" exit_code:0`. A run
  conclusion is not a state observation.
- **The operator-typed `CUTOVER_WINDOW_FROM` repo variable alone.** It is unvalidatable, never
  expires, and — decisively — is typed by a human on one clock while `startedAt` is stamped on
  another. An operator entering Europe/Paris local time in July (UTC+2) lands the bound
  **120 minutes** late, several times any workable margin. A single scalar also cannot express
  the seven `op=rearm` intervals dispatched across 2026-07-24 (10:46–15:54): coexistence was
  not one forward pass.

## Decision

**Anchor the doublefire scan window on the on-host flip-FSM transition row, and fail closed
when no anchor is derivable.**

```
anchor  = earliest flip-FSM TRANSITION row            # anchor_source=fsm
        | CUTOVER_WINDOW_FROM                          # anchor_source=var
        | (none) -> FAIL CLOSED, do not scan

DF_FROM = min( bucket_floor(anchor) − 2×cron_period , now − FALLBACK_DAYS )
FALLBACK_DAYS = 1
```

### 1. The anchor is a TRANSITION row, never "the earliest flip row"

This distinction *is* the correctness of the anchor, and it is not the obvious reading.

`inngest-cutover-flip` runs on a **~30-second on-host timer** and re-emits
`flag:"done" reason:"noop-done"` on **every tick** — ~2,880 rows/day. Measured 2026-07-24: a
400-row query spanned only **four hours** and was **100% `noop-done`**.

So "the earliest relevant flip row" — the natural phrasing, and the one this project's own
plan carried into implementation — resolves under any practical `--limit` to *a few hours
ago*, not to the cutover instant. That yields a window **narrower** than the coexistence
region: the unsafe direction, and precisely the vacuous "exactly-once VERIFIED" that AC-V3
exists to reject.

The emitter's `reason` vocabulary splits cleanly (`inngest-cutover-flip.sh`, `emit_state`):

| Class | Reasons |
|---|---|
| **Transition** (a real state change) | `flip-complete`, `flushed-resume-no-reflush`, `rolled-back`, `dbsize-nonzero`, `flushall-failed`, `refuse-rearm-after-done` |
| **Idempotent no-op** (every 30 s tick) | `noop-done`, `noop-rolled-back`, `noop-aborted`, `noop-unset` |

Measured against production: exactly **one** transition row exists
(`done/flip-complete` @ `2026-07-24 10:20:51Z`) against thousands of heartbeats.

Reasons are matched in their **quoted** form (`"reason":"rolled-back"`) because
`noop-rolled-back` *contains* the substring `rolled-back` — a bare substring grep would
re-admit the entire heartbeat firehose and silently reinstate the defect this section
describes.

### 2. Why this instant is trustworthy

The transition row is stamped on **10.0.1.40's journald — the same clock that stamps
`startedAt`** on the runs being bucketed. Anchor and data share a clock, which collapses the
operator-skew class entirely rather than bounding it.

### 3. `min()` is a skew clamp, not a safety net

An operator-supplied anchor can only ever **widen** the window, never narrow it below
`now − FALLBACK_DAYS`.

`FALLBACK_DAYS = 1`, **not** 7. A 7-day floor is ~5,100 runs ≈ 51 pages ≈ 214 s — not
exhaustible. Safety (a wide floor) and liveness (a window that finishes) are in direct
tension here, and the tension is resolved only by making the anchor *correct*, not by making
the fallback *wide*.

`bucket_floor(x) = ⌊x / cron_period⌋ × cron_period` is exact and self-documenting: it **is**
the boundary the downstream `group_by([.fn, .bucket])` uses. The additional `2×cron_period`
is straggler margin.

### 4. There is no safe wide fallback — an underivable anchor FAILS CLOSED

If neither the FSM row nor `CUTOVER_WINDOW_FROM` yields an instant, the arm refuses to scan.
Falling back to `now − 7d` would trade a deadline abort for a deadline abort **while looking
safer** — the probe emits nothing either way, so the operator learns strictly less.

### 5. Per-arm fallback

The fallback is passed as `$1`, never read from an ambient global defined ~900 lines away.
`op=doublefire-probe` — the **pre-cutover** dark-host detector — keeps its 200-day window and
makes no Better Stack call at all (no coexistence instant exists before the cutover).
Narrowing that arm too would have been a false-clean on this change's own stated harm.

### 6. Truncation refuses rather than under-covers

`betterstack-query.sh`'s `--limit` takes the **newest** N rows (inner `ORDER BY dt DESC`)
before re-sorting ascending. A **full page** therefore means the earliest transition may lie
beyond it, and the row selected would be *later* than truth — a narrower window. The deriver
refuses on a full page, so the caller falls through to a **wider** source, never a narrower
one.

### 7. `anchor_source` is part of the verdict, not decoration

`anchor_source ∈ {fsm, var, floor, wide}` is emitted to the run log and the probe's markers.
A clean verdict over a `var`-sourced or `floor`-clamped window is a materially weaker claim
than one over an `fsm`-anchored window; without the field that difference is invisible on an
otherwise-green run. It is a required input to AC-V3 (non-vacuity).

### 8. Companion: `totalCount` + a page-1 feasibility gate

The GraphQL query had **always** requested `totalCount`; nothing parsed it. The scan fetched
its own scale on every page and discarded it, which made "how many runs are in this window"
read as an inherent limit rather than a one-line omission. The probe now parses it on page 1
and refuses an unaffordable window in ~2 s with a **computed** latest-viable anchor derived
from observed density — so the next narrowing is measured, not extrapolated. (The first
extrapolation, from counting cron schedules in source, understated reality by ~2.7×.)

Pre-page-1 aborts report the enum `total_count=unknown`, **never `0`** — a `0` is
indistinguishable from a genuinely empty window, which is the false-clean shape the probe
exists to refuse.

## Consequences

**Positive.** `op=verify` can reach a verdict. Window width is now anchored on a measured,
same-clock instant. Every abort names an actionable, computed remediation. `anchor_source` +
`total_count` discriminate "window too wide" from "budget too small" from "anchored on the
wrong instant" in a single off-box event.

**Negative / accepted.**

- **Slow-cron missed-tick recall is reduced** until registry-sourced function discovery lands
  (§ Deferred). The double-fire verdict is unaffected — a function with no run in the window
  cannot have double-fired in it.
- **A new trust boundary:** the verdict's window now depends on Better Stack Logs retention.
  A retention miss degrades to `var`, then fails closed — never to a narrower window.
- **Cost grows with wall-clock.** The window is anchored but open-topped, so a `op=verify` run
  long after the cutover scans proportionally more. Bounded by the page-1 gate, which converts
  that into a fast abort naming a viable anchor rather than a silent 112 s failure.
- **ADR-100's status gate is a 7-day Phase-4 soak.** A `now`-relative floor discharges it only
  if `op=verify` runs within 7 days of the cutover. **This ADR does not claim to discharge it.**

## Deferred

1. **Registry-sourced missed-tick discovery.** After computing `registry_ids − observed`,
   issue a **second** doublefire-probe call scoped `function_ids=<zero-run set>` over a
   `2×max_cron_period` window. The `functionIDs` filter makes it cheap for the same reason
   ADR-106's `armed_reminders` query is cheap, restoring full slow-cron recall *and*
   dissolving the amplification risk. Requires extending `inngest-registry-probe.sh` to emit
   trigger type — ids alone cannot distinguish cron from event-driven functions.
   **Re-eval trigger:** before the next cutover that uses missed-tick enumeration.
2. **The missed-tick loop emits a command that does not exist**
   (`soleur:trigger-cron --function-id <UUID> --missed-tick <TS>`; the skill accepts
   `--event cron/<name>.manual-trigger`, and no UUID→name mapping exists anywhere). It also
   fires for any function with ≥1 run *anywhere* in the scan window, so post-cutover it emits
   re-fire lines for crons that were never due — and re-firing one causes the double-fire this
   cutover prevents. Interim de-fang: gate the per-bucket output behind a `workflow_dispatch`
   input defaulting **off**.
3. **`CUTOVER_REGISTRY_BASELINE` + `CUTOVER_QUIESCE_PROBES` env mapping + a completeness
   guard**, to land only *after* AC-V4 is green (mapping the baseline activates a dormant
   `exit 1` **upstream** of the doublefire check). The guard must anchor as
   `grep -oP '(?<![A-Za-z0-9_])CUTOVER_[A-Z_]+'` — an unanchored grep matches
   `CUTOVER_FLIP` / `CUTOVER_QUIESCE`, which are **Doppler secret names** on
   `soleur-inngest/prd` and must never enter the workflow env block.
4. **`INNGEST_GQL_PAGE_SIZE=500` is unmeasured.** 4.2 s/page for 100 rows is plausibly
   per-request overhead rather than row throughput, so a larger page could materially widen
   the affordable window. Not measured here: the doublefire hook plumbs only `from` and
   `function_ids`, so measuring it requires threading a new hook parameter and redeploying the
   host hook config — and it changes no decision in this change (the fsm-anchored window fits
   comfortably at `PAGE_SIZE=100`). Recorded as unmeasured with the reason, per the plan's own
   sanctioned path.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Flip run ordering to `DESC` | **Rejected.** `_pf_abort` emits nothing, so no sort order produces a verdict from a non-exhausting scan. Ordering is not causally decisive. |
| Raise `PREFLIGHT_DEADLINE_S` | **Rejected, measured.** The SUM bound caps it at 112 s ≈ 14 pages vs the ~1,456 needed. |
| Raise `INNGEST_GQL_PAGE_SIZE` | **Composable, unmeasured.** Deferred (§ Deferred 4) — it widens headroom but is not required for the anchored window to fit. |
| Scope `INNGEST_DOUBLEFIRE_FUNCTION_IDS` as the primary lever | **Rejected as primary.** Fits the budget only by dropping the high-frequency crons most at risk. Retained as a documented cost lever. |
| Bound the window with `until=` | **Rejected.** Cuts out the highest-risk region (post-repoint, post-rollback) while looking like a symmetric tidy-up. Recorded as an invariant with a test. |
| Keep the operator-typed repo variable as the safety anchor | **Rejected at this threshold.** Unvalidatable, never expires, wrong clock, and a single scalar cannot express seven re-arm intervals. |
| Anchor on the `op=arm` workflow-run timestamp | **Rejected on evidence.** Run `30021969276` concluded `failure` while the host was armed. |
| Close #6178 on healthy-cutover signals | **Rejected.** FSM `done`, 68/68 registry, and a single scheduler are real signals but are not an exactly-once proof. |
