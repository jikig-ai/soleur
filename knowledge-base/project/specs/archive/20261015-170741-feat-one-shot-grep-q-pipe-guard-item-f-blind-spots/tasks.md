# Tasks: grep -q pipe-guard, Item F (guard blind spots)

Phases 0 to 5 are ticked as delivered (evidence in `evidence.md`, the review round after the first battery in its last section); Phase 6 is ticked by the ship step.

Plan: `knowledge-base/project/plans/2026-10-14-chore-grep-q-guard-item-f-blind-spots-plan.md`. Tracker #9217 (`Ref`, never `Closes`).

## Phase 0: measurement (read-only; first commit is `evidence.md`)

- [x] 0.1 `git merge origin/main`; run `bash .claude/hooks/grep-q-pipe-guard.test.sh`; record pairs, triples, rows, `SWEPT`
- [x] 0.2 Re-run `j0-measure.py` and `j0-pattern-prototype.sh` (shipped hits equal widened hits); reconcile with the plan-time figures
- [x] 0.3 Open-PR screen (added lines of every open PR in a newly read class, widened pattern) and the marker census
- [x] 0.4 Write `evidence.md`; commit it before any guard edit
- [x] 0.5 Self-sweep: confirm every script in the spec dir is clean under the widened pattern (fixtures in `.txt` data, mutants built with `printf`)

## Phase 1: red first (guard only, no pattern or pathspec change)

- [x] 1.1 Case tables for the reader grammar (`V2_CASE_COUNT`, per-case names, a negative control for the loop)
- [x] 1.2 Split-line and fence fixtures plus the `scan_sweep` wiring check (scratch root with one split file and one md file)
- [x] 1.3 Extension witness with literal `SWEEP_EXT_COUNT` and expected list, `SWEEP_FLOOR_MIN`, `spec-dir-zero`, kb witness (active, archive, archive-lookalike), cross-extension comment-filter cases, marker-pin check
- [x] 1.4 Run under `ulimit -v 6000000`; record each new check's first result in `evidence.md`

## Phase 2: one commit per item (cut order is the reverse of this list's tail)

- [x] 2.1 Item 1 (also rewrite `residual-v2.sh` and the fp fixture; pins `V2_BAD_LINES`, fp 2): WRAP words and bounded run, BIN grep family, `sh -c` alternative
- [x] 2.2 Item 2: ARG one-operand rule (quote-aware), EARLY cluster digits and long-option abbreviations
- [x] 2.3 Item 6a: GREP-named variable in BIN; move residual lines to the bad side; re-pin `V2_BAD_LINES` / `V2_GOOD_LINES`
- [x] 2.4 Item 8 (ts): `SWEEP_EXTS` array builds the pathspec and the witness; ts tsx mjs cjs; js-family comment filter; convert the stub line in `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`; `SWEEP_FLOOR`, test canary
- [x] 2.5 Item 9: kb exclusion narrowed to `archive/` segments
- [x] 2.6 Item 8 (py): add py with its `#` filter and the cross-extension cases
- [x] 2.7 Item 4: `scan_split` linearising pass folded into `scan_sweep`
- [x] 2.8 Item 7: `scan_md` fence linearising pass folded into `scan_sweep`, `sweep_git_grep` pathspec parameter, `MD_FLOOR` argument of `sweep_main`, update the `return-wiring` text pins
- [x] 2.9 Item 10: per-file marker block (derived through `sweep_git_grep`) and its check

## Phase 3: wording and pins

- [x] 3.1 Rewrite the header paragraph on what a line regex cannot close and the stated limits; update the `ALLOW_MARKER` comment; keep the series open
- [x] 3.2 Recompute `SWEEP_PROBE_CHECKS` with the header recipe; no script suffix in comments; run `bash scripts/test-affected-kb-consumers.test.sh` once

## Phase 4: battery

- [x] 4.1 `mutation-battery.py` and `mutation-rows.json` in the spec dir: every Guard Contract row, one mutant at a time, `ulimit -v 6000000`, landing check plus control rc 0, graded by named substring
- [x] 4.2 Run under each second awk present, `( trap '' PIPE; ... )`, `env -i`, and `ubuntu:24.04` if docker exists
- [x] 4.3 Record results in `evidence.md`; UNVERIFIED rows listed with reason

## Phase 5: test file

- [x] 5.1 vitest run of `run-migrations-unmerged-gate.test.ts` at base and head (no ulimit); equal assertion counts

## Phase 6: ship

- [x] 6.1 Merge `origin/main`, re-run the guard, recompute pins (#10322 and #10081 edit the join table and `PJ_TRIPLES`)
- [x] 6.2 Lints (plan AC-9), pre-push ratchet lane on the merged tree
- [x] 6.3 Tracker comment on #9217 (dispositions, each figure with its command, NOT-fixed list); file the `head -N` / awk-exit wave issue (roadmap milestone, linked to #9217)
- [x] 6.4 PR body (`Ref #9217`; labels `semver:patch`, `app:web-platform`; barred vocabulary absent), `soleur:ship`
