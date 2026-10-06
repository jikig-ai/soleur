# Tasks — feat-one-shot-9429-9533-cron-monitor-sweep

Plan: `knowledge-base/project/plans/2026-10-06-fix-cron-monitor-luks-marker-queue-health-plan.md`
Closes #9429, closes #9533. Non-goals: #9513, #9510, #9475 (untouched files, stay open).

## Phase 1 — #9429: set-only `--no-interactive` + self-describing marker fault

- [x] 1.1 `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (~:1670): split the doppler stub's `for need` flag loop — `-p soleur` / `-c prd_workspaces_luks_marker` required on all verbs; `--no-interactive` REQUIRED on `secrets set`, REFUSED (exit 64) on `secrets get`/`secrets delete`. Verify suite REDs against unmodified workflow (failing test first).
- [x] 1.2 `.github/workflows/workspaces-luks-verify.yml` (~:1093): `marker_args=(-p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG")` + comment that names the set-only-flag invariant WITHOUT spelling the `--no-interactive` literal (whole-file `grep -c` must stay exactly 1 = the set argv); add `--no-interactive` to the `secrets set` argv only (~:1118). Keep `${marker_args[@]}` on get/read-back/delete (g3_mut anchors 3/17a/17d stay byte-identical).
- [x] 1.3 `marker_state()` fault arm: sanitized diagnostic to stderr — `sed -E 's/dp\.[a-z]+\.[A-Za-z0-9._-]+/[REDACTED-TOKEN]/g' <<<"${out//$DOPPLER_TOKEN/[REDACTED-DOPPLER-TOKEN]}" >&2` before `return 1`.
- [x] 1.4 Add scenario S55 (`G3_NEEDLE='unable to reach the API'` on `FIXTURE_DOPPLER_GET_FAIL=1`), append to `G3_EXPECTED_IDS`; add mutation row 17g dropping the diagnostic → S55 reds.

## Phase 2 — #9533a: repipe both issue-filing dedupe queries

- [x] 2.1 `scheduled-actions-queue-health.yml` ~:130 (UNDER_ASSIGNED) and ~:178 (UNKNOWN): replace `gh issue list --json … --jq --arg t …` with the fail-open two-stage shape mirrored from `workspaces-luks-verify.yml:905` (`if ! EXISTING="$(gh … --json number,title 2>/dev/null | jq -r --arg t "$ISSUE_TITLE" 'map(select(.title == $t)) | .[0].number // empty')"; then ::error:: …; EXISTING=""; fi`).
- [x] 2.2 Re-grep file: zero `--jq --arg`; self-close `--jq '.[].number'` untouched.
- [x] 2.3 `scripts/actions-queue-health.test.sh`: workflow-hygiene block — `grep -c -- '--jq --arg'` on the workflow == 0; both `File …` step names present. No `| grep -q` readers anywhere in the diff (AC7).

## Phase 3 — #9533b: genuine-truncation predicate

- [x] 3.1 `scripts/actions-queue-health.test.sh`: reshape test 19 to a full page + `total_count` beyond (genuine truncation → UNKNOWN rc2); add 19b (`total_count=8`, 7 rows → non-UNKNOWN verdict); add 19c boundary (page full, `IP_TOTAL == IP_RUN_COUNT` → proceeds).
- [x] 3.2 `scripts/actions-queue-health.sh` (~:137): guard becomes `IP_RUN_COUNT -ge MAX_IP_RUNS && IP_TOTAL -gt IP_RUN_COUNT` with the race-explaining comment.

## Phase 4 — verify

- [x] 4.1 `bash scripts/actions-queue-health.test.sh` → 0; `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` → 0 (incl. Guard-3 mutation battery).
- [x] 4.2 `grep -n 'no-interactive' .github/workflows/workspaces-luks-verify.yml` → exactly the `secrets set` line; `grep -c -- '--jq --arg' .github/workflows/scheduled-actions-queue-health.yml` → `0`.
- [x] 4.3 `bash -n` the edited run bodies.
- [x] 4.4 PR body: `Closes #9429` + `Closes #9533` + `## Changelog`; note #9554 (no file overlap — since merged) and #9513/#9510/#9475 remaining open. `## User-Brand Impact` (`none` + scope-out reason) added for the sensitive-path gate.

## Phase 5 — review round 1 (done)

- [x] 5.1 P1: `WF_MIN_ASSERTIONS` 321 → 325 (S55+17g → 323; S56+17h → 325), ledger records both deltas.
- [x] 5.2 P2: hygiene pin widened — strip `| jq …` segments + comment lines, assert no `--arg`/`--argjson` survives anywhere (order/spelling-proof); pin `if ! ISSUE_LIST=` count == 2.
- [x] 5.3 P2: `marker_state` fault arm prints sanitized+prefixed diagnostic (`[doppler-stderr]`, token+`dp.*` masked, ANSI/CR stripped, 8K cap); anchored `^Doppler Error: Could not find requested secret` absent-match (ANSI-stripped input).
- [x] 5.4 P2: mutation 17h (bespoke row — defect legitimately reds control S01): fold `--no-interactive` into `marker_args` → S01 reds via stub's set-only-flag refusal.
- [x] 5.5 P3 batch: empty-value → absent; `after=unknown` prose; dedupe diagnosability (`ISSUE_LIST` capture, two-leg if/elif, bounded single-line `::error::` breadcrumb, gh stderr → tempfile not stdout); probe numeric validation + `MAX_IP_RUNS` clamp ≤100; `- name:` anchored grep; missing-workflow guards; S56.
- [x] 5.6 Follow-ups filed: #9612 (repo-wide --arg-in-gh sentinel + sibling dedupe normalization), #9613 (doppler_call() helper for sibling stderr sites).
