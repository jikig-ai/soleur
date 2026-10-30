# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-23-fix-inngest-selfgate-name-failing-phase-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- None blocking. The plan skill's run_in_background poll hook blocked one long container run (rerun in the foreground); a stray `wait` in a measurement script hung one container (killed, script fixed); two decision rows were re-sent to the CTO agent because the ruling gate requires the `Ruled by CTO agent, <date>:` shape (gate now passes, 13 rows).

### Decisions
- Event keeps its `rc= http= attempts=` prefix and appends `phase=<connect|handshake|verify|ca_file|request|status|unknown> tcp= tls= verify=` (fixed tokens or integers clamped to 99).
- Phase derives from the time fields of one four-variable `-w` line (curl 7.19+); the success verdict is decided first; rc is used only for 77 (`ca_file`) and 60 (`verify`) because the same wire event prints rc 52 on curl 8.5.0 and rc 56 on 7.81 and 8.23.
- Measured against real curl 7.81.0, 8.5.0, 8.23.0 and real stunnel 5.72 in containers; the host's real curl version was not read. The incident signature (`rc=56 http=000` after a completed handshake) matches stunnel with its upstream refused: a match, not proof of the 2026-10-23 cause.
- Honest mocks: both curl doubles read one shared profile table and one printer (`test-fixtures/curl-w-profiles.sh`); an unknown `-w` variable exits 99 and drops a sentinel every suite asserts absent; a real-curl differential row; 20 mutation rows (M22a-M22t).
- Ratchets to re-measure from green runs: BASELINE_DECLARED_PROBES, MIN_ROWS (exact), CI_DEPLOY_ASSERT_FLOOR, fixture-relative and grep-q-pipe-guard baselines. The self-gate rows live in inngest-link-resolver.test.sh.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer, soleur:engineering:cto (four consults), learnings-researcher, functional-discovery.
