# Tasks: S4 affected-index PR4b, the held-back real-read edges (Ref #10959, Ref #10448, Ref #9729)

Plan: `knowledge-base/project/plans/2026-10-25-ci-s4-affected-index-pr4b-held-back-edges-plan.md`. Rulings: `decision-challenges.md` in this directory (CTO rows 1-8, 2026-10-25).
Holds: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no criterion-c measurement, no flip PR.
Process: run long commands detached (script file, `setsid nohup bash <file>` or `run_in_background`, rc file, one `until` loop); `grep -q P < <(producer)`; no `git stash`; stage by explicit pathspec; `CI_PR_AFFECTED` unset in every shell used; push before any long wait.

## Phase 0 - claim, base, calibrate (no edit)

- [ ] 0.1 `gh pr list --label s4-drain --state open` returns only #11109; mirror comment on #10448 present; `git fetch origin main` and rebase; sibling-overlap loop.
- [ ] 0.2 Re-measure (ratchet `--report` and `audit --all-refs --accept <main's accept file>`) only if `origin/main` moved past `45fe23b767`; otherwise cite `receipts/ratchet-baseline-45fe23b767.out`.
- [ ] 0.3 Build `receipts/edges-decisions.tsv` from `receipts/worklist-edges.tsv`: `kept-for-census` (inngest-host-dark-gate -> inngest-probe-row.sh), `already-undrained` (heartbeat-feeder -> same lib); `grep -Fxcf` equals 116; `commits_90d` per F; array names via `_aff_label_map`; 11 new-array labels registered, no label-map collision.
- [ ] 0.4 Cut the slice (cumulative round-1 at most 130) into `receipts/slice.tsv`; chains of at most 59 (trial: 25 rows, then through `redact-sentinel`, then `compound-promote`).
- [ ] 0.5 Record for the PR body: CI run 40223185 conclusion and the first hosted `affected-index-ratchet` wall time (or `not yet observed, <date>`).

## Phase 1 - per chain: declare, first report, pre-classify

- [ ] 1.1 Scratch copy: declare the chain's edges, no accept rows, `ratchet --report`; save `receipts/chain-<k>-round-<n>-first-report.txt` (summary line plus counted `new-pair`); 60 or more means bisect.
- [ ] 1.2 `audit --root <scratch git worktree> --all-refs --accept <main's accept file>` for the boundary lines (the ratchet report prints at most 3 per pair); split `anchor/ordinal` on `/`.
- [ ] 1.3 `receipts/reveals-decisions.tsv`: `suite, edges, path, ref file:line, anchor12, line text, class (real-read|mention), line_kind, ref_commits_90d` (match by anchor after a rebase); class a edges read every ref line; b/c/d default mention unless the suite extracts and re-reads the path; unsure holds the edge.
- [ ] 1.4 Hold rules into `receipts/edges-decisions.tsv`: more than 10 rows, or F or the ref file hot (more than 8 commits in 90 days) with any row, or unsure; outcomes include out-of-slice, held-cap, held-ceiling, held-grep-q, held-breaks-suite; zero surviving edges is a docs-only outcome; dry-run once on the table.
- [ ] 1.5 Later rounds (real reads declared): under 30, strictly shrinking, at most 4 rounds, 150 cumulative PR-wide, round 1 across chains at most 130.
- [ ] 1.6 Shared helper reads: `_CLOSURE_LEAF_*` only for 3 or more spreaders; reveals multiplied by spreaders.

## Phase 2 - one green commit per merged round (at most 4, a chain with real reads commits at its fixpoint)

- [ ] 2.0 Commit the runbook edit (six edits, plan 4.1) with the first round; one combined first report of all chains' round-1 edges, no accept rows, at most 130 (the number of record).

- [ ] 2.1 Accept rows from the last round's `--all-refs` output, one per boundary line, reason names the line kind, inserted in file order; assert rows per pair equals ref lines.
- [ ] 2.2 `git add` new tracked files by pathspec, then `git checkout origin/main -- <baseline>` and prune-only `--print-baseline` to a `.new` file, move it; `ratchet --base origin/main` exit 0; print its wall time.
- [ ] 2.3 Per round: `test-affected-kb-consumers.test.sh` and `scripts/lib/inngest-probe-row.test.sh`; hold an edge that breaks another suite.
- [ ] 2.4 Commit by pathspec with real/accepted/held counts; on a conflicting rebase rebuild from the saved lists and collapse to one commit, recorded.

## Phase 3 - fixpoint and verification (full battery once)

- [ ] 3.1 Final audit equals the last cycle; `stale=0`; `gap_refs` equals `wc -l` baseline; marker `exit=0 reason=pass`.
- [ ] 3.2 Prune-only (file-based diff check; removed lines equal the `declare` set via `comm -23`); inngest-probe-row test untouched, kept pair present by content.
- [ ] 3.3 Scope checks: no test file, workflow, `test-all.sh`, ADR; no `glob:`, `ALWAYS_ON`, prefix; accept diff additions only.
- [ ] 3.4 Recorder on the 5 suites with the most accepted pairs (`audit-suite-reads.sh record --mode check --only ...`, committed HEAD, one attempt); a flip repeats that chain's caps and 3.1 once.
- [ ] 3.5 Replay suite detached.
- [ ] 3.6 Full affected gate detached (kill own stale runs, `--capacity` first); rc 0, not rc 6; re-run after a rebase that moved the index, `test-all.sh` or a suite.
- [ ] 3.7 `test-all-affected.test.sh`, `lint-orphan-test-suites.sh`, shellcheck on the index, `markdown-lint.sh`.
- [ ] 3.8 Quote the final ratchet wall time against 162 s.

## Phase 4 - docs and handoff

- [ ] 4.1 Done in 2.0: runbook section 7, six edits (Never-in-a-drain-PR bullet, Reveal-and-hold-back additions, replace the stale 5-path hold, and the three PR5-only accept-row statements); `grep` for the stale phrases prints nothing.
- [ ] 4.2 Update #10959 body (remaining edges, row-3 cases, PR4c vehicle; as soon as a chain is held); comment on #10861 (PR5 inherits the 152-pair edge, the 43 sweeps with the row-6 policy, `grep-q-pipe-guard`, the brittleness measurement); comment on #10859 with accept-row count before and after plus a line-kind histogram (data only).
- [ ] 4.3 PR body: `Ref #10959` / `Ref #10448` / `Ref #9729` only; counts via `wc -l`; stop-line outcome; accept rows by line kind; held edges by reason; recorder result; window consequence; the two parent-recorded results; holds.

## Phase 5 - ship

- [ ] 5.1 Mark ready after the full gate and replay suite are green; merge via the queue; BEHIND never synced by hand; one re-enqueue on a flaky e2e dequeue.
- [ ] 5.2 After merge: comment on #10865 the merge SHA, `merged_at`, the oracle inputs touched and the window-restart sentence (skip if zero edges survived); `s4-drain` claim released; #10959, #10448, #9729 stay open; `soleur:compound` captures the accept-row learning.
