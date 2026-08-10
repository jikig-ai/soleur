# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-09-fix-worktree-create-acquires-lease-plan.md
- Status: complete

### Errors
None.

### Decisions
- Test home is `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` (floor 3 -> 6), not `session-state.test.sh`: the defect is in a plugin script's call site, not in the hooks-library primitives, which are correct here.
- Deliberate deviation from the operator's probe recipe, compensated: a hermetic fixture test for CI *plus* the operator's live scratch-worktree probe run once as AC7. The recipe is right for one-time live verification, wrong for a committed CI test (network, 13,354-file `install_deps` cost).
- ~~Fix held to exact parity with `create_for_feature`; no shared-helper extraction.~~ **SUPERSEDED.** A helper (`_acquire_worktree_lease`) WAS extracted and `create_for_feature` WAS touched: the CONCUR gate took the sites from two to four, and the review then required trap-gating, artifact verification and a telemetry marker at each, so the block stopped being "six legible lines".
- Correcting the `session-state.sh` comment is in scope: it asserted `create_worktree` acquires the lease, which it did not (it does now). Its twin in `session-state.test.sh` T15 and the sweep-reachability note ~110 lines above were corrected too — marking one block and leaving its twin is worse than marking neither. That misattribution is why the second half of the defect survived the first fix.
- ~~Adjacent findings deferred to ONE follow-up issue; net-issue-flow files 1.~~ **SUPERSEDED.** The mandated CONCUR gate DISSENTED on both: the early-return arm was fixed inline (it was an unmet goal of this PR, not a follow-up), and the vanishing-lease durability gap became a `/compound` learning because no change to `main` can retire an old checkout still running `cleanup-merged`. Net-issue-flow: 0 filed, 0 closed, no override needed. NOTE the causation there is **probable, not proven** — the falsifying experiment is to purge the stale worktrees and see whether leases still vanish.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agent: soleur:engineering:review:kieran-rails-reviewer (correctness -- no defects)
- Agent: soleur:engineering:review:code-simplicity-reviewer (YAGNI/scope -- nothing cut, two refinements folded in)

## Parent-session context (not produced by the planning subagent)
- Scope narrowed to Part 1 by operator decision. PR #7343 / branch
  `feat-one-shot-7278-registry-restart-lever` is owned by a concurrent sibling
  session (PID 1413692) which holds its lease and worktree. Not touched here.
- Defect reproduced live this session: a `--yes create` worktree checked out all
  13,354 files and was destroyed before `verify_worktree_created` ran, emitting
  `SOLEUR_GIT_WORKTREE_VERIFY_FAILED reason=not-a-worktree`. Branch survived,
  working tree did not.
- Premise verified against merged blobs via `git show origin/main:<path>` (NOT
  the bare root's stale synced mirror): `acquire_lease` at line 1402 and
  `_register_lease_release_trap` at 1407 both sit inside `create_for_feature`
  (starts 1309); `create_worktree` (1212-1308) has neither. Dispatch at 2399
  (`create`) / 2402 (`feature|feat`).
- Predecessor trap fix confirmed present using the absence anchor, not a
  presence grep: `session-state.sh:501` is
  `trap "_lease_release_safe '$worktree'" INT TERM HUP` -- no `EXIT`.
