# Tasks: S4 affected-index PR4c, the remaining held-back edges (Ref #10959, Ref #10448, Ref #9729)

Plan: `knowledge-base/project/plans/2026-10-26-ci-s4-affected-index-pr4c-held-back-edges-plan.md`. Rulings: `decision-challenges.md` in this directory (CTO rows 1-6, 2026-10-26; PR4b rows 1-16 still bind).
Holds: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no criterion-c measurement, no flip PR.
Process: run long commands detached (script file with `setsid nohup bash <file>` or `run_in_background`, rc file, one `until` loop); `grep -q P < <(producer)`; no `git stash`; stage by explicit pathspec; `CI_PR_AFFECTED` unset; push a WIP and re-acquire the lease (`acquire_lease`) before every long wait; no new comment lines in `scripts/lib/test-affected-paths.sh`; avoid the hook-denied forms (recursive delete with a variable, process-pattern search or kill, such text inside a heredoc).

## Phase 0 - claim, base, lease, calibrate (no index edit)

- [ ] 0.1 `gh pr list --label s4-drain --state open` returns only #11131; mirror comment on #10448 present; `git fetch origin main`, merge if moved; sibling-overlap loop; acquire the lease and assert the lease file.
- [ ] 0.2 Measure the base on a detached worktree of `origin/main` (`ratchet --report`, `audit --all-refs --accept`); save `receipts/ratchet-base-<sha12>.out`.
- [ ] 0.3 Build `receipts/edges-decisions.tsv` (suite, F, outcome, reason, chain, shared_ref, accept_rows, extra_drained, commits_90d_F, declaring_suites) from `receipts/worklist-edges.tsv`; membership test (105 baselined); recompute `commits_90d` for every F into `receipts/commits-90d.txt`; array names via `_aff_label_map`, new blocks (at most 3), label-map collisions; pre-flag hot-F exception candidates; `declaring_suites` includes PR4d consumers.
- [ ] 0.4 One recorder pass (index asserted equal to `origin/main`) over every candidate slice suite plus two standby suites (`t5-skip`, `battery-tag-authorship`); `load_refused` gets `recorder-load-refused` and one deferred retry; (`audit-suite-reads.sh record --mode check --only ...` on the committed HEAD) plus suite-text proofs for the `declared-F-never-opened` edges; one attempt each; evidence in `receipts/retest/`; failures become `recorder-unreliable-2` / `declared-F-never-opened-2` and go to PR5.
- [ ] 0.5 Cut the slice once at a round-1 sum of 130 (ascending, no skipping ahead); chains C1 57 / C2 30 / C3 30 (shared ref files share a chain, `shared_ref` empty across chains); mark `held-ceiling` and `held-pr5` (`grep-q-pipe-guard`, birth-readiness).

## Phase 1 - per chain: declare, first report, pre-classify

- [ ] 1.1 Scratch worktree: declare the chain's edges (existing arrays, at most 3 new blocks appended at EOF), no accept rows, `ratchet --report` (exit 1 expected); suites with `new-pair`/`stale-line` are a subset of the chain; save `receipts/chain-<k>-round-<n>-first-report.txt`; 60 or more means bisect.
- [ ] 1.2 `audit --root <scratch worktree> --all-refs --accept <main's accept file>` for the boundary lines.
- [ ] 1.3 `receipts/reveals-decisions.tsv`: each revealed pair real-read or mention with the cited `file:line`, line kind, recorder evidence; unsure holds the whole edge.
- [ ] 1.4 Hold rules (any hold removes the edge and its sole-parent real reads and re-runs the chain from round 1; `parent_edge` column): more than 10 accept rows; any accept row on a hot file (F, the mention-line file, the real-read file); hot F with zero rows only if all real reads and `commits_90d x declaring suites <= about 72`; dry-run once on the table; zero `declare` rows means a docs-only PR.
- [ ] 1.5 Later rounds: under 30, strictly shrinking, at most 4 rounds, cumulative at most 150 (running total in ascending chain order), round 1 summed over chains at most 130.
- [ ] 1.6 Shared helper reads: `_CLOSURE_LEAF_*` only for 3 or more spreaders; never edit a leaf array.

## Phase 2 - one green commit per surviving chain

- [ ] 2.0 Number of record = sum over chains of post-hold round-1 totals (at most 130); one combined `--report` before the first chain commit must equal the union of the per-chain reports.
- [ ] 2.1 Accept rows from the last round's `--all-refs` output (one per boundary line, reason names the line kind), inserted in the file's order (`sort -c` first); save `receipts/accept-rows.tsv`.
- [ ] 2.2 `git checkout origin/main -- <baseline>`, prune-only `--print-baseline` via a `.new` file, `git add` baseline/accept/index/new tracked files, `ratchet --base origin/main` exit 0; print wall; re-check from a detached clean worktree of the commit.
- [ ] 2.3 Per commit: `ratchet`, `scripts/test-affected-kb-consumers.test.sh`, `scripts/lib/inngest-probe-row.test.sh`.
- [ ] 2.4 Commit by explicit pathspec with real/accepted/held counts; WIP commits before waits hold receipts and docs only.

## Phase 3 - fixpoint and verification

- [ ] 3.1 Final audit equals the last cycle, `stale=0`, `gap_refs == wc -l` baseline, marker `exit=0 reason=pass`.
- [ ] 3.2 Prune-only baseline diff (file-based), removed lines = `declare` rows + `extra_drained`; `inngest-probe-row.test.sh` untouched, kept pair present.
- [ ] 3.3 Scope checks (no test file, workflow, `test-all.sh`, ADR; no `glob:`, `ALWAYS_ON`, prefix, new index comment; accept diff additions only).
- [ ] 3.4 Replay suite detached.
- [ ] 3.5 Full affected gate detached and non-blocking (`SOLEUR_ALLOW_FULL_GATE=1 ... --affected`, rc from the rc file); CI `test` context is the merge gate.
- [ ] 3.6 `test-all-affected.test.sh`, `lint-orphan-test-suites.sh`, shellcheck, `markdown-lint.sh`; duplicate `AFFECTED_*_PATHS` names none.
- [ ] 3.7 Quote the final local `ratchet` wall next to the base wall.

## Phase 4 - documentation and handoff

- [ ] 4.1 Runbook section 7 edits (last docs commit, conditional on the declared count N: PR4d wording only if N is at least 10, no edit at zero); `grep -nE 'PR4b and PR4c|PR4c or PR5'` prints nothing when N is at least 10.
- [ ] 4.2 Update #10959 (remaining edges by reason code, PR4d eligibility, series end); comment on #10861 (PR5 handoff by name).
- [ ] 4.3 PR body: `Ref` only, counts via `wc -l`, chain table, stop-line outcome, accept rows by line kind, holds by reason code, re-test results, yield, declared N and PR4d eligibility, series end, local gate state, holds.

## Phase 5 - ship

- [ ] 5.1 Before arming: merge `origin/main`; re-insert accept rows (from `receipts/accept-rows.tsv`) THEN regenerate the baseline (prune-only); intersect sibling PR files and the merge diff with the receipts file set (re-record or hold affected suites); re-run `commits-90d`; ratchet/3.1/edge-batch suites/duplicate-array check (3.4 only if replay files changed, never 3.5); re-acquire lease; push; mark ready; ONE evidence comment (ancestor check, lease `ls`, head SHA); `gh pr merge 11131 --squash --auto`; no push after arming; re-acquire the lease while queued; sibling-dequeue playbook at most 2 cycles, then draft + comment on #10959.
- [ ] 5.2 After merge: comment merge SHA, `merged_at`, oracle inputs and the window-restart sentence on #10865 (skip at zero edges); claim released; #10959, #10448, #9729 stay open; file PR4d only if N is at least 10; `soleur:compound` at ship.
