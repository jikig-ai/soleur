# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-07-fix-stall-check-correlate-run-to-queue-entry-by-headcommit-oid-plan.md
- Status: complete
- cto_spawns=2 (planning phase, two batched calls: D3-D7 then E1-E3), plus 1 epic-start CTO call before the worktree
- Technical-ruling gate: PASS (12 rows)

### Errors
- Planning subagent: a scripted edit deleted plan sections, caught by the deepen gates and rebuilt. One stray sleep call, harmless.
- Collision pre-check named this branch's own draft PR 12350 (not a competitor).

### Decisions
- Live re-verification 2026-11-07 21:09Z: built queue entries carry headCommit.oid and all merge_group runs on their temp ref have head_sha equal to it; QUEUED entries have a null oid.
- Correction to the brief: failed-load push run 42336368201 exists; its head_sha equals its merge_group siblings. Push-run equals headCommit.oid is transitive, not directly observed. fetch_runs did not carry head_sha, so it is added.
- Design: select the ref by newest created_at first, then verify the candidate head_sha equals the oid. The arm can only turn a named cause into suspected, never the reverse. Null or malformed oid short-circuits with its own notice.
- Suite: 8 mutants C27-C34, expected 153 passes (set from the observed count).
- Residuals accepted: grouped-merge non-deepest member stays suspected; null headCommit on a built entry degrades to suspected (flip evidence D8).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (x2), dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer

## Operator Constraints

- constraint: Use Ref 9927 never Closes for the epic. The PR body says Closes 12320.
- constraint: Guard 1 is merge-blocking. A green push-run of ci.yml is not Guard 1 evidence. Only merge_group or dispatch runs on a SHA are. State run kind and leg with every CI claim.
- constraint: Technical forks go to the CTO agent never the operator. Batch seat dissents from CTO rulings into one CTO call.
- constraint: Review seats that simulate an inherited GIT_DIR use a throwaway repo. After a panel check git log main -1, HEAD, and git config --local --list for leaked user.* or commit.gpgsign.
- constraint: No sleep in Bash and no background polling. Use Monitor. Run gh pr merge as a bare command.
- constraint: After any merge from main run the duplicate YAML key check python3 -I .github/scripts/check-workflow-duplicate-keys.py.
- constraint: Before pushing a PR that changes a test suite run the affected-replay ratchet, fixture-env-adoption test, grep-q-pipe-guard test and the suite run-all registration locally. Batch every fix before pushing. Stage and commit in separate Bash calls. Re-read the PR body after editing it.
- constraint: Do not touch the A6 record, the off-project copy spend decision, host-replace authorisation or dispatch, closing the epic, the inngest_arm_write token, the G2e pin, PR 12275, the CI_ORACLE_LANE variable, or the SOLEUR-DEBT marker in ci.yml.
- constraint: Done requires a merged PR, postmerge verification with merge_group evidence by run kind and leg, deploy arm exact and success, KB archival read-back clean, pipeline-tally.sh show cited, and a Ref-only classification comment on the epic.
- constraint: Operator said in session on 2026-11-07 to rely on CI instead of the local affected battery because the machine is contended. Targeted local gates already passed.
- ci-is-the-gate: Rely on CI instead of the local affected battery as the machine is contended.
