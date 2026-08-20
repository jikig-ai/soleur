# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-20-fix-apply-infra-failure-channel-and-arm-deadline-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Harness degradation (load-bearing context for later phases)
The `soleur:*` plugin skills were dropped from this Claude Code session when the plugin
subsystem cycled mid-run (the plugin is registered from the local repo, not from
`enabledPlugins`, so it did not return with the MCP reconnect). `Skill(soleur:plan)`
returns `Unknown skill`. Every pipeline phase from Step 1 onward therefore executes its
`plugins/soleur/skills/<name>/SKILL.md` read from disk and followed verbatim, in an
isolated subagent — NOT an improvised subset. Deregistered `soleur:engineering:*` agents
are substituted by `general-purpose` agents carrying each agent's own definition.

### Errors
- Agent substitutions (harness): repo-research-analyst, learnings-researcher, cto, coo, cpo,
  dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
  observability-coverage-reviewer, architecture-strategist, security-sentinel,
  test-design-reviewer, plus the Phase 4.45 passes.
- Deepen Phase 5 fan-out scoped, not exhaustive: 8 of ~23 agents across two rounds;
  omitted agents whose domain is provably absent from a YAML/TS-test/Markdown diff
  (data-migration-expert, ddd-architect, semgrep-sast, legacy-code-expert,
  agent-native-reviewer, data-integrity-guardian). Recorded as a deliberate deviation.
- `iac-plan-write-guard.sh` rejected the first plan write on the literal `out-of-band`;
  reworded at source rather than using the `iac-routing-ack` opt-out.
- Self-inflicted regression caught by its own gate: a Guard 2 rewrite broke the required
  `**Assembly.**` field marker; `lint-guard-contract.py` failed and it was restored.
- Unverifiable from the repo, carried into tasks.md Phase 0.6 for empirical re-confirmation:
  `git_data_prd`'s tfstate absence, and `$RUNNER_TEMP` step-persistence. Both load-bearing.

### Decisions
- Separate `notify-apply-failure` job, NOT the issue's `if: failure()` step arm. Measured on
  run 32168637847: a timed-out job concludes `cancelled`, its `failure()` step is `skipped`
  while `always()` steps run — the step arm is structurally silent on exactly the #7587 path.
- Deadline resize (230s -> ~30s) instead of the brief's `inngest_consumer` short-circuit.
  UC-1 in decision-challenges.md. ACCEPTED by the pipeline owner as a technical fork:
  a short-circuit never re-tests, so nothing re-arms once #7228 closes; and the live
  `gh issue view` gate would need `issues: read` on the job holding prod Doppler secrets
  and the fleet-wide apply mutex. ADR-100 records #7228 cannot close until #7462 lands.
- Job budget raised 15 -> 30 min, sized by a two-part inequality with a measured p95
  pre-gate of 111s. Per-merge queue wait is NOT yet measured -- /work measures it before
  relying on the raise.
- `brand_survival_threshold: aggregate pattern` on verified precedent (the post-mortem for
  this same workflow and defect class declares that value). `user-impact-reviewer` retained
  voluntarily as the give-back.
- Scope grew by two files (extracted `arm-heartbeats.sh` + its test) because Guard 2 was
  otherwise satisfiable by a decoy `date +%s`.
- Burst suppression and the green-again email deferred to a repo-wide `workflow_run`
  catch-all, which also closes this plan's run-level-cancellation residual.

### Components Invoked
plan/SKILL.md (Phases 0-6, from disk); plan-review/SKILL.md; deepen-plan/SKILL.md
(halt gates 4.5-4.11 + fan-out); plan-network-outage-checklist.md; plan-issue-templates.md;
plan-community-discovery.md; plan-functional-overlap.md; brainstorm-domain-config.md;
ui-surface-terms.md; lint-guard-contract.py; lint-infra-no-human-steps.py; probe-verb-gate.sh;
13 substituted agents; gh run/job/issue/PR APIs.
