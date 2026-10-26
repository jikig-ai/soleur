# Tasks: S4 PR5 measurement slice (Ref #10861)

Plan: `knowledge-base/project/plans/2026-10-26-ci-s4-affected-index-pr5-glob-measurements-plan.md`. Decisions: `decision-challenges.md` (rows 1-12). Receipts go under `receipts/` in this directory. Holds: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR. No number from an earlier PR or from planning is copied into any receipt.

## Phase 0 - base and preflight

- 0.1 `git fetch origin main`, merge it, record `BASE=$(git rev-parse origin/main)` and `date -u` in `receipts/measurement-stamp.txt`.
- 0.2 Re-verify: #10861 open, holds untouched, `gh pr list --label s4-drain --state open` empty, handoff receipts present.
- 0.3 Take the edge sets once, before any edit: `bash scripts/test-all.sh --print-selection --paths=README.md > receipts/rows.txt` (background; cold run takes minutes); confirm `fallback=none` and rows for the four labels.

## Phase 1 - build the measurement (tests first)

- 1.1 Write the failing `== glob-rate (S4 PR5)` section in `plugins/soleur/test/ci-pr-affected-replay.test.sh`
  - 1.1.1 count rows (glob-only, existing-only, total, incremental; empty candidate field still listed)
  - 1.1.2 always_on, runner-changed, not-evaluable and empty-diff units in both readings
  - 1.1.3 one table-driven verdict row (60000/60001, 30000/30001, 50/51 of 200) and the floor, missing and disagree rows
  - 1.1.4 pair-coverage refusal, directory-completeness, malformed-entry refusal, non-canonical candidates file
  - 1.1.5 spot-check divergence stop (rc 4)
  - 1.1.6 Guard Contract mutation rows 1-7 and harness rows (a)-(b)
- 1.2 Implement `cmd_glob_rate`, `durations_src`, docstring and argparse in `scripts/ci-pr-affected-replay.py` (read-only; `durations()` untouched)
- 1.3 Green the section, run the whole replay suite detached, shellcheck, `py_compile`; commit tool and tests before measuring

## Phase 2 - take both measurements

- 2.1 The 200 units: assert 200 first-parent commits of `$BASE`, `(#N)` subjects, distinct PR count, dates
- 2.2 Duration (measurement 1) for the four labels with the `src` column; the duration gate (`floor`, missing, over 60000 ms stop here)
- 2.3 Recorder evidence for gate-passing suites (one attempt each)
- 2.4 Candidate sets for gate-passing suites; each entry matches a tracked file
- 2.5 Build `receipts/pairs-scope.tsv` (the 43-pair rows plus the one `boundary-prefix` pair)
- 2.6 Run `glob-rate ... --base $BASE --spot-check 3`; save `glob-rate.tsv` and the marker line
- 2.7 Glob-half check in a detached scratch worktree against the real selector; remove the worktree

## Phase 3 - apply the verdicts (skip when nothing qualifies)

- 3.1 Claim `s4-drain` (label on #11226, mirror comment on #10448)
- 3.2 Edit `scripts/lib/test-affected-paths.sh` for `glob` and `always_on` rows only; fix the stale grep-q-pipe-guard array comment
- 3.3 Delete the accept rows reported stale `suite-always-on`
- 3.4 Prune the baseline with `ratchet --print-baseline`; `ratchet --base origin/main` exits 0
- 3.5 Post-edit parity (empty-candidate run, one real-selector glob-only check per edited suite)
- 3.6 Verification set (replay suite, affected tests, kb-consumers test, probe-row test, orphan census, `uniq -d`, shellcheck, markdown lint)

## Phase 4 - documentation and handoff

- 4.1 Runbook section 7: exception clause on two bullets, procedure line, fix the "selection call" wording
- 4.2 Comment on #10861: verdict table, baseline movement, what remains by name

## Phase 5 - ship

- 5.1 Push, `soleur:ship`; merge `origin/main` before arming; re-run Phases 2 and 3 if the listed files moved since `BASE`, else the ratchet only
- 5.2 If the index or baseline changed: comment the merge SHA on #10865; confirm the `s4-drain` claim is free
