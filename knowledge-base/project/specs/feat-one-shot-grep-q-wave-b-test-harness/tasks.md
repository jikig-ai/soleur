# Tasks: grep -q Wave B (test harness) and producer-side join, slice S1

Plan: `knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md`

Scope of this task list: S1 only (draft PR #9720; 107 sites in 26 in-scope files, 24 edited, the codemod, the ledger edit). Later slices S2 to S7 are separate PRs listed in the plan's Slice Register; each starts from its own Phase 0.

## Phase 0: re-measure (read-only)

- [x] 0.1 Run `bash .claude/hooks/grep-q-pipe-guard.test.sh`; keep the `DEFERRED:` lines (expect ten test rows summing to 804 and six production rows summing to 23).
- [x] 0.2 Re-run the unbounded-producer screen over S1's files; record the command and the count (expect 0).
- [x] 0.3 Count code versus data lines in S1's files; confirm the hand queue (5 data including the `-m` site `pkill-self-match-guard:280`, 1 demo, 3 `-m` in `test-tag-filter.sh`, 98 mechanical).
- [x] 0.4 Derive the merge-trigger table: walk every `.github/workflows/*.yml` `on.push|pull_request.paths` or `paths-ignore` (later patterns override, `!` subtracts) over S1's files (expect no match in any); paste the output in the PR body.
- [x] 0.5 Run `python3 scripts/lint-shell-trace-credential-refusal.py` on `scripts/test-weekly-analytics.sh`, `scripts/test-jaccard-duplicates.sh`, `scripts/lib/test-contention.sh` (expect rc 0).
- [x] 0.6 `uptime`; decide whether local `--affected` is skipped and prepare the PR-body sentence.

## Phase 1: guard and instrument first (red, then green)

- [x] 1.1 Write the demonstration-suspect rule (files naming sigpipe, EPIPE, false-FAIL or broken pipe are never auto-applied) and list the suspects in S1's files.
- [x] 1.2 Add the codemod selftest checks to the guard; they fail because the tool does not exist yet.
- [x] 1.3 Write `scripts/grep-q-drain-codemod.py` (`apply` with a dry run that prints per-tier counts and the hand queue, and `verify`): population via `git grep --column -o` with the guard's strings, cluster parser, one tokenizer plus the demonstration-suspect rule, one-line-in-one-line-out for `apply`, idempotent, dry-run by default.
- [x] 1.4 Selftest fixtures (synthesized): flag cluster classes, refusals (`-m`, `-eq`, data, heredoc, unbounded), about a dozen equivalence rows (bash; dash when present, else UNRESOLVED exit 3) collected into a string asserted empty, idempotency, the `verify` RED fixtures (the Guard 2 matrix) and the empty-diff exit 3. Run the full 1,080-row table once and keep the result for the PR body.
- [x] 1.5 Raise `SWEEP_PROBE_CHECKS` to the new count; confirm no counter or `-lt` floor was added to the guard.

## Phase 2: convert

- [x] 2.1 One conversion commit (the tool does not classify producers by kind, and `verify` covers the whole set; the three-commit ordering was not worth a producer classifier). Deviation recorded in the PR body.
- [x] 2.2 Hand queue: `test-tag-filter.sh` (3 lines, mirror production, add the first-match-not-first-line row); `iac-plan-write-guard.test.sh:268` marker; leave the 5 data lines.
- [x] 2.3 Rows: lower `.claude/*.test.sh` to 5 and `scripts/test-*` to 2 (both `<=`); delete `.github/scripts/test/*`, `scripts/lib/test-*`, `*.test.sh`.
- [x] 2.4 Record every hand edit in the hand-edit list for `verify`, keyed by base-side line range (`path:OLD[-OLD2]:reason`).

## Phase 3: verify

- [x] 3.1 `verify --base origin/main --hand-edits <list>` prints `unexplained: 0`; second `apply` changes 0 lines.
- [x] 3.2 `bash -n` on all 24 edited files; suite pair runs (pristine worktree versus branch) for every suite that runs locally; list the rest.
- [x] 3.3 `bash scripts/pre-push-ratchet-lane.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, the xtrace lint with `--changed --base origin/main`, `bash scripts/test-all.sh --print-selection` for a codemod-only diff.
- [x] 3.4 Re-measure the discoverability command under the 15 s cap.

## Phase 4: mutation battery

- [x] 4.1 Guard 1 matrix (6 rows) hand-applied on scratch copies in a committed worktree after a green control; first failing row recorded from printed output; restore check clean. The Guard 2 matrix is the committed RED fixtures from 1.4.

## Phase 5: evidence and ship notes

- [x] 5.1 Learning files, one per non-obvious finding (confirm each is non-obvious).
- [ ] 5.2 `markdownlint-cli2` on the plan, this file and each learning.
- [ ] 5.3 Ship notes for `soleur:ship`: first PR-body line says merging fires no release and no apply; `Ref #9217`; NOT-fixed list; tracker comment text with the command behind each number; labels `semver:patch`, `type/chore`, `domain/engineering`.
- [ ] 5.3b Cut S2 only after S1 has merged; never re-sync a BEHIND branch mid-flight.
- [ ] 5.4 After merge: `soleur:postmerge` (deploy-arm `find --wait`, then served, must read CONTAINS).

## Later slices (separate PRs, registered in the plan)

- S2 `plugins/soleur/test/*` (140), S3 `scripts/*.test.sh` and `scripts/test-all.sh` (130), S4 `tests/*` (181), S5 plugin skills/scripts tests plus `apps/web-platform` scripts and test/infra (162), S6 `apps/web-platform/infra/*.test.sh` (84) plus the confirmed `cutover-inngest-workflow.test.sh` function-consumer fix, S7 the producer-side join (own plan), then codemod removal.
