---
module: scripts/followthroughs/web2-plugin-seed-8743.sh
date: 2026-10-21
problem_type: integration_issue
component: tooling
symptoms:
  - "Better Stack soak probe exited 2 (NOT YET) on every sweeper run — the tracker could never grade"
  - "ClickHouse returned HTTP 400 Code: 6 on the absence-window query"
  - "first_marker_dt rendered with microseconds ('2026-10-21 03:26:45.242796') but the query fed it to toDateTime()"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
tags: [clickhouse, datetime64, followthrough, betterstack, soak-probe]
---

# Troubleshooting: ClickHouse `toDateTime()` rejects a DateTime64 microsecond literal — followthrough probe stuck at NOT YET

## Problem

The #8743 Better Stack soak probe (`scripts/followthroughs/web2-plugin-seed-8743.sh`) could never grade: its absence-window query embedded the DateTime64 `first_marker_dt` literal into `toDateTime()`, ClickHouse rejected the microsecond fraction with Code 6 (HTTP 400), the probe exited 2 `NOT YET` on every sweep, and the tracker stayed open indefinitely.

## Environment

- Module: scripts/followthroughs/ soak probes (sweep-followthroughs.sh fleet)
- Affected Component: followthrough probe SQL generation (bash + ClickHouse HTTP API)
- Date: 2026-10-21

## Symptoms

- Sweeper output `NOT YET` on every run, indistinguishable from "soak still in progress"
- ClickHouse Code: 6 — `toDateTime` cannot parse a literal carrying a fractional-seconds part
- Exit 2 masked the 400 as a probe verdict rather than a probe failure

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt (test-first: a stub-side ClickHouse Code-6 strictness arm + a fractional-marker PASS case pinned the defect before the fix).

## Solution

Parse the marker with `toDateTime64` at the column's precision and an explicit timezone, per the codebase's naive-literal convention:

```bash
# Before (broken — Code: 6, HTTP 400 on any microseconds literal):
WHERE dt >= toDateTime('${first_marker_dt}')

# After (CTO-ruled):
WHERE dt >= toDateTime64('${first_marker_dt}', 6, 'UTC')
```

Two load-bearing details:

1. **`toDateTime64(lit, 6)` over a bash fraction-strip** (`${first_marker_dt%%.*}`): stripping floors the absence boundary and can false-FAIL on a pre-marker row in the same second; a strict parse fails loud (exit 2) on unexpected shapes instead.
2. **Explicit `'UTC'`** matches the column's `DateTime64(6,'UTC')` declaration. Both prior naive-literal parse sites pin `'UTC'` (`registry-clientip-alert-7530.sh:473`, `inngest-provision-rehearsal-capture.sh:211,501`); without it the literal parses in the session TZ and silently shifts the grading boundary.

Companion change: the defensive shape gate on `first_marker_dt` was anchored from `^[0-9]{4}-[0-9]{2}-[0-9]{2}` to the full `YYYY-MM-DD HH:MM:SS[.ffffff]` form so a decode failure still exits `not_yet 2` rather than reaching ClickHouse.

## Prevention

- The test suite gained (a) a Code-6 strictness stub arm that asserts the probe never emits a literal ClickHouse rejects, and (b) a calls-log pin asserting the absence query uses `toDateTime64` — the anti-vacuity floor moved 17→19.
- Convention for followthrough SQL: when a timestamp variable derives from a `DateTime64` column, embed it via `toDateTime64(lit, 6, 'UTC')`, never `toDateTime()`; a plan-time sibling sweep confirmed `web2-plugin-seed-8743.sh` was the only `toDateTime('<variable-timestamp>')` fed by a dt-derived value.
