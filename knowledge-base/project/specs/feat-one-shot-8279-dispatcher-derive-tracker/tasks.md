# Tasks: registry-host-replace dispatcher derives the delivered change and its tracker (#8279)

Plan: `knowledge-base/project/plans/2026-09-19-fix-registry-dispatcher-derive-delivery-tracker-plan.md`. No `spec.md` exists for this branch (pipeline entered at `plan`); `lane:` defaulted to `cross-domain` (fail-closed).

## Phase 1: Tests first (RED)

- [ ] 1.1 Write `tests/scripts/test-registry-delivery-change.sh` in the shape of `tests/scripts/test-registry-replace-preflight.sh`: a `gh` stub at `$TMP/gh.sh` dispatching on argv (`compare/`, `commits?`, `/pulls`, `commits/<sha>`) driven by `STUB_*` env vars, a `run_sut` that runs `env -u GITHUB_ACTIONS REGISTRY_DELIVERY_GH_CMD=$TMP/gh.sh bash "$SUT" …`, an inline anti-vacuity floor on the assertion count, every fixture synthesized.
  - [ ] 1.1.1 Rows T1–T16 from the plan's `## Test Scenarios` (T1 subject has no `(#N)` suffix and carries `=`, `%`, backticks, `"`; T4b is the manual-re-fire shape; T11 and T15 assert `prs=` EMPTY on a proven range; T12 asserts rc 1 on the seam under `GITHUB_ACTIONS`; T14 counts exactly 10 `/pulls` calls).
  - [ ] 1.1.2 Run it against a non-existent helper and confirm every row is RED.
- [ ] 1.2 Register the suite in `scripts/test-all.sh` directly under `run_suite "tests/scripts/registry-replace-preflight"` with the same `run_suite "tests/scripts/registry-delivery-change" bash tests/scripts/test-registry-delivery-change.sh` shape (the runner does not glob `tests/scripts/`).

## Phase 2: Helper (GREEN)

- [ ] 2.1 Write `scripts/registry-delivery-change.sh` (executable, `set -uo pipefail`): args `--repo`, `--after` (required, usage → exit 2), `--before` (may be empty), `--path`; seam `REGISTRY_DELIVERY_GH_CMD` (default `gh`) refused with exit 1 + `::error::` naming it when `GITHUB_ACTIONS` is set; constant `MAX_LOOKUPS=10`.
  - [ ] 2.1.1 Arms 1–7 from plan §1: no watermark → `[after]`/unproven; compare (NO paging params) rc≠0 or status ∉ {ahead, identical} → `[after]`/unproven with note; `total_commits > 250` → `[after]`/unproven; range ∩ `commits?sha=&path=&per_page=100` → candidates oldest→newest; empty intersection on a proven range → `prs=` EMPTY, summary names `<after7>` and `<before7>`; `resolve_pr_for_sha` = `/pulls` `.[0].number // empty` → `(#N)` subject fallback → digit validation → `unattributed`; dedupe preserving order.
  - [ ] 2.1.2 Output lines: `range=`, `range_note=`, `commits=`, `prs=`, `unattributed=`, `summary=` (one line, first message line only, CR/LF stripped, no cap, no suffix strip). Exit 0 on every API arm.
  - [ ] 2.1.3 Header comment: what it answers, the watermark/range contract, why `identical` needs no arm, why merge-commit PRs resolve via their branch commits (measured on #6326), the seam guard.
- [ ] 2.2 Run the suite to GREEN; then run the plan's mutation rows (range intersection removed → T11 red; `[after]` fallback on proven-no-touch → T11/T15 red; `(#N)` fallback dropped → T7 red; `?per_page=100` on compare → T10 red; compare failure `exit 1` → T6 red; delete T1's `pass` → floor reds) and revert each.

## Phase 3: Workflow

- [ ] 3.1 `.github/workflows/registry-host-replace-dispatch.yml` — `workflow_dispatch.inputs.tracker` (string, optional, default `''`, description per plan); `permissions:` add `pull-requests: write` with its WHY comment and rewrite the `issues: write` WHY comment to name `gh api … /issues/{n}/comments -X POST` + `gh issue create`.
- [ ] 3.2 Gate step: hoist the `gh run list` watermark lookup above the `"$EVENT_NAME" == "workflow_dispatch"` early exit; emit `watermark=${BEFORE_SHA}` as soon as a SHA resolves (before the gate's own compare); manual arm still `deliver=true` unconditionally.
- [ ] 3.3 New step `id: change` after the gate: `if: always()`, `continue-on-error: true`, `timeout-minutes: 5`, `env:` `GH_TOKEN`, `BEFORE`, `AFTER`, `TRACKER`; `set -euo pipefail`; runs the helper, `echo`es each `key=value` to `$GITHUB_OUTPUT`, strips a leading `#` from `TRACKER`, digit-validates it (`::warning::` + drop otherwise), emits `targets=` = prs ∪ tracker deduplicated, prints the block to `$GITHUB_STEP_SUMMARY`. No in-step fallback block.
- [ ] 3.4 Dispatch step: bind `SUMMARY: ${{ steps.change.outputs.summary }}` via `env:` with `SUMMARY="${SUMMARY:-the cloud-init-registry.yml user_data at ${MERGE_SHA:0:7}}"`; push-arm reason `Delivering the cloud-init-registry.yml user_data merged at ${MERGE_SHA} — ${SUMMARY}. Inert until this replace runs; the store volume is preserved.`; manual arm appends ` — ${SUMMARY}`; replace the `#7556` step-summary sentence with the follow-through wording from plan §2.
- [ ] 3.5 Poll step: add `id: poll`; emit `apply_run=` and `apply_conclusion=` on every arm; remove its `gh issue comment 7556`; keep `::error::` + `exit 1` on non-success; reword `#7556 remains the authority`.
- [ ] 3.6 Refusal step ("Record the delivery verdict on its tracker(s)"): bind the four step outcomes, poll outputs, change outputs, `job.status` via `env:`; consumer defaults for `SUMMARY`/`TARGETS`; four arms (cancelled / `Apply FAILED` / `Delivery REFUSED (${FAILED_STEP})` / `Delivery UNDETERMINED`); not-live sentence only when `prs` non-empty, `(attribution unproven: …)` when `range_note` non-empty, the "unchanged since the delivery watermark" sentence when `prs` is empty on a proven range; `MARKER=` defined once; re-fire instruction with `-f tracker=${FIRST_TARGET}` substituted (echoed to the step summary too); posting loop via `gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${n}/comments" -f body="$BODY"` with per-target `::error::` and a final `exit 1` if any failed; empty targets → `gh issue create … --label domain/engineering --label type/chore --label priority/p1-high --label action-required`. No comment listing, no pre-create search.
- [ ] 3.7 Rewrite the poll/refusal WHY comments that name #7556; add the STEP MAP comment block at the top of `jobs:`; keep the header provenance line.
- [ ] 3.8 Verify every `run:` body in the file parses (`bash -n` via the AC7 PyYAML one-liner) and that no `run:` body contains `steps.change.outputs` (AC11a).

## Phase 4: Verification

- [ ] 4.1 Run AC1–AC13 from the plan verbatim; fix anything that does not match.
- [ ] 4.2 `bash scripts/alarm-issue-filing-guard.test.sh` (expect 83 scanned, ≤ 11 violations) and `python3 scripts/lint-workflow-issue-write-scope.py` (exit 0).
- [ ] 4.3 `bash scripts/test-all.sh` touched shards: `tests/scripts/registry-delivery-change`, `scripts/alarm-issue-filing-guard`, `scripts/lint-workflow-issue-write-scope`, `scripts/lint-workflow-issue-write-scope-live`, `plugins/soleur/test/c4-count-parity`.
- [ ] 4.4 Confirm the diff is a subset of the AC13 file list.

## Phase 5: Ship

- [ ] 5.1 PR body: `Closes #8279`; render `decision-challenges.md` (T1 verdict-helper split, T2 AC trimming) per `ship` Phase 6.
- [ ] 5.2 File the two deferrals from the plan (`resolve_pr_for_sha` extraction; poll UNVERIFIED arms) as `deferred-scope-out` issues if not already tracked.
- [ ] 5.3 Post-merge: read the registration-path dispatcher run per AC14 (`range=proven`, `deliver=false` unless a config-touching PR merged in the range, `success`).
