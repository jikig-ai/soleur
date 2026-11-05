# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-05-fix-ci-claude-cli-pins-bun-1-4-4-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=1 (planner; rulings F1-F4)

### Errors
None blocking. collision-precheck exit 10 was this branch's own draft PR.

### Decisions
- CLI_VERSION -> exactly 2.1.311; no pin-table row edit (value-agnostic).
- claude-code-action -> v1.0.263 (tag-object SHA 3b7e1a45ca6f231c62605aabcf79e6a41b08c7da) in 4 workflows + constraint-scaffold template; no claude_code_version input exists.
- pen-cli lock: exact overrides entry for agent-sdk 0.3.311, gated on engine-contract-probe.sh.
- operator-digest pin v1.0.101 left out; follow-up issue.

### Components Invoked
soleur:plan, soleur:deepen-plan, learnings-researcher, cto
