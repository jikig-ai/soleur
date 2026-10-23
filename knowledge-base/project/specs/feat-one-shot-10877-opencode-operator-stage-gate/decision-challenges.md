# Decision challenges — plan review panel

Plan: `knowledge-base/project/plans/2026-10-23-fix-opencode-operator-stage-gate-plan.md`
Panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer` (engineering), `cto` (devex), `cpo` (product) — inline at depth 1 on OpenCode (`Reviewed-Coverage: sequential-fallback`).

## Decision Classes

| Item | Class | Ruling |
| --- | --- | --- |
| Predicate in `soleur_op_in_agent_harness()` tests `OPENCODE` alongside `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` without testing generic `AI_AGENT` | technical | Ruled by CTO agent, 2026-10-23: Test `[[ -n "${CLAUDECODE:-}" \|\| -n "${CLAUDE_CODE_ENTRYPOINT:-}" \|\| -n "${OPENCODE:-}" ]]` in `soleur_op_in_agent_harness()` - OpenCode injects `OPENCODE=1` into every `shell` child process (`opencode v2.1.2` measurement), and `plugins/soleur/lib/harness.ts` (`detectHarness`) explicitly avoids `AI_AGENT` as a primary predicate because the variable name is generic |
| Keep `surface="${CLAUDE_CODE_ENTRYPOINT:-unknown}"` unchanged in `soleur_op_stage_gate` rather than widening `surface=` in this PR | technical | Ruled by CTO agent, 2026-10-23: Keep `surface` assignment in `soleur_op_stage_gate` unchanged and scrub `-u OPENCODE` in `pty_drive` and `g11_pty` - `#10877` scopes only `soleur_op_in_agent_harness()` and `SKILL.md` receipt qualification, and keeping `surface` untouched avoids unrequested ledger schema drift |
| Update `plugins/soleur/scripts/sync-opencode-adapter.ts` and regenerate `plugins/soleur/opencode/INSTRUCTIONS.md` in the same PR as `soleur_op_in_agent_harness()` | technical | Ruled by CTO agent, 2026-10-23: Update `sync-opencode-adapter.ts` and regenerate `opencode/INSTRUCTIONS.md` in the same PR - `opencode/INSTRUCTIONS.md` currently states `soleur_op_in_agent_harness` recognises only `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT`, which becomes false the moment `soleur_op_in_agent_harness()` recognises `OPENCODE` |
