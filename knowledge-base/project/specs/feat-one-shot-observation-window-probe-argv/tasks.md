# Tasks: feat-one-shot-observation-window-probe-argv

Plan: knowledge-base/project/plans/2026-10-27-fix-observation-window-probe-argv-limit-plan.md (Ref #10865, Ref #10861)

## Phase 0 - Reproduce
- 0.1 Fetch PR 9051 files page 1; run the accumulator `jq --argjson` step; expect rc 126 (Argument list too long)

## Phase 1 - Tests first (RED)
- 1.1 Helpers: `ow_big_files`, `ow_assert_bytes_over`, `ow_probe_split`, stub-gh `SLOW_<key>` branch
- 1.2 E2BIG rows: `row_ow_big_patch` (100/100/50), `row_ow_big_long` (3x100), `row_ow_long_names` (100/100/50), extend `row_ow_static` (`--argjson` operands)
- 1.3 `row_ow_pr_facts_cached` (PR 11, second unit)
- 1.4 `row_ow_progress`, `row_ow_heartbeat`
- 1.5 `row_ow_parallel_same`, `row_ow_worker_fail`, `row_ow_budget`
- 1.6 `row_ow_jq_error_text`
- 1.7 Mutants: args-accumulator, oracle-argv, progress-to-stdout, parallel-rc-ignored, budget-ignored, extras-last, draft-cache-dropped, jq-error-dropped, merge-in-completion-order; verify existing mutant anchors still unique
- 1.8 Run the section on the unfixed probe; record RED rows and messages

## Phase 2 - E2BIG fix
- 2.1 pr_facts: per-page projection through stdin, stdin-fed accumulate, exclusion program on stdin, jq error text

## Phase 3 - draft_at cache
- 3.1 Timeline once per PR (PR_TL), draft flag from the pull JSON (PR_CURDRAFT)

## Phase 4 - Parallel reads, budget, progress
- 4.1 Seams SOAK_PARALLEL, SOAK_BUDGET_S, SOAK_PROGRESS (positive-integer validation)
- 4.2 `read_unit` workers (`return 0`), `{ ...; } &` launch, counter + `wait -n`, extras first and deadline-exempt, first oldest-first dispatch unconditional, drain, first-failure-in-dispatch-order exit 3, trap waits for workers
- 4.3 Merge by zero-padded seq, `-k5,5 -s` plus `-k1,1n` tiebreak
- 4.4 Three stderr phase lines and opt-in heartbeat; status line unchanged
- 4.5 Header comment updates (certification paragraph, seams, budget bounds the read phase only)

## Phase 5 - Runbook, floors, gates
- 5.1 Runbook bullet "Reads are bounded and oldest-first"
- 5.2 FLOOR_ASSERTIONS / FLOOR_MUTANTS
- 5.3 Replay suite, shellcheck

## Phase 6 - Ship and verify
- 6.1 PR text Ref only, no s4-drain label, Changelog, semver:patch; prepush-secret-scan before every push
- 6.2 Comment on #7923 with the measured evidence
- 6.3 After merge: one read-only live run (stderr to a file), report verdict and timings to the operator; post nothing
