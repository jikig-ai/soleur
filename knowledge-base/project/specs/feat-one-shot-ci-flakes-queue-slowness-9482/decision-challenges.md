# Decision challenges: plan review (2026-10-05)

Taste items surfaced by plan review of the PR-1 plan. The plan's current choice is the default; the operator
may overrule.

1. **Keep the guard's runtime SIGPIPE control?** DHH and code-simplicity say cut it (it tests bash/kernel
   semantics, not repo code; the static pin plus mutation rows already buy the property). The CTO lens and the
   repo's TS7 learning favour keeping one control so the guard proves the environment can exhibit the race.
   Plan choice: keep ONE control (reusing the existing `yes | grep -q y` pattern), with a named
   "environment cannot exhibit the race" result, trimmed of the extra harness-of-harness rows.
2. **Depth of PR-2 / PR-3 design inside the PR-1 plan.** DHH and simplicity say reduce to a pointer; the brief
   requires explicit follow-ups and a hypothesis plus evidence per flake. Plan choice: keep the dossier
   evidence (asks 1, 5, 7), shorten the follow-up sections to root cause, direction and tracker.
3. **Order of work.** CTO and DHH note e2e (PR-2) is the larger queue lever. Plan choice: PR-1 first because
   it is investigated and small, PR-2 starts immediately in a separate worktree and is not gated on PR-1.
