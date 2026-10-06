# Tasks — feat-one-shot-9429-9533-cron-monitor-sweep

Plan: `knowledge-base/project/plans/2026-10-06-fix-cron-monitor-luks-marker-queue-health-plan.md`
Closes #9429, closes #9533. Non-goals: #9513, #9510, #9475 (untouched files, stay open).

## Phase 1 — #9429: set-only `--no-interactive` + self-describing marker fault

- [ ] 1.1 `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (~:1670): split the doppler stub's `for need` flag loop — `-p soleur` / `-c prd_workspaces_luks_marker` required on all verbs; `--no-interactive` REQUIRED on `secrets set`, REFUSED (exit 64) on `secrets get`/`secrets delete`. Verify suite REDs against unmodified workflow (failing test first).
- [ ] 1.2 `.github/workflows/workspaces-luks-verify.yml` (~:1093): `marker_args=(-p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG")` + comment citing set-only flag scope (Doppler CLI v3.76.6); add `--no-interactive` to the `secrets set` argv only (~:1118). Keep `${marker_args[@]}` on get/read-back/delete (g3_mut anchors 3/17a/17d stay byte-identical).
- [ ] 1.3 `marker_state()` fault arm: sanitized diagnostic to stderr — `sed -E 's/dp\.[a-z]+\.[A-Za-z0-9._-]+/[REDACTED-TOKEN]/g' <<<"${out//$DOPPLER_TOKEN/[REDACTED-DOPPLER-TOKEN]}" >&2` before `return 1`.
- [ ] 1.4 Add scenario S55 (`G3_NEEDLE='unable to reach the API'` on `FIXTURE_DOPPLER_GET_FAIL=1`), append to `G3_EXPECTED_IDS`; add mutation row 17g dropping the diagnostic → S55 reds.

## Phase 2 — #9533a: repipe both issue-filing dedupe queries

- [ ] 2.1 `scheduled-actions-queue-health.yml` ~:130 (UNDER_ASSIGNED) and ~:178 (UNKNOWN): replace `gh issue list --json … --jq --arg t …` with the fail-open two-stage shape mirrored from `workspaces-luks-verify.yml:905` (`if ! EXISTING="$(gh … --json number,title 2>/dev/null | jq -r --arg t "$ISSUE_TITLE" 'map(select(.title == $t)) | .[0].number // empty')"; then ::error:: …; EXISTING=""; fi`).
- [ ] 2.2 Re-grep file: zero `--jq --arg`; self-close `--jq '.[].number'` untouched.
- [ ] 2.3 `scripts/actions-queue-health.test.sh`: workflow-hygiene block — `grep -c -- '--jq --arg'` on the workflow == 0; both `File …` step names present. No `| grep -q` readers anywhere in the diff (AC7).

## Phase 3 — #9533b: genuine-truncation predicate

- [ ] 3.1 `scripts/actions-queue-health.test.sh`: reshape test 19 to a full page + `total_count` beyond (genuine truncation → UNKNOWN rc2); add 19b (`total_count=8`, 7 rows → non-UNKNOWN verdict); add 19c boundary (page full, `IP_TOTAL == IP_RUN_COUNT` → proceeds).
- [ ] 3.2 `scripts/actions-queue-health.sh` (~:137): guard becomes `IP_RUN_COUNT -ge MAX_IP_RUNS && IP_TOTAL -gt IP_RUN_COUNT` with the race-explaining comment.

## Phase 4 — verify

- [ ] 4.1 `bash scripts/actions-queue-health.test.sh` → 0; `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` → 0 (incl. Guard-3 mutation battery).
- [ ] 4.2 `grep -n 'no-interactive' .github/workflows/workspaces-luks-verify.yml` → exactly the `secrets set` line; `grep -c -- '--jq --arg' .github/workflows/scheduled-actions-queue-health.yml` → `0`.
- [ ] 4.3 `bash -n` the edited run bodies.
- [ ] 4.4 PR body: `Closes #9429` + `Closes #9533` + `## Changelog`; note #9554 (no file overlap) and #9513/#9510/#9475 remaining open.
