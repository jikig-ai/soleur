# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-02-ci-rerule-observation-window-wall-ceilings-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Floor root cause documented but not reproduced under a GITHUB_TOKEN (probe live run forbidden by brief).

### Decisions
- Floor mismatch root cause: sweeper GITHUB_TOKEN lacks pull-requests permission, so the s4-drain label query returns issues only and floor stays pr3a. Fix (CTO ruled 2026-11-02): add `pull-requests: read` to the sweeper workflow plus a fail-closed probe check on pulls/11226, with replay rows and a workflow pin test.
- Ceilings P95_MAX=240, MAX_MAX=285 (CTO ruled 2026-11-02); row_ow_timeout pin must become `over 285`; fixtures 250 and 288.
- Sweeper exit codes: 0 posts PASS and closes tracker; 2 posts NOT YET; 3 posts CANNOT ESTABLISH; none but 0 closes.
- cto_spawns=0 in this run (rulings carried from the 2026-11-02 sessions).

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:engineering:cto (inside plan), learnings-researcher, technical-ruling-gate.sh, lint-guard-contract.py, collision-precheck.sh
