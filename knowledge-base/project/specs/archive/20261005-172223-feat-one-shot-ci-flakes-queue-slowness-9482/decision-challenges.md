# Decision challenges: plan review (2026-10-05)

Taste items surfaced by plan review of the PR-1 plan. The plan's current choice is the default; the operator
may overrule.

1. **Keep the guard's runtime SIGPIPE control?** DHH, code-simplicity and test-design say cut it (tests bash
   semantics; `tests/scripts/test-sentry-full-root-apply.sh:340-380` already owns the control; CI ignores
   SIGPIPE so a default-disposition leg cannot run). The CTO lens leaned keep. Plan choice after deepen:
   CUT, cross-reference T4 in the guard header. Overrule if you want a local control copy.
2. **Depth of PR-2 / PR-3 design inside the PR-1 plan.** DHH and simplicity say reduce to a pointer; the brief
   requires explicit follow-ups and a hypothesis plus evidence per flake. Plan choice: keep the dossier
   evidence (asks 1, 5, 7), shorten the follow-up sections to root cause, direction and tracker.
3. **Order of work.** CTO and DHH note e2e (PR-2) is the larger queue lever. Plan choice: PR-1 first because
   it is investigated and small, PR-2 starts immediately in a separate worktree and is not gated on PR-1.
