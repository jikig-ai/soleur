# Tasks: Weekly Analytics Improvements

## Phase 1: Setup

- [ ] 1.1 Read existing `scripts/weekly-analytics.sh` and `.github/workflows/scheduled-weekly-analytics.yml`
- [ ] 1.2 Read `knowledge-base/marketing/marketing-strategy.md` lines 331-341 for phase date ranges
- [ ] 1.3 Read learnings: `2026-03-13-shell-script-defensive-patterns.md`, `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`

## Phase 2: Core Implementation

- [ ] 2.1 Add `detect_phase()` function to `scripts/weekly-analytics.sh`
  - [ ] 2.1.1 Define phase config block with date ranges and targets (Phase 1: Mar 13 - Apr 10 +15%, Phase 2: Apr 11 - May 9 +10%, Phase 3: May 10 - Jul 4 +7%)
  - [ ] 2.1.2 Implement epoch-based date comparison using `date -u -d` with macOS `date -u -j -f` fallback
  - [ ] 2.1.3 Add "Post-Phase 3" fallback for dates after Jul 4 and "Pre-Phase 1" for dates before Mar 13
  - [ ] 2.1.4 Use `local` declarations for all function variables per constitution shell conventions
  - [ ] 2.1.5 Set `CURRENT_PHASE`, `CURRENT_TARGET`, and `TARGET_NUMERIC` as globals for caller access
  - [ ] 2.1.6 Remove hardcoded `CURRENT_PHASE` and `CURRENT_TARGET` variables (lines 31-32)
  - [ ] 2.1.7 Call `detect_phase "$SNAPSHOT_DATE"` before snapshot generation

- [ ] 2.2 Add trend summary append logic to `scripts/weekly-analytics.sh`
  - [ ] 2.2.1 Define `TREND_FILE` path as `$OUTPUT_DIR/trend-summary.md`
  - [ ] 2.2.2 Create trend summary file with markdown header and table header if it does not exist
  - [ ] 2.2.3 Calculate week number using epoch division: `(snapshot_epoch - p1_start_epoch) / (7 * 86_400) + 1`
  - [ ] 2.2.4 Add `determine_status()` function to compare numeric `VISITORS_CHANGE` against `TARGET_NUMERIC`
  - [ ] 2.2.5 Add idempotency guard: `if grep -q "$SNAPSHOT_DATE" "$TREND_FILE"` (safe under `set -e` inside `if` conditional)
  - [ ] 2.2.6 Append data row to trend summary file using `>>` operator

- [ ] 2.3 Add KPI miss output logic to `scripts/weekly-analytics.sh`
  - [ ] 2.3.1 Add `emit_kpi_status()` helper that writes key=value to `$GITHUB_OUTPUT` when available
  - [ ] 2.3.2 After computing metrics, compare `VISITORS_CHANGE` against `TARGET_NUMERIC`
  - [ ] 2.3.3 Emit `kpi_miss=false` when: change is empty/null, or phase is pre/post-phase (no target)
  - [ ] 2.3.4 Emit `kpi_miss=true` plus `kpi_phase`, `kpi_target`, `kpi_actual`, `kpi_visitors` when below target

- [ ] 2.4 Update `.github/workflows/scheduled-weekly-analytics.yml`
  - [ ] 2.4.1 Add `id: analytics` to the "Generate analytics snapshot" step
  - [ ] 2.4.2 Add "Discord notification (KPI miss)" step with `if: steps.analytics.outputs.kpi_miss == 'true'`
  - [ ] 2.4.3 Use `jq -n` for payload construction with explicit `username`, `avatar_url`, `allowed_mentions: {parse: []}`
  - [ ] 2.4.4 Gracefully skip if `DISCORD_WEBHOOK_URL` is not set

## Phase 3: Testing

- [ ] 3.1 Verify `detect_phase()` returns correct values for all boundary dates: Mar 12 (pre), Mar 13 (P1 start), Apr 10 (P1 end), Apr 11 (P2 start), May 9 (P2 end), May 10 (P3 start), Jul 4 (P3 end), Jul 5 (post)
- [ ] 3.2 Verify trend summary file creation with header on first run
- [ ] 3.3 Verify trend summary append with no duplicate rows on re-run (idempotency)
- [ ] 3.4 Verify week number calculation is correct (epoch division by 7*86400)
- [ ] 3.5 Verify `kpi_miss=true` output when WoW < target (including negative WoW values)
- [ ] 3.6 Verify `kpi_miss=false` output when WoW >= target, or when change data is N/A
- [ ] 3.7 Verify script exits 0 on KPI miss
- [ ] 3.8 Verify existing snapshot markdown format is unchanged
- [ ] 3.9 Run `bash -n scripts/weekly-analytics.sh` for syntax validation
- [ ] 3.10 Run markdownlint on any new or modified markdown files
