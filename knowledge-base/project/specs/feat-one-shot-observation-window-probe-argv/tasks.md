# Tasks: feat-one-shot-observation-window-probe-argv

Plan: knowledge-base/project/plans/2026-10-27-fix-observation-window-probe-argv-limit-plan.md (Ref #10865, Ref #10861)

## Phase 0 - Reproduce
- 0.1 Fetch PR 9051 files page 1; run the accumulator `jq --argjson` step; expect rc 126 (Argument list too long)

## Phase 1 - Tests first (RED)
- 1.1 Fixture builders `ow_big_files`, size precondition helper, `ow_probe_split`
- 1.2 E2BIG rows: `row_ow_big_patch`, `row_ow_big_long`, `row_ow_long_names`, `row_ow_patch_mentions_oracle`, `row_ow_static_argv`
- 1.3 Cache row `row_ow_pr_facts_cached`
- 1.4 Progress rows: `row_ow_progress`, `row_ow_heartbeat`
- 1.5 Parallel/budget rows: `row_ow_parallel_same`, `row_ow_worker_fail`, `row_ow_budget`, `row_ow_budget_extras_unread`, `row_ow_prefix_contiguous`
- 1.6 Error/prereq rows: `row_ow_jq_error_text`, `row_ow_bash_version`
- 1.7 Mutants: args-accumulator, projection-dropped, oracle-argv, progress-to-stdout, parallel-rc-ignored, budget-ignored, extras-last, draft-cache-dropped, jq-error-dropped, contiguity-check-dropped; re-check existing mutant anchors
- 1.8 Run the section on the unfixed probe; record RED rows (E2BIG rows RED with `files (parse)`)

## Phase 2 - E2BIG fix
- 2.1 pr_facts: printf-to-file, per-page projection through stdin, `jq -s add`, `--slurpfile`, jq error text

## Phase 3 - draft_at cache
- 3.1 One timeline read per PR; curdraft from the written pull JSON

## Phase 4 - Parallel reads, budget, progress
- 4.1 Seams SOAK_PARALLEL, SOAK_BUDGET_S, SOAK_PROGRESS; bash >= 5 check
- 4.2 `read_unit` workers, counter-based `wait -n`, newest-queue extras first, deadline check, drain, contiguity check
- 4.3 Progress lines (stderr), `elapsed_s` appended to the status line
- 4.4 Header comment updates

## Phase 5 - Runbook, floors, gates
- 5.1 Runbook bullet "Reads are bounded and oldest-first"
- 5.2 FLOOR_ASSERTIONS / FLOOR_MUTANTS
- 5.3 Replay suite, shellcheck

## Phase 6 - Ship and verify
- 6.1 PR text Ref only, no s4-drain label, Changelog, semver:patch; prepush-secret-scan before every push
- 6.2 Comment on #7923 with the measured evidence
- 6.3 After merge: one read-only live run (stderr to a file), report verdict and timings to the operator; post nothing
