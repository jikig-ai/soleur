# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3040-v2-cc-hardening/knowledge-base/project/plans/2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md
- Status: complete

### Errors
- Worktree at `.worktrees/feat-one-shot-3040-v2-cc-hardening` was stale (gitdir pointer referenced a `.git/worktrees/` entry that did not exist; only the working-tree directory remained). Recovered by removing the dangling directory, running `git worktree prune`, and recreating with `git worktree add ... -b feat-one-shot-3040-v2-cc-hardening main`. All subsequent steps ran cleanly.

### Decisions
- **Finding 1 (safe-bash extraction):** chose **Approach A** (extract regex grammar to `safe-bash.ts` sibling module per `tool-tiers.ts` / `tool-path-checker.ts` precedent) over **B** (fixed-string Set rewrite) — preserves grammar that #3344 will extend, keeps 107-case test surface intact. Kept `NEAR_MISS_STATE: WeakMap<CanUseToolContext, …>` in `permission-callback.ts` to avoid cyclic import against `CanUseToolContext`.
- **Finding 2 (mirror debounce):** rejected both stated approaches; **folded in open issue #3369** which proposes the canonical extraction of `mirrorWithDebounce` to `observability.ts`. PR closes both #3040 and #3369. `notifyAwaitingUser`'s no-active-query branch routes through `mirrorWithDebounce(..., "unknown", "notify-awaiting-no-active-query")` — `userId` is unknowable when no `state` exists; the `"unknown"` flood-coalesces correctly.
- **Finding 3 (idle-reaper):** chose **Approach B** (skip reaper entries where `awaitingUser === true`) over **A** (bump `lastActivityAt = now()`) — A would muddle the observable contract of `lastActivityAt`.
- **Finding 4 (wall-clock budget):** chose **Approach A** (preserve `firstToolUseAt`, subtract `totalPausedMs + (pausedAt ? now() - pausedAt : 0)` from elapsed at fire time) over **B** (accept per-window semantics). Per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`, Approach B would be a second defense-relaxation that dissolves the chatty-flap-runaway role. Re-arm-on-too-early-fire shape over arm-time-effective-anchor; the absolute 10-min `DEFAULT_MAX_TURN_DURATION_MS` ceiling is preserved with the same cumulative semantic.
- **Deepen-pass surfaced load-bearing test drift:** existing test at `soleur-go-runner-awaiting-user.test.ts:291` ("AC9: only ACTIVE compute time counts") + line 407 silent-fallback test + 4 sibling doc-comment sites pin the per-window semantic and must be REWRITTEN (not just extended) — promoted to explicit AC8 + Phase 4 task 4.6 with a verification grep.

### Components Invoked
- Skill: `soleur:plan` (this session)
- Skill: `soleur:deepen-plan` (this session)
- Bash: `gh issue view` / `gh pr view` (live-verified #3020, #3225, #3040, #3369, #3344, #3343)
- Bash: `gh issue list --label code-review --json` + `jq` for Phase 1.7.5 code-review overlap check
- Bash: `grep` / `git grep` / `find` / `ls` / `wc` (touchpoint and learning discovery)
- Read: `permission-callback.ts`, `soleur-go-runner.ts`, `cc-dispatcher.ts`, `review-gate.ts`, `soleur-go-runner-awaiting-user.test.ts`, AGENTS.md (via CLAUDE.md include), `2026-05-05-defense-relaxation-must-name-new-ceiling.md`, `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`
- Write: `2026-05-11-fix-cc-hardening-safe-bash-mirror-reaper-wallclock-plan.md`, `tasks.md`
- Edit: deepen-pass enhancements (Enhancement Summary, Files to Edit, Tests to Edit, AC renumbering, Phase 3/4 tasks, Research Insights section)
- Git: worktree recovery (`prune` + `worktree add`), 2 commits, push
