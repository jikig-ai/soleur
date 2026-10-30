# Decision Challenges — feat-one-shot-11600-job-log-step-attribution

Headless one-shot pipeline (no TTY, no agent-spawn tool in the Devin planning
subagent). `Reviewed-Coverage: sequential-fallback` — gates that prescribe
spawned agents (advisor consult, domain leaders, plan-review panel, functional
discovery) were adjudicated sequentially inline by the planning orchestrator.

## Mechanism adoptions (not rulings)

The design carries no open technical fork. Every load-bearing choice is either
prescribed verbatim by issue #11600's own fix sketch or forced by semantics the
probe already implements — recording them as challenges would manufacture
discretion that does not exist:

- Region-slice anchor (`##[group]Run` header `ts >= started_at[0:19]`, EOF or
  next-header bound, global BOM/CR strip): prescribed by the issue and proven on
  `origin/main` at `git-data-boot-poll-8178.sh:202-209`.
- Conclusion-agnostic recovery: the probe already populates `BOOT_EPOCH` from
  any parsed trail regardless of job conclusion (`web-first-deploy-10585.sh`
  Step 1); conditioning recovery on `jcon` would be new machinery buying no
  property (Phase 0.6b cut-list logic).
- Shared emit-filter across both paths: single chokepoint for the #9905
  ANSI-echo rule; a second copy is the drift vector, not an option.
- Tripwire wording keeps the `zero parseable` substring: the suite's checks
  grep that fixed string — a compatibility constraint, not a choice.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Sibling step-anchored probes (`web-fresh-boot-zot-8651.sh`, `git-data-rehearsal-evidence.sh`) deferred to a follow-up issue rather than folded into this PR | operator (scope) | surfaced to operator — the plan defers both to a follow-up issue filed during work because #11600 scopes its acceptance to web-first-deploy-10585; the alternative is folding them into this PR |
