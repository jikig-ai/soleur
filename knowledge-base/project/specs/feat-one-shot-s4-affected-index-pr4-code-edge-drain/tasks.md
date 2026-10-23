# Tasks: S4 affected-index PR4, code-edge drain (Ref #10860, Ref #10448, Ref #9729)

Plan: `knowledge-base/project/plans/2026-10-23-ci-s4-affected-index-pr4-code-edge-drain-plan.md`. Rulings: `decision-challenges.md` in this directory.
Holds: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no criterion-c measurement, no flip PR, no delay of PR4.
Process: run long commands detached (script file, `setsid nohup bash <file>`, rc file, Monitor until-loop); `grep -q P < <(producer)`; no `git stash`.

## Phase 0 - claim, base, calibrate

- [ ] 0.1 `gh pr list --label s4-drain --state open` returns only #10945; mirror comment on #10448 present; rebase on `origin/main`.
- [ ] 0.2 Re-measure: detached worktree of the base, `audit --all-refs` (about 5 minutes), record the audit line and the code / non-code split with `CODE_EXT`; assert `gap_refs` equals the baseline line count.
- [ ] 0.3 Calibration trial (throwaway, reverted): about 10 heavy edges plus one new block plus one shared-array spread; run the census, `test-all-affected.test.sh` and one `ratchet --report`; record the census rules and the reveal rate; decide batch order / early split before building the table.
- [ ] 0.4 Scratch heuristic triage (not committed) writes `candidates.tsv`; the human read decides.
- [ ] 0.5 Recorder trial: one timeboxed attempt on one non-runner label; else write `recorder: not run, <reason>`.

## Phase 1 - decision table (`pairs-decisions.tsv`)

- [ ] 1.1 One row per code pair: `suite, path, class (a, b, c, d or mention), file:line, decision`; plus a revealed / held-back section; no class means no declaration.
- [ ] 1.2 Cluster pairs that share a consumer; quote the consumer loop for every class (d) row; the 271 `test-relevance-paths.sh` pairs are read once per consumer suite.
- [ ] 1.3 Order: batch A (17 suites with more than 10 code pairs), batch B (cross-suite library clusters), batch C (long tail).
- [ ] 1.4 Recorder cross-check (best-effort): top 12 suites plus 15 random; compare the full per-window opened set restricted to table pairs; flip any opened-but-mention pair.
- [ ] 1.5 Log held-back edges (`suite, F, reason, file:line`) and ambiguous declares.

## Phase 2 - one commit per batch

- [ ] 2.1 RED: edit the index only; `ratchet --base origin/main --report <file>` lists `stale-line` for exactly the declared pairs (set equality); counts come from the report, not stdout.
- [ ] 2.2 GREEN: prune-only `--print-baseline` to a `.new` file, move it, `ratchet` exits 0.
- [ ] 2.3 Reveal count: every revealed pair (real plus mention) counts PR-wide; stop line 60 / 30 / 4 rounds / 150, strictly decreasing; a revealed mention holds the revealing edge back; no accept file.
- [ ] 2.4 Commit batch with baseline in the same commit (real versus held-back counts and running totals in the message), push; the HEAD-pin check runs once on the final HEAD and after rebases.

## Phase 3 - fixpoint and verification

- [ ] 3.1 Post-final audit equals the last cycle (`refs`, `files_read`, `gap_refs`, `stale`), `gap_refs` equals `wc -l` of the baseline, last ratchet marker `exit=0 reason=pass`; final reveal 0.
- [ ] 3.2 Breadth check: prefixes at least 3 segments and at most 25 tracked files; no baseline added line (`grep -c '^+[^+]' < <(git diff origin/main...HEAD -- <baseline>)` prints 0).
- [ ] 3.3 Selection canary for prefix / glob edges only.
- [ ] 3.4 Replay suite detached: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (1,069 assertions, 420 mutants, about 17 minutes).
- [ ] 3.5 Full gate detached: `SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600 bash scripts/test-all.sh --affected`; rc 0, not rc 6; kill own stale runs first.
- [ ] 3.6 Census and lint: `lint-orphan-test-suites.sh`, `test-all-affected.test.sh`, shellcheck on the index file, `scripts/markdown-lint.sh` on changed docs.
- [ ] 3.7 After any rebase regenerate the baseline with a HEAD pin; sibling overlap loop and `git merge-tree` right before the push; floors resolved additively and confirmed by a measured run.
- [ ] 3.8 Time the final local `ratchet` run against the 162 s hosted datapoint (job cap 5 minutes, provisional ceilings 210 s / 270 s).
- [ ] 3.9 Rollback simulation in a scratch detached worktree (squash, revert, `ratchet --base origin/main`; expect `grown`); record in the plan.

## Phase 4 - docs and handoff

- [ ] 4.1 Runbook section 7: the drain rubric (about 15 lines, the one durable home), counts via `wc -l`, window-restart wording (recorded on #10865, restarts by hand), revert reads `grown`.
- [ ] 4.2 Comments on #10448 and #10861 (PR5 sizing, table path, ambiguous and held-back rows); #10865 only if merged inside the window.
- [ ] 4.3 PR body: `Ref` only, audit lines, class counts, ambiguous declares, prefix counts, always-on candidate rows, recorder status, stop-line outcome, holds, window consequence.

## Phase 5 - ship

- [ ] 5.1 Mark ready after the full gate and replay suite are green; merge via the queue; BEHIND never synced by hand; one re-enqueue on a flaky e2e dequeue, a second reported with the run URL.
- [ ] 5.2 After merge: `s4-drain` claim released; #10860, #10448, #9729 stay open; first `merge_group` run of the ratchet reads `exit=0 reason=pass`.
