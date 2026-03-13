---
title: "feat: improve weekly analytics for CMO consumption"
type: feat
date: 2026-03-13
semver: patch
---

# Improve Weekly Analytics for CMO Consumption

## Overview

Enhance `scripts/weekly-analytics.sh` and its CI workflow to auto-detect growth phases, maintain a rolling trend summary, and send Discord alerts when WoW visitor growth misses the phase target. These three additions close the feedback loop between weekly snapshots and the CMO agent's ability to assess marketing performance without reading multiple files.

## Problem Statement / Motivation

The weekly analytics snapshot (shipped in #575) generates isolated per-week markdown files. Three gaps limit CMO consumption:

1. **Hardcoded phase detection.** `CURRENT_PHASE` and `CURRENT_TARGET` are string literals at line 31-32 of `scripts/weekly-analytics.sh`. Phase transitions (Phase 1 -> 2 -> 3) require a manual edit. The phase schedule is already defined in `knowledge-base/marketing/marketing-strategy.md` (lines 335-339) with concrete date ranges.

2. **No trend aggregation.** Each snapshot is a standalone file. Seeing WoW trends across weeks requires reading and diffing multiple files. A rolling `trend-summary.md` that appends each week's key metrics into a single table eliminates this.

3. **No KPI miss alerting.** The existing Discord webhook only fires on workflow *failures* (API errors, script crashes). If WoW visitor growth drops below the phase target, there is no proactive notification. The CMO only discovers misses during weekly review -- too late for mid-week course corrections.

## Proposed Solution

Three changes to the existing script and workflow, all backward-compatible with the current snapshot format.

### Change 1: Phase Auto-Detection (`scripts/weekly-analytics.sh`)

Replace the hardcoded `CURRENT_PHASE` and `CURRENT_TARGET` variables with a `detect_phase()` function that:

1. Defines phase boundaries as date ranges in a config block at the top of the script (matching `marketing-strategy.md` lines 335-339):
   - Phase 1: 2026-03-13 to 2026-04-10, target +15%
   - Phase 2: 2026-04-11 to 2026-05-09, target +10%
   - Phase 3: 2026-05-10 to 2026-07-04, target +7%
2. Compares `SNAPSHOT_DATE` against each range using `date +%s` epoch comparison
3. Falls back to "Post-Phase 3" with no target after 2026-07-04
4. Sets `CURRENT_PHASE` and `CURRENT_TARGET` dynamically

**Design decision -- config in script vs. parsing marketing-strategy.md:** Embedding the phase config directly in the script is more robust than parsing a markdown table at runtime. The phase schedule changes at most quarterly and the script is the source of truth for phase detection. If the strategy doc changes, the script config block is updated in the same PR.

**Date arithmetic:** Use GNU `date -d` with epoch seconds for comparison. The script already uses `date -d` at line 145. macOS fallback with `-v` is maintained but secondary (CI runs on `ubuntu-latest`).

### Change 2: Trend Summary Append (`scripts/weekly-analytics.sh`)

After writing the individual snapshot file, append a row to `knowledge-base/marketing/analytics/trend-summary.md`:

1. If the file does not exist, create it with a header row:
   ```
   # Weekly Analytics Trend Summary

   | Week | Date | Visitors | WoW % | Target % | Status |
   |------|------|----------|-------|----------|--------|
   ```
2. Append a row with the current week's data:
   - **Week**: Calculate week number as `((SNAPSHOT_DATE - Phase1_start) / 7) + 1`
   - **Date**: `SNAPSHOT_DATE`
   - **Visitors**: `VISITORS` value from API
   - **WoW %**: `VISITORS_DELTA` (already computed)
   - **Target %**: `CURRENT_TARGET` (from auto-detection)
   - **Status**: Compare numeric WoW against numeric target. "on-track" if WoW >= target, "below-target" otherwise
3. Guard against duplicate rows: check if `SNAPSHOT_DATE` already exists in the file before appending (idempotency for re-runs)

**Numeric comparison:** The `VISITORS_CHANGE` value from Plausible is already a numeric integer (e.g., `156` for +156%). The `CURRENT_TARGET` is stored as an integer (e.g., `15` for +15%). Compare directly with bash arithmetic `[[ "$VISITORS_CHANGE" -ge "$target_numeric" ]]`.

### Change 3: KPI Miss Alert (`scripts/weekly-analytics.sh` + workflow)

Add a conditional Discord notification when actual WoW visitor growth falls below the phase target:

1. **In the script:** After computing `VISITORS_CHANGE` and `CURRENT_TARGET`, compare them. If below target, write a signal file (e.g., `/tmp/kpi-miss-signal`) containing the miss details (actual %, target %, phase name). Exit code remains 0 -- a KPI miss is not a script failure.
2. **In the workflow:** Add a new step after "Generate analytics snapshot" that checks for the signal file and sends a Discord alert if present.

**Why a signal file instead of exit code?** A KPI miss is informational, not a failure. Using a non-zero exit code would trigger the existing failure notification (duplicate alerts) and prevent the snapshot from being committed. A signal file decouples the notification from the script's success/failure semantics.

**Discord payload format:**

```json
{
  "content": "**Weekly Analytics: KPI Miss**\n\nPhase: Phase 1: Content Traction\nTarget: +15% WoW\nActual: +5% WoW\nVisitors: 23\n\nSnapshot: <link-to-file>",
  "username": "Sol",
  "avatar_url": "<logo-url>",
  "allowed_mentions": {"parse": []}
}
```

**Edge cases:**
- First week (no previous period data): `VISITORS_CHANGE` may be empty or null. Skip the alert if change data is unavailable. First-week snapshots have no meaningful WoW comparison.
- Post-Phase 3 (no target): Skip the alert. No target means no miss.
- N/A change values: Skip the alert. Cannot compare against target.

## Technical Considerations

- **Backward compatibility:** The individual snapshot format is unchanged. The trend summary and KPI alert are additive. Existing snapshots continue to work.
- **Idempotency:** Trend summary append checks for existing date before adding a row. Re-running the workflow for the same week does not duplicate data.
- **Signal file path:** Use `GITHUB_WORKSPACE` if available, otherwise `/tmp`. The signal file is ephemeral (workflow step boundary only).
- **Shell script learnings:** Apply patterns from `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`: validate inputs, use `trap` for cleanup, include `else` cases in dispatchers. The existing `api_get()` function pattern is retained (no refactoring scope).
- **Trend summary git add:** The workflow's `git add knowledge-base/marketing/analytics/` already covers the new `trend-summary.md` since it is in the same directory.
- **Discord webhook reuse:** The `DISCORD_WEBHOOK_URL` secret is already configured for the failure notification step. The KPI miss step reuses the same secret.
- **Week number calculation:** Week numbers are 1-indexed from the Phase 1 start date (2026-03-13). This gives continuous numbering across phases (Week 1-4 = Phase 1, Week 5-8 = Phase 2, etc.).

## Acceptance Criteria

- [ ] `detect_phase()` function in `scripts/weekly-analytics.sh` returns correct phase and target for dates in each phase range and post-Phase 3
- [ ] `CURRENT_PHASE` and `CURRENT_TARGET` are no longer hardcoded string literals
- [ ] `trend-summary.md` is created on first run with header and first data row
- [ ] `trend-summary.md` appends a row on subsequent runs without duplicating existing rows
- [ ] Trend summary row contains: Week number, Date, Visitors, WoW %, Target %, Status (on-track/below-target)
- [ ] Discord KPI miss alert fires when actual WoW % < phase target %
- [ ] KPI miss alert does NOT fire when WoW % >= target, when change data is N/A, or when post-Phase 3
- [ ] KPI miss alert is distinct from the existing failure notification (different message, same webhook)
- [ ] Existing snapshot markdown format is unchanged
- [ ] Script exits 0 on KPI miss (miss is informational, not a failure)
- [ ] `set -euo pipefail` compliance maintained (no unguarded variables, no bare greps in pipelines)

## Test Scenarios

- Given the date is 2026-03-20 (Phase 1), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 1: Content Traction" and `CURRENT_TARGET` is "+15%"
- Given the date is 2026-04-15 (Phase 2), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 2: Content Velocity" and `CURRENT_TARGET` is "+10%"
- Given the date is 2026-05-15 (Phase 3), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 3: Organic Growth" and `CURRENT_TARGET` is "+7%"
- Given the date is 2026-07-10 (post-Phase 3), when `detect_phase()` runs, then `CURRENT_PHASE` is "Post-Phase 3" and `CURRENT_TARGET` is empty
- Given `trend-summary.md` does not exist, when the script runs, then the file is created with a header and one data row
- Given `trend-summary.md` exists with prior rows, when the script runs with a new date, then one row is appended
- Given `trend-summary.md` already contains today's date, when the script runs again, then no duplicate row is added
- Given WoW visitor change is +5% and phase target is +15%, when the script completes, then a KPI miss signal file is written
- Given WoW visitor change is +20% and phase target is +15%, when the script completes, then no KPI miss signal file is written
- Given the KPI miss signal file exists, when the workflow runs the alert step, then a Discord notification is sent with phase, target, and actual values
- Given VISITORS_CHANGE is empty (first week, no comparison data), when the KPI check runs, then no alert is sent
- Given the phase is post-Phase 3, when the KPI check runs, then no alert is sent (no target to miss)

## Non-Goals

- **Refactoring `api_get()` into `api_request()`**: The existing function works and is not duplicated. The learnings doc recommends the pattern for new scripts, not retrofitting existing ones.
- **Parsing `marketing-strategy.md` at runtime**: The phase config is embedded in the script. Runtime markdown parsing is fragile and unnecessary for a quarterly-changing config.
- **Adding new Plausible API calls**: The three existing calls (aggregate, pages breakdown, sources breakdown) are sufficient. No new metrics.
- **Alerting on absolute visitor thresholds**: Only WoW percentage growth is compared. Absolute targets (100/week by week 4) are assessed during manual weekly review.
- **Historical backfill of trend-summary.md**: The first row is whatever week this ships. No retroactive data population.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| GNU `date` epoch comparison fails on macOS | CI runs on `ubuntu-latest`. macOS fallback maintained for local testing but not required for CI. |
| Phase config in script drifts from marketing-strategy.md | Both are updated in the same PR when phases change. Constitution.md documents this coupling. |
| Discord webhook not configured | KPI alert step checks for empty `DISCORD_WEBHOOK_URL` and skips gracefully (matches existing failure notification pattern). |
| Trend summary file corruption (partial write) | Append is atomic at the filesystem level for single-line writes. `>>` operator on ext4 is safe for single lines. |
| First-week N/A change triggers false miss alert | Explicit guard: skip KPI check when `VISITORS_CHANGE` is empty or "null". |

## Files Modified

| File | Change |
|------|--------|
| `scripts/weekly-analytics.sh` | Add `detect_phase()`, trend summary append, KPI miss signal logic |
| `.github/workflows/scheduled-weekly-analytics.yml` | Add KPI miss Discord alert step |
| `knowledge-base/marketing/analytics/trend-summary.md` | Created on first run (not committed in this PR -- generated by CI) |

## References

- Parent issue: #594
- Snapshot script: `scripts/weekly-analytics.sh`
- Workflow: `.github/workflows/scheduled-weekly-analytics.yml`
- Growth targets: `knowledge-base/marketing/marketing-strategy.md` (lines 331-341)
- First snapshot: `knowledge-base/marketing/analytics/2026-03-13-weekly-analytics.md`
- Original plan: `knowledge-base/project/plans/2026-03-13-feat-plausible-analytics-operationalization-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-plausible-goals-api-provisioning-hardening.md`
