# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-31-infra-inngest-batch1-guard-deadletter-posture-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- iac-plan-write-guard denied the plan Write twice on the verbatim `## Operator Holds` text; resolved with the sanctioned `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` literal (no new infra, no .tf edit prescribed).
- **Worktree destruction incident (planning subagent):** subagent's mid-session `git checkout` flipped the ROOT checkout onto the feature branch, committed the three artifacts under `.worktrees/<name>/` paths (gitignored → `git add -f`), and the linked worktree was destroyed in the process. Recovered: recreated worktree, `git mv`'d the three files to correct KB paths (commit 4e390ec17b), root restored to main.
- No Agent/Task tool in this harness — plan-review panel, domain leaders, deepen fan-outs could not be spawned; halt gates run in-process; unspawned seats recorded as `pending - assumed:` rows.
- `scripts/lint-guard-contract.py` not found on this branch — guard contract verified manually.
- Residual: tasks.md has several MD013 (>80 col) lines — fold at work time if lefthook enforces.

### Decisions
- #11528: adopt sibling-guard (PR #11601) conventions — canonical-equality SQL compare (WRONGVOLUME_CANON), res_block()/param() exactly-once pins, VAR_BLOCK opener count==1, PRESENCE_ROWS/MUT_ROWS, _red_verdict/mutate_green/mutate_floor_red; family remainder filed as an issue in Phase 4.
- #11528 gap 5: pin `env -u MUT_SKIP -u <PREFIX>_GUARD_*` on the wrong-volume and key-probe run lines of infra-validation.yml.
- #8841: move reportSpawnDeadLetter after the persist-failure catch (file's own settle convention :1641); replay regression test via runLikeInngest asserting deadLetters()==1, invocations>=2.
- #9139: partially landed already (PR #11487) — amend connections[6] enforced_at += route.ts serveOrigin; connections[5] verify-only; no C4/ADR change.
- Co-rider inngest-verify-clean-10390.sh already deleted on main (PR #11381) — descoped to residual-zero AC.
- CTO batching ruling recorded in decision-challenges.md (Ruled by CTO agent, 2026-10-31).

### Components Invoked
- soleur:plan, soleur:deepen-plan (in-process halt gates)
- CTO spawn #1 (Own the epic): holds classification + batching ruling
- Files committed: 7aa59ed8b4 (mis-pathed), 4e390ec17b (relocation fix), pushed
