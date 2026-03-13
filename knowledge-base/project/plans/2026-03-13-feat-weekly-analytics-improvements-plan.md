---
title: "feat: improve weekly analytics for CMO consumption"
type: feat
date: 2026-03-13
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 7
**Research sources:** shell-script-defensive-patterns learning, set-euo-pipefail-upgrade-pitfalls learning, shell-api-wrapper-hardening-patterns learning, discord-bot-identity-and-webhook-behavior learning, github-actions-auto-push-vs-pr learning, plausible-analytics-operationalization-pattern learning, bash-operator-precedence learning, GitHub Actions GITHUB_OUTPUT docs, Baeldung epoch arithmetic guide

### Key Improvements

1. Replace signal file with `GITHUB_OUTPUT` -- the canonical GitHub Actions inter-step communication pattern, eliminating filesystem cleanup and path portability concerns
2. Add concrete `detect_phase()` implementation with epoch arithmetic and `set -euo pipefail` compliance guards
3. Add week number calculation fix -- must divide epoch seconds by `(7 * 86400)`, not by `7`
4. Add `grep` idempotency guard with `|| true` to prevent `set -o pipefail` abort when trend file has no matching date
5. Add boundary date test scenarios for phase transitions (Apr 10 vs Apr 11, May 9 vs May 10)
6. Add pre-Phase 1 edge case (date before 2026-03-13) to `detect_phase()` handling

### New Considerations Discovered

- `GITHUB_OUTPUT` is preferred over signal files for inter-step communication in GitHub Actions -- avoids path portability issues and filesystem cleanup
- `grep` inside command substitution aborts the script under `set -o pipefail` when no match is found -- the idempotency check for trend-summary.md must use `|| true`
- Phase boundary dates (last day of Phase 1 vs first day of Phase 2) need inclusive/exclusive range clarity to avoid off-by-one errors
- Negative `VISITORS_CHANGE` values (traffic drop) are handled correctly by bash arithmetic `-ge` comparison -- no special case needed
- The `detect_phase()` function should use `local` for all variables to comply with constitution shell conventions

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
   - Phase 1: 2026-03-13 to 2026-04-10 (inclusive), target +15%
   - Phase 2: 2026-04-11 to 2026-05-09 (inclusive), target +10%
   - Phase 3: 2026-05-10 to 2026-07-04 (inclusive), target +7%
2. Compares `SNAPSHOT_DATE` against each range using `date +%s` epoch comparison
3. Falls back to "Post-Phase 3" with no target after 2026-07-04
4. Falls back to "Pre-Phase 1" with no target before 2026-03-13
5. Sets `CURRENT_PHASE` and `CURRENT_TARGET` dynamically

**Design decision -- config in script vs. parsing marketing-strategy.md:** Embedding the phase config directly in the script is more robust than parsing a markdown table at runtime. The phase schedule changes at most quarterly and the script is the source of truth for phase detection. If the strategy doc changes, the script config block is updated in the same PR.

**Date arithmetic:** Use GNU `date -d` with epoch seconds for comparison. The script already uses `date -d` at line 145. macOS fallback with `-v` is maintained but secondary (CI runs on `ubuntu-latest`).

### Research Insights: Phase Auto-Detection

**Implementation pattern:**

```bash
# --- Phase Configuration ---
# Source of truth: knowledge-base/marketing/marketing-strategy.md lines 335-339
# Update both files in the same PR when phases change.
PHASE1_START="2026-03-13"
PHASE1_END="2026-04-10"
PHASE1_NAME="Phase 1: Content Traction"
PHASE1_TARGET=15

PHASE2_START="2026-04-11"
PHASE2_END="2026-05-09"
PHASE2_NAME="Phase 2: Content Velocity"
PHASE2_TARGET=10

PHASE3_START="2026-05-10"
PHASE3_END="2026-07-04"
PHASE3_NAME="Phase 3: Organic Growth"
PHASE3_TARGET=7

detect_phase() {
  local snapshot_date="$1"
  local snapshot_epoch
  snapshot_epoch=$(date -u -d "$snapshot_date" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$snapshot_date" +%s 2>/dev/null)

  local p1_start_epoch p1_end_epoch p2_start_epoch p2_end_epoch p3_start_epoch p3_end_epoch
  p1_start_epoch=$(date -u -d "$PHASE1_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_START" +%s 2>/dev/null)
  p1_end_epoch=$(date -u -d "$PHASE1_END" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE1_END" +%s 2>/dev/null)
  p2_start_epoch=$(date -u -d "$PHASE2_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE2_START" +%s 2>/dev/null)
  p2_end_epoch=$(date -u -d "$PHASE2_END" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE2_END" +%s 2>/dev/null)
  p3_start_epoch=$(date -u -d "$PHASE3_START" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE3_START" +%s 2>/dev/null)
  p3_end_epoch=$(date -u -d "$PHASE3_END" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$PHASE3_END" +%s 2>/dev/null)

  if [[ "$snapshot_epoch" -lt "$p1_start_epoch" ]]; then
    CURRENT_PHASE="Pre-Phase 1"
    CURRENT_TARGET=""
    TARGET_NUMERIC=""
  elif [[ "$snapshot_epoch" -le "$p1_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE1_NAME"
    CURRENT_TARGET="+${PHASE1_TARGET}%"
    TARGET_NUMERIC="$PHASE1_TARGET"
  elif [[ "$snapshot_epoch" -le "$p2_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE2_NAME"
    CURRENT_TARGET="+${PHASE2_TARGET}%"
    TARGET_NUMERIC="$PHASE2_TARGET"
  elif [[ "$snapshot_epoch" -le "$p3_end_epoch" ]]; then
    CURRENT_PHASE="$PHASE3_NAME"
    CURRENT_TARGET="+${PHASE3_TARGET}%"
    TARGET_NUMERIC="$PHASE3_TARGET"
  else
    CURRENT_PHASE="Post-Phase 3"
    CURRENT_TARGET=""
    TARGET_NUMERIC=""
  fi
}
```

**`set -euo pipefail` compliance notes** (from learning `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`):

- All variables inside `detect_phase()` use `local` declarations per constitution shell conventions
- The `date` fallback chain uses `2>/dev/null || date ...` which is safe -- the `||` short-circuits, and the overall command substitution succeeds if either branch succeeds
- `TARGET_NUMERIC` is set as a global alongside `CURRENT_PHASE` and `CURRENT_TARGET` since the caller needs it for KPI comparison
- No `grep` in pipelines, no bare positional args -- clean for strict mode

**Boundary date clarity:**

- Phase ranges are **inclusive on both ends** (Phase 1 ends Apr 10, Phase 2 starts Apr 11)
- Using `-le` (less-than-or-equal) for end dates ensures the last day of each phase is correctly classified
- The gap between phases is handled by ordering: if not in Phase 1 range (`<= p1_end`), check Phase 2 (`<= p2_end`), etc. Since Phase 2 starts the day after Phase 1 ends, there is no gap

### Change 2: Trend Summary Append (`scripts/weekly-analytics.sh`)

After writing the individual snapshot file, append a row to `knowledge-base/marketing/analytics/trend-summary.md`:

1. If the file does not exist, create it with a header row:
   ```markdown
   # Weekly Analytics Trend Summary

   | Week | Date | Visitors | WoW % | Target % | Status |
   |------|------|----------|-------|----------|--------|
   ```
2. Append a row with the current week's data:
   - **Week**: Calculate week number as `((snapshot_epoch - phase1_start_epoch) / SECONDS_PER_WEEK) + 1`
   - **Date**: `SNAPSHOT_DATE`
   - **Visitors**: `VISITORS` value from API
   - **WoW %**: `VISITORS_DELTA` (already computed)
   - **Target %**: `CURRENT_TARGET` (from auto-detection)
   - **Status**: Compare numeric WoW against numeric target. "on-track" if WoW >= target, "below-target" otherwise
3. Guard against duplicate rows: check if `SNAPSHOT_DATE` already exists in the file before appending (idempotency for re-runs)

**Numeric comparison:** The `VISITORS_CHANGE` value from Plausible is already a numeric integer (e.g., `156` for +156%). The `CURRENT_TARGET` is stored as an integer (e.g., `15` for +15%). Compare directly with bash arithmetic `[[ "$VISITORS_CHANGE" -ge "$TARGET_NUMERIC" ]]`.

### Research Insights: Trend Summary

**Week number calculation fix:**

The original plan stated `((SNAPSHOT_DATE - Phase1_start) / 7) + 1` -- this is incorrect if using epoch seconds. The correct formula divides by seconds per week:

```bash
SECONDS_PER_WEEK=$((7 * 86_400))
week_number=$(( (snapshot_epoch - p1_start_epoch) / SECONDS_PER_WEEK + 1 ))
```

Using the `86_400` literal with underscore separator per constitution convention (line 59: "Prefer numeric literal underscores as thousand separators").

**Idempotency guard with `set -o pipefail` compliance** (from learning `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`):

```bash
# WRONG -- grep exits 1 on no match, pipefail propagates, script aborts
if grep -q "$SNAPSHOT_DATE" "$TREND_FILE"; then

# CORRECT -- || true prevents pipefail abort on no match
if grep -q "$SNAPSHOT_DATE" "$TREND_FILE" 2>/dev/null; then
```

Note: `grep -q` does not participate in a pipeline (no `|`), so `pipefail` does not apply here. However, under `set -e`, `grep -q` returning exit 1 (no match) would abort the script if not inside an `if` conditional. Using it as the `if` condition is the correct pattern -- the `if` statement suppresses `errexit` for its condition command. No `|| true` needed when `grep` is the `if` condition itself.

**Status determination implementation:**

```bash
determine_status() {
  local wow_change="${1:-}"
  local target="${2:-}"

  # No target (pre/post-phase) or no change data: cannot determine
  if [[ -z "$target" || -z "$wow_change" || "$wow_change" == "null" ]]; then
    echo "N/A"
    return
  fi

  if [[ "$wow_change" -ge "$target" ]]; then
    echo "on-track"
  else
    echo "below-target"
  fi
}
```

**Edge case -- negative WoW values:** `VISITORS_CHANGE` can be negative (e.g., `-50` for a 50% drop). Bash arithmetic `-ge` handles negative integers correctly, so `-50 -ge 15` evaluates to false. No special case needed.

### Change 3: KPI Miss Alert (`scripts/weekly-analytics.sh` + workflow)

Add a conditional Discord notification when actual WoW visitor growth falls below the phase target:

1. **In the script:** After computing `VISITORS_CHANGE` and `TARGET_NUMERIC`, compare them. If below target, write the KPI miss details to `GITHUB_OUTPUT` for the workflow to consume. Exit code remains 0 -- a KPI miss is not a script failure.
2. **In the workflow:** Add a new step after "Generate analytics snapshot" that reads the step output and sends a Discord alert if a miss was detected.

**Why `GITHUB_OUTPUT` instead of a signal file?** [Updated 2026-03-13] The original plan proposed a `/tmp/kpi-miss-signal` file. Research into [GitHub Actions workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands) reveals that `GITHUB_OUTPUT` is the canonical mechanism for inter-step communication:

- No filesystem path portability concerns (`$GITHUB_WORKSPACE` vs `/tmp`)
- No cleanup needed (GitHub manages the file lifecycle)
- Outputs are visible in the workflow UI for debugging
- The step must have an `id` field to enable output access

**Implementation pattern:**

In the script, write to `GITHUB_OUTPUT` if the environment variable exists (CI), otherwise write to stdout (local testing):

```bash
# --- KPI Miss Detection ---

emit_kpi_status() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

if [[ -n "$TARGET_NUMERIC" && -n "${VISITORS_CHANGE:-}" && "${VISITORS_CHANGE}" != "null" ]]; then
  if [[ "$VISITORS_CHANGE" -lt "$TARGET_NUMERIC" ]]; then
    emit_kpi_status "kpi_miss" "true"
    emit_kpi_status "kpi_phase" "$CURRENT_PHASE"
    emit_kpi_status "kpi_target" "$CURRENT_TARGET"
    emit_kpi_status "kpi_actual" "$VISITORS_DELTA"
    emit_kpi_status "kpi_visitors" "${VISITORS:-0}"
    echo "KPI miss detected: ${CURRENT_PHASE} target ${CURRENT_TARGET} WoW, actual ${VISITORS_DELTA}" >&2
  else
    emit_kpi_status "kpi_miss" "false"
  fi
else
  emit_kpi_status "kpi_miss" "false"
fi
```

In the workflow, add the step with an `id` on the script step and a conditional alert step:

```yaml
      - name: Generate analytics snapshot
        id: analytics
        env:
          PLAUSIBLE_API_KEY: ${{ secrets.PLAUSIBLE_API_KEY }}
          PLAUSIBLE_SITE_ID: ${{ secrets.PLAUSIBLE_SITE_ID }}
        run: bash scripts/weekly-analytics.sh

      - name: Discord notification (KPI miss)
        if: steps.analytics.outputs.kpi_miss == 'true'
        env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
        run: |
          if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
            echo "DISCORD_WEBHOOK_URL not set, skipping KPI miss notification"
            exit 0
          fi
          PHASE="${{ steps.analytics.outputs.kpi_phase }}"
          TARGET="${{ steps.analytics.outputs.kpi_target }}"
          ACTUAL="${{ steps.analytics.outputs.kpi_actual }}"
          VISITORS="${{ steps.analytics.outputs.kpi_visitors }}"
          REPO_URL="${{ github.server_url }}/${{ github.repository }}"
          MESSAGE=$(printf '**Weekly Analytics: KPI Miss**\n\nPhase: %s\nTarget: %s WoW\nActual: %s WoW\nVisitors: %s\n\nDashboard: %s/tree/main/knowledge-base/marketing/analytics' \
            "$PHASE" "$TARGET" "$ACTUAL" "$VISITORS" "$REPO_URL")
          PAYLOAD=$(jq -n \
            --arg content "$MESSAGE" \
            --arg username "Sol" \
            --arg avatar_url "https://raw.githubusercontent.com/jikig-ai/soleur/main/plugins/soleur/docs/images/logo-mark-512.png" \
            '{content: $content, username: $username, avatar_url: $avatar_url, allowed_mentions: {parse: []}}')
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "$DISCORD_WEBHOOK_URL")
          if [[ "$HTTP_CODE" =~ ^2 ]]; then
            echo "Discord KPI miss notification sent (HTTP $HTTP_CODE)"
          else
            echo "::warning::Discord KPI miss notification failed (HTTP $HTTP_CODE)"
          fi
```

### Research Insights: KPI Miss Alert

**Discord webhook compliance** (from learnings):

- `allowed_mentions: {parse: []}` prevents mention injection (learning `2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`)
- Explicit `username` and `avatar_url` fields per constitution line 96 and learning `2026-02-19-discord-bot-identity-and-webhook-behavior.md`
- Uses `jq -n` for payload construction to avoid shell escaping issues with embedded newlines
- `curl` stderr is not suppressed here since no auth header is in the URL (webhook URL contains the token in the path, not in headers) -- but the URL itself is in `$DISCORD_WEBHOOK_URL` which is never printed

**Security consideration:** The KPI miss alert step uses `${{ steps.analytics.outputs.kpi_phase }}` etc. in shell variables. These values originate from the script's own output (not user input), so injection risk is minimal. However, wrapping in quotes and using `jq --arg` for the final payload provides defense-in-depth.

**`if:` condition on the step** ensures the Discord API call is never attempted when there is no miss, avoiding unnecessary webhook noise and rate limit consumption.

## Technical Considerations

- **Backward compatibility:** The individual snapshot format is unchanged. The trend summary and KPI alert are additive. Existing snapshots continue to work.
- **Idempotency:** Trend summary append checks for existing date before adding a row. Re-running the workflow for the same week does not duplicate data.
- **Inter-step communication:** Uses `GITHUB_OUTPUT` (the canonical GitHub Actions mechanism) instead of signal files. The script step needs an `id: analytics` field in the workflow YAML.
- **Shell script learnings:** Apply patterns from `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`: validate inputs, use `trap` for cleanup, include `else` cases in dispatchers. The existing `api_get()` function pattern is retained (no refactoring scope).
- **`set -euo pipefail` compliance** (from learning `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`): All new functions use `local` variable declarations. `grep` for idempotency is inside an `if` conditional (suppresses errexit). No bare positional args in new functions. No `grep` in pipelines with command substitution.
- **Trend summary git add:** The workflow's `git add knowledge-base/marketing/analytics/` already covers the new `trend-summary.md` since it is in the same directory.
- **Discord webhook reuse:** The `DISCORD_WEBHOOK_URL` secret is already configured for the failure notification step. The KPI miss step reuses the same secret.
- **Week number calculation:** Week numbers are 1-indexed from the Phase 1 start date (2026-03-13). Uses epoch seconds divided by `(7 * 86_400)` for correct day-based arithmetic. This gives continuous numbering across phases (Week 1-4 = Phase 1, Week 5-8 = Phase 2, etc.).
- **Bash operator precedence** (from learning `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`): Any `|| true` in chained `&&` commands must use `{ ...; }` grouping to prevent catching failures from earlier commands. The proposed implementation avoids this pattern entirely by using `if/elif/else` instead of `&&/||` chains.

## Acceptance Criteria

- [x] `detect_phase()` function in `scripts/weekly-analytics.sh` returns correct phase and target for dates in each phase range, pre-Phase 1, and post-Phase 3
- [x] `CURRENT_PHASE` and `CURRENT_TARGET` are no longer hardcoded string literals
- [x] `trend-summary.md` is created on first run with header and first data row
- [x] `trend-summary.md` appends a row on subsequent runs without duplicating existing rows
- [x] Trend summary row contains: Week number, Date, Visitors, WoW %, Target %, Status (on-track/below-target/N/A)
- [x] KPI miss status written to `GITHUB_OUTPUT` when actual WoW % < phase target %
- [x] KPI miss output is `false` when WoW % >= target, when change data is N/A, or when pre/post-phase
- [x] Discord KPI miss alert fires via workflow step conditional on `steps.analytics.outputs.kpi_miss == 'true'`
- [x] KPI miss alert is distinct from the existing failure notification (different message, same webhook)
- [x] Existing snapshot markdown format is unchanged
- [x] Script exits 0 on KPI miss (miss is informational, not a failure)
- [x] `set -euo pipefail` compliance maintained (no unguarded variables, no bare greps in pipelines)
- [x] All new functions use `local` variable declarations per constitution shell conventions
- [x] Week number calculation uses epoch seconds divided by `(7 * 86400)`, not bare `7`

## Test Scenarios

- Given the date is 2026-03-20 (Phase 1), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 1: Content Traction" and `CURRENT_TARGET` is "+15%"
- Given the date is 2026-04-10 (last day of Phase 1), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 1: Content Traction" (boundary inclusive)
- Given the date is 2026-04-11 (first day of Phase 2), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 2: Content Velocity"
- Given the date is 2026-04-15 (Phase 2), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 2: Content Velocity" and `CURRENT_TARGET` is "+10%"
- Given the date is 2026-05-09 (last day of Phase 2), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 2: Content Velocity" (boundary inclusive)
- Given the date is 2026-05-10 (first day of Phase 3), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 3: Organic Growth"
- Given the date is 2026-05-15 (Phase 3), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 3: Organic Growth" and `CURRENT_TARGET` is "+7%"
- Given the date is 2026-07-04 (last day of Phase 3), when `detect_phase()` runs, then `CURRENT_PHASE` is "Phase 3: Organic Growth" (boundary inclusive)
- Given the date is 2026-07-05 (post-Phase 3), when `detect_phase()` runs, then `CURRENT_PHASE` is "Post-Phase 3" and `CURRENT_TARGET` is empty
- Given the date is 2026-03-12 (pre-Phase 1), when `detect_phase()` runs, then `CURRENT_PHASE` is "Pre-Phase 1" and `CURRENT_TARGET` is empty
- Given `trend-summary.md` does not exist, when the script runs, then the file is created with a header and one data row
- Given `trend-summary.md` exists with prior rows, when the script runs with a new date, then one row is appended
- Given `trend-summary.md` already contains today's date, when the script runs again, then no duplicate row is added
- Given WoW visitor change is +5% and phase target is +15%, when the script completes, then `kpi_miss=true` is written to GITHUB_OUTPUT
- Given WoW visitor change is +20% and phase target is +15%, when the script completes, then `kpi_miss=false` is written to GITHUB_OUTPUT
- Given WoW visitor change is -50% (traffic drop) and phase target is +15%, when the script completes, then `kpi_miss=true` is written to GITHUB_OUTPUT
- Given the KPI miss output is `true`, when the workflow runs the alert step, then a Discord notification is sent with phase, target, and actual values
- Given VISITORS_CHANGE is empty (first week, no comparison data), when the KPI check runs, then `kpi_miss=false` (no alert)
- Given the phase is post-Phase 3, when the KPI check runs, then `kpi_miss=false` (no target to miss)
- Given DISCORD_WEBHOOK_URL is empty, when the KPI miss alert step runs, then it skips gracefully with exit 0

## Non-Goals

- **Refactoring `api_get()` into `api_request()`**: The existing function works and is not duplicated. The learnings doc recommends the pattern for new scripts, not retrofitting existing ones.
- **Parsing `marketing-strategy.md` at runtime**: The phase config is embedded in the script. Runtime markdown parsing is fragile and unnecessary for a quarterly-changing config.
- **Adding new Plausible API calls**: The three existing calls (aggregate, pages breakdown, sources breakdown) are sufficient. No new metrics.
- **Alerting on absolute visitor thresholds**: Only WoW percentage growth is compared. Absolute targets (100/week by week 4) are assessed during manual weekly review.
- **Historical backfill of trend-summary.md**: The first row is whatever week this ships. No retroactive data population.
- **macOS date compatibility for `detect_phase()`**: The dual `date -d` / `date -j` fallback is provided for convenience but not tested in CI. CI runs on `ubuntu-latest` exclusively.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| GNU `date` epoch comparison fails on macOS | CI runs on `ubuntu-latest`. macOS fallback via `date -j -f` maintained for local testing but not required for CI. |
| Phase config in script drifts from marketing-strategy.md | Both are updated in the same PR when phases change. Add a comment in the script referencing the strategy doc lines. |
| Discord webhook not configured | KPI alert step checks for empty `DISCORD_WEBHOOK_URL` and skips gracefully (matches existing failure notification pattern). |
| Trend summary file corruption (partial write) | Append is atomic at the filesystem level for single-line writes. `>>` operator on ext4 is safe for single lines. Workflow concurrency group prevents parallel writes. |
| First-week N/A change triggers false miss alert | Explicit guard: skip KPI check when `VISITORS_CHANGE` is empty or "null". Emit `kpi_miss=false` in all skip cases. |
| `date -d` returns different epoch for timezone-unaware dates | All `date` calls use `-u` flag for UTC consistency. Snapshot dates are UTC by convention. |
| Off-by-one on phase boundaries | Phase ranges use `-le` (inclusive end dates). Test scenarios cover every boundary date (Apr 10/11, May 9/10, Jul 4/5). |

## Files Modified

| File | Change |
|------|--------|
| `scripts/weekly-analytics.sh` | Add phase config block, `detect_phase()`, `determine_status()`, `emit_kpi_status()`, trend summary append logic, KPI miss output logic. Remove hardcoded `CURRENT_PHASE` and `CURRENT_TARGET`. |
| `.github/workflows/scheduled-weekly-analytics.yml` | Add `id: analytics` to script step. Add KPI miss Discord alert step with `if: steps.analytics.outputs.kpi_miss == 'true'` conditional. |
| `knowledge-base/marketing/analytics/trend-summary.md` | Created on first run (not committed in this PR -- generated by CI). |

## References

- Parent issue: #594
- Snapshot script: `scripts/weekly-analytics.sh`
- Workflow: `.github/workflows/scheduled-weekly-analytics.yml`
- Growth targets: `knowledge-base/marketing/marketing-strategy.md` (lines 331-341)
- First snapshot: `knowledge-base/marketing/analytics/2026-03-13-weekly-analytics.md`
- Original plan: `knowledge-base/project/plans/2026-03-13-feat-plausible-analytics-operationalization-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-13-plausible-goals-api-provisioning-hardening.md`
- Learning: `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`
- Learning: `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-05-discord-allowed-mentions-for-webhook-sanitization.md`
- Learning: `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md`
- Learning: `knowledge-base/project/learnings/2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`
- Learning: `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`
- [GitHub Actions workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands)
- [Baeldung: UNIX Timestamp Arithmetic](https://www.baeldung.com/linux/shell-unix-timestamp-arithmetic)
