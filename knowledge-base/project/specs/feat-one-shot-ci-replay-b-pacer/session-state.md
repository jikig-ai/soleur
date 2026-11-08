# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-ci-replay-b-pacer-plan.md
- Status: complete

### Errors
- No spawn tool inside the planning subagent: all prescribed fan-outs ran sequential-fallback inline; technical rows recorded `pending - assumed:` in decision-challenges.md (batched CTO gate follows).
- precommit simulation guard blocked two git commits; repaired via separate `git add` calls.

### Decisions
- Item B reframed by measurement: pristine row_scan_ops ~4.8s — the 47.3s site cost is mutant-side runaway. Plan: per-scan give_up inside cpu(), cheapest-condemner ordering + early exits, text axis ~16KB→~256KB, tighter line-event cap.
- Load-bearing constraints kept: 400k-path corpus and 150k-line baseline untouched; site 350 unchanged.
- row_sym cheap win: parameterize run_sut `timeout 30` → `REPLAY_SUT_TIMEOUT`, row_sym sets 10s (~20s drop on site 225).
- Item A: re-price -a 1033094→160004 + drop ledger-inconsistent exemption row; regen via `--incremental --durations`. -b/-c stale prices out of scope (#11679 umbrella).
- Adjacency: PR #12412 bumps DECLARED_TOTAL→477 / FLOOR_ASSERTIONS→1115 and +1 ordinal shift — re-verify by name after rebase.

### Components Invoked
- soleur:plan, soleur:deepen-plan (sequential-fallback roles inline)
- regenerate-shard-manifest.py --incremental --durations (dry-run), collision-precheck.sh, lint-guard-contract.py
- instrumented /tmp/row_scan_ops_i.py timing run
- Commits: 4e3e61b655, d4ac647af4

## Operator Constraints

- constraint: Repo edits only in .worktrees/ via worktree-manager (bare root CWD).
- constraint: Merge queue governs; arm `gh pr merge --auto` (no --squash). Queued branches reject pushes; dequeue via GraphQL dequeuePullRequest, push, re-arm.
- constraint: The queue ejects entries between batches with no warning; re-arm when OPEN/CLEAN and not queued.
- constraint: Ratchet discipline: edge declarations only for genuinely-read files; anchor-keyed accept rows (12-hex sha256 of whitespace-collapsed line, ordinal in canonical read order) with one of the six typed kinds; verify locally with `python3 -I scripts/ci-pr-affected-replay.py ratchet` before pushing.
- constraint: Non-goals: no .github/workflows/* edits, no oracle-lane work (#12393 sibling, #12418 filed), no #9729 stage-4 activation, no CI_PR_AFFECTED/PR_AFFECTED_LOCKED changes, -b/-c stale prices out of scope (#11679 umbrella).

## Technical Rulings
- cto_spawns=1 (batched, 9 rows): all assumed defaults confirmed, zero dissents; rows rewritten to `Ruled by CTO agent, 2026-11-08` in decision-challenges.md.
