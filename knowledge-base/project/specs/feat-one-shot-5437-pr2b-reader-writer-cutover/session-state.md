# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-17-refactor-adr-044-pr2b-reader-writer-cutover-plan.md
- Status: complete

### Errors
None. (gh `--json merged` unsupported in this gh version — worked around with `--json state`; non-blocking.)

### Decisions
- Cron join: Shape B (two-query) — scan workspaces.repo_status='ready' → collect ids → fetch users.kb_sync_history via .in("id", ids) (solo workspaces.id==users.id, ADR-038 N2). repo_url carried in a Map from the workspaces Step-A rows. kb_sync_history stays a users read (users-only, mig 017).
- provisionWorkspace side effect preserved at all 3 sites; only the return-value write to users.workspace_path is removed. api/workspace/route.ts KEEPS `const workspacePath` (consumed by the JSON response at :72); callback sites drop the local.
- Latent-bug fix is bidirectional (newly-connected users now caught; stale-ready users now correctly excluded). Both tested.
- AC7 mandates a per-table eq spy (the shared eqSpy can't prove the readiness filter moved to the workspaces chain) — single-user-incident class.
- Ref #5437 (NOT Closes) — umbrella stays open for the actual column DROP. Orthogonal open #3739 (observability-DRY) acknowledged, different lines.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: Explore (6/6 live-claim CONFIRM), spec-flow-analyzer, data-integrity-guardian
- Deepen hard gates 4.6/4.7/4.8/4.9 all passed/skipped correctly
