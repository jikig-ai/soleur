# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-chore-reconcile-agents-rule-budget-rubric-with-linter-plan.md
- Status: complete

### Errors
None. Two notes surfaced:
- Pre-existing red, unrelated to this work: `scripts/lint-agents-enforcement-tags.py` exits 1 on the current tree (12 unresolved `[skill-enforced:]` anchors) and is wired only in lefthook, not CI — so it silently fails to gate. Any PR staging an `AGENTS*.md` file is blocked at pre-commit by a failure it did not cause. Filed as a deferral; the plan avoids `AGENTS*.md` entirely to stay clear of it.
- One Write was correctly blocked by the bare-root guard and redirected into the worktree.

### Decisions
- The issue's numbers were all wrong and the payload is NOT over budget. Measured `B_ALWAYS=22900` (6072 + 16828, frontmatter-stripped) against a real reject threshold of 23000 — so no demote/prune is in scope. Registry is 202 rules / 43513 B (issue claimed 198 / 42142).
- "98/198 unused" is a category error: it is 98 of 101 *tagged* rules, and `rule-metrics-aggregate.sh` no-ops in a worktree because the incidents log is operator-machine-local. Pruning descoped pending a trustworthy denominator.
- The gate already fires — lefthook + `test-all.sh` -> `ci.yml` `test-scripts` -> the required `test` check; unit case T2 proves exit 1 above 23000. The issue's "more urgent half" needed no fix. What IS CI-blind is the sync guard (`lint-agents-compound-sync.sh`), lefthook-only — the real gap this plan wires up.
- The drift is wider than reported and includes a live bug. Root cause is commit `d475c4e46` raising 22000->23000 without sweeping. The same stale 18000 sits in the live weekly Inngest promote cron (enabled since 2026-07-06, cron `0 0 * * 0`), as both the LLM proposal hint and a post-apply revert gate — so the `agents-core` tier has refused 100% of clusters every tick. Fixing it restores correct behaviour, not capacity (~27 B raw headroom); that honesty is pinned as an AC.
- Design: linter constants stay the authority; extend the existing sync guard rather than adding a cross-language JSON. A shared JSON would put a config read on the promotion execution path, trading a static problem a lint solves for free against a new runtime failure mode.
- Review changed the plan materially in four places: the originating file would have exited the sync graph (P0); the `emit_incident` telemetry block sat inside the replaced span un-retained (P0); `2>&1` is load-bearing because WARN/REJECT go to stderr and the tree is in WARN; remediation guidance re-tiered onto WARN since REJECT means the commit is already blocked.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agent: Explore x2 (test-surface/threshold inventory; 14-claim adversarial verification, all CONFIRMED)
- Agent: soleur:engineering:review:architecture-strategist
- Agent: soleur:engineering:review:code-simplicity-reviewer
- Agent: soleur:product:spec-flow-analyzer
- Deepen-plan gates 4.5-4.9 (all pass)
