# Tasks: sync-pr-behind.sh base-branch rules read and one bounds helper (Ref #10832, Ref #9454)

Plan: `knowledge-base/project/plans/2026-10-23-fix-sync-pr-behind-base-branch-rules-and-bounds-helper-plan.md`. Decisions: `knowledge-base/project/specs/feat-one-shot-10832-sync-pr-behind-base-and-helpers/decision-challenges.md` (F1-F7). Never use a closing keyword for #9454 or #10832.

## Phase 0: RED tests and request-shape-compatible mock widening (test-only commit)

- [ ] 0.1 Read `plugins/soleur/test/sync-pr-behind.test.sh` stubs (`install_gh`, `install_gh_wait`, `install_rules`) and baseline the suite: `bash plugins/soleur/test/sync-pr-behind.test.sh` must end `=== 172 passed, 0 failed ===`.
- [ ] 0.2 Capture golden texts from the PRE-change script: the `kind=queue_wait` refusal line and the `qw_unreadable` text for base `main`; paste them as literals into the suite.
- [ ] 0.3 Stub widening (green against the old script): runtime `pr-base` file (default `main`, `__none__` = head only) read by `install_gh` and `install_gh_wait`; `*headRefName*` arm answers `<head> <base>` only when argv names `baseRefName`; raw pr view JSON gains `baseRefName` and the "delete fields not in `--json`" loop covers it; keep the `ok:<STATE MERGESTATE>:<armed|disarmed>` split unchanged; `install_rules` applies its mode only to the branch in a `rules-branch` file (default `main`, others answer `[]`), decoding `%2F`.
- [ ] 0.4 Recording `timeout` and `sleep` shims in a separate bin used only by characterization fixtures (never in hang-mode fixtures).
- [ ] 0.5 Characterization rows (green before and after), ids C1-C7: C1 timeout table via `--queue-state` (unset, 7, 0, abc to 10, 7, 10, 10); C2 attempts table via a failing rules read (unset, 1, 3, 0, abc to 2, 1, 3, 2, 2); C3 nap table via `queue_wait_eval` (unset, 5, 0, abc to 2, 5, 0, 2); C4 timeout via `--queue-wait` pr view; C5 timeout via the rules read; C6 attempts via `queue_state_read` (`gqlfail`); C7 nap via `queue_read_settled` (marker dequeue). Each nap case sets `PR_QUEUE_RETRY_SLEEP` explicitly or `unset`s it.
- [ ] 0.6 Sentinel row S1: with whole-line comments and the `USAGE` heredoc stripped, `tr -c '[:alnum:] ._:/=-'` `== 1`; each of `${PR_QUEUE_TIMEOUT:-`, `${PR_QUEUE_ATTEMPTS:-`, `${PR_QUEUE_RETRY_SLEEP:-` `== 1` via `grep -o | wc -l`; `rules/branches/main` `== 0`; plus an anti-vacuity run of the counting function on an empty file.
- [ ] 0.7 Base rows (RED), ids N1..N8 with sub-rows: N1s flagless `--step` develop+queue-on-develop (exit 14, path develop); N1w `--queue-wait` (`queue_wait`); N2s develop+queue-only-on-main flagless `--step` (exit 4 non-main refusal); N2w `--queue-wait` (`queue_wait`); N2l standalone loop (exit 4); N3a `release/1.x` (path `release%2F1.x`); N3b `feat/x/y`; N4 unsupported-base table (`feat%2Fx`, `a?b`, `a..b`, `x.lock`, empty base, loop head read `__none__`); N5a disarmed develop syncs; N5b disarmed `rel+1` syncs and `--queue-wait` prints `proceed`; N6 loop develop+queue-on-develop (`kind=queue_wait rc=0`); N7a main refusal golden; N7b main unreadable golden; N7c develop refusal names `develop`; N8 snapshot answers with no base or extra tokens (rc 4).
- [ ] 0.8 Mutation and harness rows (RED until Phases 1-2) with unique-fragment anchors: G1 mutants M1 literal-main, M2 empty base at all callers, M3 loop passes `main`, M4 queue-wait passes empty, M5 no `%2F`, M6 no allowlist, M7 reorder before armed, M8/M9/M10 refusal removed at step_guard / queue_wait_gate / `--queue-wait`, H1 rules stub ignores branch; G2 mutants M11 inline env reads re-added, M12 fourth reader, M13/M14/M15 `qb_clean` removed at each of the three sites, M16 `queue_read_settled` raw nap, H2 non-recording `timeout` shim; plus mutation-control rows for the two new scenarios (G1, G2) and the re-pointed `tr -c` and snapshot-regex anchors.
- [ ] 0.9 Mock widening in the other suites (green against the old script): `.claude/hooks/pre-merge-rebase.test.sh` (`mss-<N>` fourth token default `main`, body `baseRefName`, field loop, comments at l.912 and l.2117); `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (snapshot data gains `"baseRefName":"main"`); `plugins/soleur/scripts/sync-pr-behind.test.sh` (`headRefName*` arm); stale comment at `plugins/soleur/test/sync-pr-behind.test.sh` l.1301.
- [ ] 0.10 Run every edited suite against the unchanged script: pre-existing rows green (control first), new base, sentinel and mutation rows red. Record the failing row names. Commit as test-only.

## Phase 1: GREEN - one bounds helper, one sanitiser (behaviour-preserving)

- [ ] 1.1 Add `qb_bounds` and `qb_clean` exactly as in the plan's prescribed source shape; replace the four clamp copies (`queue_state_read`, `queue_read_settled`, `queue_wait_eval`, `qw_snapshot`) and the three `tr -c` copies; use `QB_*` directly.
- [ ] 1.2 Re-point the `tr -c` mutation anchor; confirm C1-C7 stay green and S1's clamp, env-read and sanitiser clauses go green.
- [ ] 1.3 `shellcheck -x plugins/soleur/scripts/sync-pr-behind.sh` clean; suite green except the base rows, S1's `rules/branches/main == 0` clause and the snapshot-regex mutant.

## Phase 2: GREEN - base plumbing and the interim refusal

- [ ] 2.1 `qw_snapshot`: `--json state,mergeStateStatus,autoMergeRequest,baseRefName`, `--jq` with `.baseRefName // ""`, strict regex with a loose `[^[:space:]]+` base token, `read -r` into `QW_STATE`, `QW_ARMED`, `QW_BASEREF`.
- [ ] 2.2 `qw_base_path` (with `local LC_ALL=C`) and `qw_base_foreign`; `queue_wait_eval <state_line> <armed> <base>`: reset `QW_BASE` at the top, validate after the armed check, set `QW_BASE` after validation, `$4` path operand, sanitised and truncated detail on failure.
- [ ] 2.3 Callers: `step_guard` and the `--queue-wait` mode pass `$QW_BASEREF`; widen the standalone loop's pre-loop read to `headRefName,baseRefName` with `read -r head_ref LOOP_BASE`; `queue_wait_gate` passes `$LOOP_BASE`; comment that the loop resolves the base once.
- [ ] 2.4 Interim refusal after `proceed` when `qw_base_foreign`: `step_guard` and `queue_wait_gate` print `kind=gh` rc 4 and exit 4 (text: base is `<base>`, not `main`; `sync_step` only merges `origin/main`; sync by hand or retarget); `--queue-wait` prints `queue_wait` and exits 0. Not in `--fence`, `sync_step` or `queue_wait_eval`.
- [ ] 2.5 `qw_refusal` / `qw_unreadable`: interpolate `QW_BASE` (`${QW_BASE:-its base branch}` in `qw_unreadable`); byte-identical for `main`.
- [ ] 2.6 Header l.53, `--help` l.99 / l.118-119 / l.135 and the `queue_wait_eval` comment: PR's own base branch, name `baseRefName`; keep every pinned `--help` substring (`--fence`, `--queue-wait`, `^  14 .*kind=queue_wait`, `^  11 .*kind=noop`, `^  4 .*kind=gh`, `should a sync be skipped`, `is the PR in the queue`, `nobody else`, `merge queue`).
- [ ] 2.7 Update the `PASS -eq` pin to 172 plus the new rows (count them from the ids above; list the ids in the commit message).
- [ ] 2.8 Run all suites: `bash plugins/soleur/test/sync-pr-behind.test.sh`, `bash plugins/soleur/scripts/sync-pr-behind.test.sh`, `bash .claude/hooks/pre-merge-rebase.test.sh`, `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `bash plugins/soleur/test/monitor-pr-checks.test.sh`; `EXPECTED_CASES=77` and `MIN_VERDICTS=1123` unchanged.

## Phase 3: Documentation, ADR addendum, tracking issue

- [ ] 3.1 `.claude/hooks/pre-merge-rebase.sh` l.757-758 comment and `plugins/soleur/skills/ship/references/queue-mode.md` l.7: the PR's own base branch.
- [ ] 3.2 File the tracking issue (`gh issue create`; verify labels with `gh label list --limit 200`; milestone from `knowledge-base/product/roadmap.md`) for `sync_step`'s `origin/main` merge, the hook's own merge and `queue_wait` context text, the fences' inline `main` reads and `pr-merge-poll.ts`; Ref #9454 and Ref #10832 only.
- [ ] 3.3 Append the short ADR-270 addendum via `soleur:architecture` (residual 6 closed, four-field snapshot, interim non-`main` refusal, what still reads `main`, tracking issue number). No C4 change.
- [ ] 3.4 `npx markdownlint-cli2` on the plan, this file and the ADR; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-10832-sync-pr-behind-base-and-helpers`.

## Phase 4: Verify out-of-scope and ship

- [ ] 4.1 `git diff --stat origin/main...HEAD -- scripts/lib/test-affected-paths.sh scripts/suite-durations.tsv scripts/suite-durations.tsv.n scripts/suite-shard-legs.tsv scripts/suite-shard-legs.tsv.n .claude/rule-weakening-acks.txt AGENTS.rules.md AGENTS.md` prints nothing.
- [ ] 4.2 PR body: `Ref #9454`, `Ref #10832`, no closing keyword; names the interim non-`main` refusal as a deliberate narrowing; links the tracking issue.
- [ ] 4.3 Merge via the queue with `session-state.sh with_lock merge-main` (ship owns the exact form); after MERGED verify `git grep -c 'rules/branches/main' origin/main -- plugins/soleur/scripts/sync-pr-behind.sh` prints 0, then close #10832 by hand with an evidence comment. Leave #9454 open; leave #9482, #10245 and #5840 untouched.
